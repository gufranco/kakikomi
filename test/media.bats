#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-media.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  disk_test_fill "${WORK}/target.img" 4 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="$(disk_test_name "${DEVICE}")"
  IMAGE="${WORK}/payload.img"
  disk_test_random_file "${IMAGE}" 2
  fake_install
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

writing() {
  printf '%s\n' "${NAME}" | disk_test_run_env "${1:-}" kakikomi "${IMAGE}" "${DEVICE}"
}

pass_fault() {
  disk_test_shim dd "case \"\$*\" in *head-[0-9]*of=*${NAME}* | */chunk\\ of=*${NAME}*) printf 'dd: error writing: Input/output error\\n' >&2; exit 1 ;; esac
exec \"\$REAL\" \"\$@\""
}

@test "kakikomi stops on media the drive reports as read-only" {
  # Arrange
  fake_read_only

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is write protected, so nothing on it can be written."* ]]
  [[ "${output}" == *"the drive reports this media as read-only."* ]]
  [[ "${output}" == *"Release the write-protect switch or lock on the device"* ]]
}

@test "kakikomi tells how to unprotect a floppy" {
  # Arrange
  fake_read_only
  fake_identity_as "TEAC USB-FDU"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Cover the square hole on the corner of the disk"* ]]
}

@test "kakikomi tells how to unprotect a Zip cartridge" {
  # Arrange
  fake_read_only
  fake_identity_as "ZIP 100"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Unlock the cartridge, through the Iomega tools or its write-protect tab"* ]]
}

@test "kakikomi goes on when the drive gives no write-protect answer" {
  # Arrange
  printf '<string>unknown</string>\n' >"$(fake_dir)/plist/WritableMedia"
  disk_test_shim blockdev "case \"\$*\" in *--getro*) printf 'unknown\\n'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" != *"write protected"* ]]
}

@test "kakikomi stops when the disk size cannot be read" {
  # Arrange
  fake_size_unknown

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: unable to determine the size of ${DEVICE}."* ]]
}

@test "kakikomi stops when the disk stays mounted" {
  # Arrange
  fake_flag unmount-fails
  printf '%s on /Volumes/FAKE (msdos, local)\n' "${DEVICE}" >"$(fake_dir)/mounts"
  printf '/mnt/fake\n' >>"$(fake_dir)/mounts"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"disk is still mounted, so writing to it would corrupt the mounted volume"* ]]
}

@test "kakikomi stops when the mount state cannot be read" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS reads the mount table directly"
  fake_flag mount-state-fails

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"unable to read the mount state of ${DEVICE}, so this stops here"* ]]
}

@test "kakikomi falls back to unmounting when the drive refuses to eject after a fault" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux has no separate unmount fallback"
  fake_flag eject-fails
  pass_fault

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"the drive refused to eject. the volume is unmounted, so nothing else will touch it."* ]]
}

@test "kakikomi says to cut power when the drive will not let go after a fault" {
  # Arrange
  fake_flag eject-fails
  fake_flag unmount-fails
  pass_fault

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"cut power to the drive before doing anything else with it."* ]]
}

@test "kakikomi ejects the cartridge after a fault on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "a disk image on macOS ejects through diskutil"
  disk_test_shim eject "exit 0"
  pass_fault

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Cartridge ejected."* ]]
}

@test "kakikomi ejects the drive once the write is validated on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "a disk image on macOS ejects through diskutil"
  disk_test_shim eject "exit 0"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Ejected. ${DEVICE} is safe to remove."* ]]
}

@test "kakikomi keeps the guard when the drive will not eject at the end" {
  # Arrange
  fake_flag eject-fails

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"did not eject; it stays unmounted and guarded. remove it once the light stops."* ]]
  [[ "${output}" == *"is still attached, so the mount guard stays."* ]]
}

@test "kakikomi asks for a floppy to be taken out by hand" {
  # Arrange
  fake_identity_as "TEAC USB-FDU"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. This drive has no software eject, so take the disk out now."* ]]
}

@test "kakikomi stops when administrator access is refused" {
  # Arrange
  disk_test_shim sudo "case \"\$1\" in
  -n) [ \"\${2:-}\" = true ] && exit 1 ;;
  -v) exit 1 ;;
esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Administrator access is required to reach the raw device."* ]]
  [[ "${output}" == *"kakikomi: administrator access was not granted."* ]]
}

@test "kakikomi continues once administrator access is granted" {
  # Arrange
  disk_test_shim sudo "case \"\$1\" in
  -n) [ \"\${2:-}\" = true ] && exit 1 ;;
  -v) exit 0 ;;
esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Administrator access is required to reach the raw device."* ]]
}
