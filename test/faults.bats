#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-faults.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  TARGET_IMG="${WORK}/target.img"
  disk_test_fill "${TARGET_IMG}" 16 '\252'
  DEVICE="$(disk_test_attach "${TARGET_IMG}")"
  NAME="$(disk_test_name "${DEVICE}")"
  IMAGE="${WORK}/fat.img"
  disk_test_fat_image "${IMAGE}" 8 FIXTURE
  fake_install
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

writing() {
  printf '%s\n' "${NAME}" | disk_test_run_env "${1:-}" kakikomi "${IMAGE}" "${DEVICE}"
}

fake_dd() {
  local condition="$1"
  local action="$2"
  disk_test_shim dd "case \"\$*\" in
  ${condition}) ${action} ;;
esac
exec \"\$REAL\" \"\$@\""
}

pass_write() {
  fake_dd "*head-[0-9]*of=*${NAME}* | */chunk\\ of=*${NAME}*" "$1"
}

media_error="printf 'dd: error writing: Input/output error\\n' >&2; exit 1"

@test "kakikomi stops after three failed attempts at the same chunk" {
  # Arrange
  pass_write "${media_error}"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"failed 3 times at offset"* ]]
  [[ "${output}" == *"dd said: dd: error writing: Input/output error"* ]]
}

@test "kakikomi calls a media error on a Zip disk the click of death" {
  # Arrange
  fake_identity_as "ZIP 100"
  pass_write "${media_error}"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Handling this as fragile media"* ]]
  [[ "${output}" == *"did not come back clean at offset"* ]]
  [[ "${output}" == *"this is the click of death"* ]]
}

@test "kakikomi reports a chunk that only settled on a retry" {
  # Arrange
  local once="${WORK}/failed-once"
  pass_write "[ -e '${once}' ] || { : >'${once}'; ${media_error}; }"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"needed 2 attempts at offset"* ]]
  [[ "${output}" == *"chunks only settled on a retry"* ]]
}

@test "kakikomi stops at once when the drive leaves the bus" {
  # Arrange
  pass_write "printf 'dd: /dev/${NAME}: Device not configured\\n' >&2; exit 1"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped answering at offset"* ]]
}

@test "kakikomi says when the drive is gone from the bus after a fault" {
  # Arrange
  local gone
  gone="$(fake_dir)/gone"
  pass_write ": >'${gone}'; printf 'dd: /dev/${NAME}: Device not configured\\n' >&2; exit 1"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is no longer on the bus, so there is nothing left to eject by software."* ]]
}

@test "kakikomi stops a transfer that runs past its deadline" {
  # Arrange
  pass_write "sleep 5"

  # Act
  run writing "KAKIKOMI_DEADLINE_CAP_MS=2000"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"went silent for"* ]]
  [[ "${output}" == *"the drive stopped answering mid-transfer"* ]]
}

@test "kakikomi stops a transfer past its deadline when timeout reports a terminate" {
  # Arrange
  disk_test_shim timeout "while [ \"\$#\" -gt 0 ]; do
  case \"\$1\" in
    -k | -s) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
limit=\"\$1\"
shift
\"\$@\" &
child=\"\$!\"
( sleep \"\${limit}\"; kill -TERM \"\${child}\" ) >/dev/null 2>&1 &
watcher=\"\$!\"
status=0
wait \"\${child}\" || status=\"\$?\"
kill \"\${watcher}\" 2>/dev/null
exit \"\${status}\""
  pass_write "sleep 5"

  # Act
  run writing "KAKIKOMI_DEADLINE_CAP_MS=2000"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"went silent for"* ]]
  [[ "${output}" == *"the drive stopped answering mid-transfer"* ]]
}

@test "kakikomi writes through a dd that reports only record counts" {
  # Arrange
  disk_test_shim dd "err=\"\$(mktemp)\"
\"\$REAL\" \"\$@\" 2>\"\$err\"
status=\$?
grep -v bytes \"\$err\" >&2
rm -f \"\$err\"
exit \"\$status\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Wrote and verified every chunk of the image."* ]]
}

@test "kakikomi does not trust a dd whose only record count came up short" {
  # Arrange
  pass_write "\"\$REAL\" \"\$@\" 2>/dev/null; printf '0+1 records in\\n0+1 records out\\n' >&2; exit 0"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"moved 0 of"* ]]
}

@test "kakikomi stops at once when a transfer is interrupted" {
  # Arrange
  pass_write "exit 130"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: interrupted during"* ]]
}

@test "kakikomi does not trust a transfer that moved fewer bytes" {
  # Arrange
  pass_write "\"\$REAL\" \"\$@\" 2>/dev/null; printf '0+0 records in\\n0+0 records out\\n0 bytes transferred\\n' >&2; exit 0"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"moved 0 of"* ]]
}

@test "kakikomi names the bit lines of a byte that read back wrong" {
  # Arrange
  disk_test_shim dd "\"\$REAL\" \"\$@\"; status=\$?
case \"\$*\" in *if=*${NAME}*of=*readback*) printf '\\001' | \"\$REAL\" of=\"\$(printf '%s\\n' \"\$@\" | sed -n 's/^of=//p')\" bs=1 count=1 conv=notrunc 2>/dev/null ;; esac
exit \"\$status\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"did not read back as"* ]]
}

@test "kakikomi reads a refused write as write protection" {
  # Arrange
  pass_write "printf 'dd: /dev/${NAME}: Read-only file system\\n' >&2; exit 1"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"that reads as write protection rather than worn media."* ]]
}

@test "kakikomi stops when the disk fails while it is being measured" {
  # Arrange
  fake_dd "*pattern-*of=*${NAME}*" "${media_error}"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"the write probe failed on the first sectors of"* ]]
  [[ "${output}" == *"the disk failed while being measured"* ]]
}

@test "kakikomi refuses media whose writes silently do not land" {
  # Arrange
  disk_test_shim dd "case \"\$*\" in *write-probe\\ of=*${NAME}*) set -- \$(printf '%s\\n' \"\$@\" | sed 's|^of=.*|of=/dev/null|; /^seek=/d; /^oflag=/d') ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is write protected, so nothing on it can be written."* ]]
  [[ "${output}" == *"the drive accepted a test write and the media kept its previous contents."* ]]
}

@test "kakikomi bypasses the page cache when direct I/O works" {
  # Arrange
  [[ "${KAKIKOMI_TEST_OS}" == "Linux" ]] || skip "macOS reads the raw device, which never caches"
  disk_test_shim dd "set -- \$(printf '%s\\n' \"\$@\" | sed '/^iflag=direct\$/d; /^oflag=direct\$/d')
exec \"\$REAL\" \"\$@\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Bypassing the page cache so every chunk reaches the media."* ]]
}

@test "kakikomi waits on every transfer when the deadline cap is zero" {
  # Arrange
  local settings="KAKIKOMI_DEADLINE_CAP_MS=0"

  # Act
  run writing "${settings}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
}
