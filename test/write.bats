#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi.XXXXXX")"
  disk_test_setup_env
  TARGET_IMG="${WORK}/target.img"
  disk_test_fill "${TARGET_IMG}" 16 '\252'
  DEVICE="$(disk_test_attach "${TARGET_IMG}")"
  NAME="$(disk_test_name "${DEVICE}")"
  IMAGE="${WORK}/fat.img"
  disk_test_fat_image "${IMAGE}" 8 FIXTURE
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

write_with() {
  local answer="$1"
  local settings="$2"
  shift 2
  printf '%s\n' "${answer}" | disk_test_run_env "${settings}" kakikomi "$@"
}

@test "kakikomi copies a FAT image byte for byte and validates it" {
  # Arrange
  local settings=""

  # Act
  run write_with "${NAME}" "${settings}" "${IMAGE}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
  disk_test_same_prefix "${IMAGE}" "${TARGET_IMG}"
}

@test "kakikomi removes its mount guard once the disk is ejected" {
  # Arrange
  local settings=""

  # Act
  run write_with "${NAME}" "${settings}" "${IMAGE}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ ! -s "${KAKIKOMI_FSTAB}" ]]
}

@test "kakikomi keeps the fstab guard with KAKIKOMI_KEEP_GUARD and --release removes it" {
  # Arrange
  write_with "${NAME}" "KAKIKOMI_KEEP_GUARD=y" "${IMAGE}" "${DEVICE}" >/dev/null 2>&1
  local kept
  kept="$(cat "${KAKIKOMI_FSTAB}")"

  # Act
  run disk_test_run kakikomi --release

  # Assert
  [[ "${status}" -eq 0 ]]
  if [[ "${KAKIKOMI_TEST_OS}" == "Darwin" ]]; then
    [[ "${kept}" == *"UUID="*" none msdos rw,noauto"* ]]
  fi
  [[ ! -s "${KAKIKOMI_FSTAB}" ]]
}

@test "kakikomi refuses an image one byte larger than the disk" {
  # Arrange
  local big="${WORK}/big.img"
  disk_test_image "${big}" 16
  printf 'x' >>"${big}"

  # Act
  run write_with "${NAME}" "" "${big}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: the image needs 16777728 bytes and ${DEVICE} holds 16777216."* ]]
  local first
  first="$(disk_test_range_bytes "${TARGET_IMG}" 0 512)"
  [[ "${first}" == "aa" ]] || {
    printf "found bytes: %s\n" "${first}"
    false
  }
}

@test "kakikomi writes nothing when the confirmation is not the disk name" {
  # Arrange
  local answer="y"

  # Act
  run write_with "${answer}" "" "${IMAGE}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"cancelled, nothing was touched."* ]]
  local bytes
  bytes="$(disk_test_unique_bytes "${TARGET_IMG}")"
  [[ "${bytes}" == "aa" ]] || {
    printf "found bytes: %s\n" "${bytes}"
    false
  }
}

@test "kakikomi blanks the rest of a larger disk with KAKIKOMI_ZERO_TAIL" {
  # Arrange
  local settings="KAKIKOMI_ZERO_TAIL=y"

  # Act
  run write_with "${NAME}" "${settings}" "${IMAGE}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  local tail_bytes
  tail_bytes="$(disk_test_range_bytes "${TARGET_IMG}" 8388608 8388608)"
  [[ "${tail_bytes}" == "00" ]] || {
    printf "found bytes: %s\n" "${tail_bytes}"
    false
  }
}

@test "kakikomi leaves the old contents past the image without KAKIKOMI_ZERO_TAIL" {
  # Arrange
  local settings=""

  # Act
  run write_with "${NAME}" "${settings}" "${IMAGE}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"--zero-tail blanks it."* ]]
  local tail_bytes
  tail_bytes="$(disk_test_range_bytes "${TARGET_IMG}" 8388608 8388608)"
  [[ "${tail_bytes}" == "aa" ]] || {
    printf "found bytes: %s\n" "${tail_bytes}"
    false
  }
}

@test "kakikomi stopped mid-run leaves the first sectors blank" {
  # Arrange
  local big="${WORK}/random.img"
  local log="${WORK}/run.log"
  local inside="${WORK}/inside-chunk"
  disk_test_random_file "${big}" 2
  disk_test_shim dd "case \"\$*\" in */chunk\\ of=*${NAME}*) : >'${inside}'; sleep 1 ;; esac
exec \"\$REAL\" \"\$@\""
  printf '%s\n' "${NAME}" | disk_test_run_env "KAKIKOMI_CHUNK_TARGET_MS=1 KAKIKOMI_SLOW_FACTOR=1000" kakikomi "${big}" "${DEVICE}" >"${log}" 2>&1 &
  local runner="$!"
  local tries=0
  until [[ -e "${inside}" || "${tries}" -ge 6000 ]]; do
    sleep 0.1
    tries=$((tries + 1))
  done

  # Act
  pkill -TERM -f "^[^ ]*(sh|bash|dash|zsh)( --posix)? ${REPO_DIR}/bin/kakikomi ${big}"
  local status_code=0
  wait "${runner}" || status_code="$?"

  # Assert
  [[ "${status_code}" -ne 0 ]]
  grep -q "stopped: interrupted during write chunk" "${log}" || {
    cat "${log}"
    false
  }
  disk_test_detach "${DEVICE}"
  local head_bytes
  head_bytes="$(disk_test_range_bytes "${TARGET_IMG}" 0 1048576)"
  [[ "${head_bytes}" == "00" ]] || {
    printf "found bytes: %s\n" "${head_bytes}"
    false
  }
}

@test "kakikomi refuses a target that holds the running system" {
  # Arrange
  local boot
  boot="$(disk_test_call call_first_boot_disk)"

  # Act
  run disk_test_call disk_refuse_target "${boot}" "" ""

  # Assert
  [[ -n "${boot}" ]] || skip "no block device holds / on this host"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: ${boot} holds the running system, so it is never a target."* ]]
}

@test "kakikomi skips the read-back and keeps the image when KAKIKOMI_VERIFY=n" {
  # Arrange
  local settings="KAKIKOMI_VERIFY=n KAKIKOMI_DELETE=y"

  # Act
  run write_with "${NAME}" "${settings}" "${IMAGE}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"--delete is ignored because nothing was read back"* ]]
  [[ -f "${IMAGE}" ]]
}

@test "kakikomi moves the image to the Trash after it validated with KAKIKOMI_DELETE=y" {
  # Arrange
  local settings="KAKIKOMI_DELETE=y"

  # Act
  run write_with "${NAME}" "${settings}" "${IMAGE}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ ! -e "${IMAGE}" ]]
  [[ -f "${WORK}/Trash/fat.img" ]]
}

@test "kakikomi keeps an image that changed after it was hashed" {
  # Arrange
  local image="${IMAGE}"

  # Act
  run disk_test_call call_changed_source "${image}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"the image changed while it was being written, so it is kept."* ]]
  [[ -f "${image}" ]]
}

@test "kakikomi reports a mount that happened while it held the disk" {
  # Arrange
  disk_test_fat_image "${WORK}/mountable.img" 8 BREACH
  local mountable
  mountable="$(disk_test_attach "${WORK}/mountable.img")"

  # Act
  run disk_test_call call_breach "${mountable}" "${KAKIKOMI_TESTS_DIR}/mounter.sh"

  # Assert
  disk_test_detach "${mountable}"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"was mounted, so the system may have written to it."* ]]
}
