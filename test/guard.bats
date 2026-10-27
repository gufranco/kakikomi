#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-guard.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
}

teardown() {
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

craft() {
  local file="$1"
  local size="$2"
  local writes="$3"
  python3 -c '
import struct, sys
path, size, writes = sys.argv[1], int(sys.argv[2]), sys.argv[3]
data = bytearray(size)
for item in writes.split():
    offset, hexbytes = item.split("=")
    raw = bytes.fromhex(hexbytes)
    data[int(offset):int(offset) + len(raw)] = raw
open(path, "wb").write(bytes(data))
' "${file}" "${size}" "${writes}"
}

gpt_header() {
  local entries="$1"
  printf '512=4546492050415254 584=0200000000000000 592=%02x000000 596=80000000' "${entries}"
}

signature="510=55aa"

writing() {
  printf '%s\n' "${NAME}" | disk_test_run_env "${1:-}" kakikomi "${IMAGE}" "${DEVICE}"
}

fat_target() {
  disk_test_fat_image "${WORK}/fat.img" 8 GUARDED
  IMAGE="${WORK}/fat.img"
  disk_test_fill "${WORK}/target.img" 16 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="$(disk_test_name "${DEVICE}")"
}

@test "a GPT image lists the start of each partition it holds" {
  # Arrange
  local header
  header="$(gpt_header 2)"
  craft "${WORK}/gpt.img" 65536 "450=ee ${signature} ${header} 1024=a2a0d0ebe5b9334487c068b6b72699c7 1056=0008000000000000"

  # Act
  run disk_test_call call_partition_starts "${WORK}/gpt.img"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == $'1048576\nunsupported=' ]]
}

@test "a GPT image holding APFS is flagged as unsupported" {
  # Arrange
  local header
  header="$(gpt_header 1)"
  craft "${WORK}/apfs.img" 65536 "450=ee ${signature} ${header} 1024=ef57347c0000aa11aa1100306543ecac"

  # Act
  run disk_test_call call_partition_starts "${WORK}/apfs.img"

  # Assert
  [[ "${output}" == "unsupported=APFS" ]]
}

@test "a protective MBR without a GPT header lists nothing" {
  # Arrange
  craft "${WORK}/broken.img" 65536 "450=ee ${signature}"

  # Act
  run disk_test_call call_partition_starts "${WORK}/broken.img"

  # Assert
  [[ "${output}" == "unsupported=" ]]
}

@test "an MBR image holding HFS+ is flagged as unsupported" {
  # Arrange
  craft "${WORK}/hfs.img" 65536 "450=af 454=00080000 ${signature}"

  # Act
  run disk_test_call call_partition_starts "${WORK}/hfs.img"

  # Assert
  [[ "${output}" == "unsupported=HFS+" ]]
}

@test "an extended partition chain lists every logical partition it reaches" {
  # Arrange
  local base=1048576
  local second=$((base + 2048 * 512))
  craft "${WORK}/ebr.img" $((second + 512)) "450=05 454=00080000 ${signature} $((base + 450))=83 $((base + 454))=3f000000 $((base + 466))=05 $((base + 470))=00080000 $((base + 510))=55aa $((second + 466))=05 $((second + 470))=00040000 $((second + 510))=55aa"

  # Act
  run disk_test_call call_partition_starts "${WORK}/ebr.img"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == $'1080832\nunsupported=' ]]
}

@test "the fstab guard is written to a new fstab" {
  # Arrange
  export DISK_FSTAB="${WORK}/etc/fstab.new"
  mkdir -p "${WORK}/etc"
  export TMPDIR="${WORK}"

  # Act
  run disk_test_call call_fstab_append disk9 "UUID=1234 none msdos rw,noauto"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == $'# kakikomi disk9 begin\nUUID=1234 none msdos rw,noauto\n# kakikomi disk9 end' ]]
}

@test "a lock left by a process that ended is taken over" {
  # Arrange
  export TMPDIR="${WORK}"
  mkdir -p "${WORK}/kakikomi-fstab.lock"
  printf '999999\n' >"${WORK}/kakikomi-fstab.lock/pid"

  # Act
  run disk_test_call call_fstab_append disk9 "UUID=1234 none msdos rw,noauto"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"# kakikomi disk9 end"* ]]
}

@test "a lock held by a running kakikomi leaves the fstab untouched" {
  # Arrange
  export TMPDIR="${WORK}" FSTAB_LOCK_SECONDS=1
  mkdir -p "${WORK}/kakikomi-fstab.lock"
  printf '%s\n' "$$" >"${WORK}/kakikomi-fstab.lock/pid"

  # Act
  run disk_test_call call_fstab_append disk9 "UUID=1234 none msdos rw,noauto"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"another kakikomi held ${WORK}/kakikomi-fstab.lock for 1s, so the fstab was left untouched."* ]]
  [[ ! -s "${DISK_FSTAB}" ]]
}

@test "kakikomi --release says when no guard is left" {
  # Arrange
  printf 'LABEL=OTHER none msdos rw,noauto\n' >"${DISK_FSTAB}"

  # Act
  run disk_test_run kakikomi --release

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No mount guard was left in ${DISK_FSTAB}."* ]]
}

@test "kakikomi guards a volume by label when it has no UUID" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "the fstab guard exists only on macOS"
  fat_target
  fake_install
  printf '<string></string>\n' >"$(fake_dir)/plist/VolumeUUID"

  # Act
  run writing "KEEP_GUARD=y"

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -q '^LABEL=GUARDED none msdos rw,noauto$' "${DISK_FSTAB}"
}

@test "kakikomi stops when a volume has neither a UUID nor a label" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "the fstab guard exists only on macOS"
  fat_target
  fake_install
  printf '<string></string>\n' >"$(fake_dir)/plist/VolumeUUID"
  printf '<string></string>\n' >"$(fake_dir)/plist/VolumeName"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"volume in this image has neither a UUID nor a label"* ]]
  [[ "${output}" == *"could not stop the system from mounting ${DEVICE}, so its first sectors stay blank."* ]]
}

@test "kakikomi stops when the probe image will not attach" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "the fstab guard exists only on macOS"
  fat_target
  disk_test_shim hdiutil "case \"\$*\" in attach*probe.img*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"could not stop the system from mounting ${DEVICE}, so its first sectors stay blank."* ]]
}

@test "kakikomi stops when the fstab cannot be written" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "the fstab guard exists only on macOS"
  fat_target

  # Act
  run writing "DISK_FSTAB=${WORK}/missing/fstab"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"could not stop the system from mounting ${DEVICE}, so its first sectors stay blank."* ]]
}

@test "kakikomi refuses an image holding an HFS+ partition" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "the fstab guard exists only on macOS"
  craft "${WORK}/hfs.img" 2097152 "450=af 454=00080000 ${signature}"
  IMAGE="${WORK}/hfs.img"
  disk_test_fill "${WORK}/target.img" 4 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="$(disk_test_name "${DEVICE}")"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: this image holds an HFS+ partition, whose volume identity cannot be read from its header alone."* ]]
}

@test "kakikomi keeps the guard when the write fails after it was declared" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "the fstab guard exists only on macOS"
  fat_target
  disk_test_shim dd "case \"\$*\" in *if=*${NAME}\\ bs=1048576) printf 'X'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"the mount guard for ${DEVICE} stays in place. run kakikomi --release once the disk is out."* ]]
  grep -q "# kakikomi ${DEVICE##*/} begin" "${DISK_FSTAB}"
}

@test "an extended partition chain that loops on itself stops after a bounded walk" {
  # Arrange
  local base=1048576
  local self=$((base + 2048 * 512))
  craft "${WORK}/loop.img" $((self + 512)) "450=05 454=00080000 ${signature} $((base + 466))=05 $((base + 470))=00080000 $((base + 510))=55aa $((self + 466))=05 $((self + 470))=00080000 $((self + 510))=55aa"

  # Act
  run disk_test_call call_partition_starts "${WORK}/loop.img"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "unsupported=" ]]
}
