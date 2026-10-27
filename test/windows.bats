#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-windows.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
}

teardown() {
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

windows_iso() {
  command -v wimlib-imagex >/dev/null || skip "wimlib-imagex is not installed"
  command -v mformat >/dev/null || skip "mtools is not installed"
  ISO="${WORK}/win.iso"
  disk_test_windows_iso "${ISO}"
  disk_test_fill "${WORK}/target.img" 64 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="$(disk_test_name "${DEVICE}")"
}

laying_out() {
  printf '%s\n' "${NAME}" | disk_test_run_env "FAT32_MAX_FILE=1048576 ${1:-}" kakikomi "${ISO}" "${DEVICE}"
}

laying_out_on() {
  printf '%s\n' "${NAME}" | FAT32_MAX_FILE=1048576 disk_test_run_path "$1" kakikomi "${ISO}" "${DEVICE}"
}

@test "a disk up to 3 MiB gets a floppy filesystem by default" {
  # Arrange
  local size=3145728

  # Act
  run disk_test_call disk_default_fs "${size}"

  # Assert
  [[ "${output}" == "floppy" ]]
}

@test "a disk up to 32 GiB gets FAT32 by default" {
  # Arrange
  local size=34359738368

  # Act
  run disk_test_call disk_default_fs "${size}"

  # Assert
  [[ "${output}" == "fat32" ]]
}

@test "a disk over 32 GiB gets exFAT by default" {
  # Arrange
  local size=34360786944

  # Act
  run disk_test_call disk_default_fs "${size}"

  # Assert
  [[ "${output}" == "exfat" ]]
}

@test "an unknown system cannot build exFAT" {
  # Arrange
  export DISK_OS=FreeBSD

  # Act
  run disk_test_call disk_exfat_build "${WORK}/volume.img" LABEL

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "kakikomi lists an ISO with 7z when bsdtar is missing" {
  # Arrange
  command -v 7z >/dev/null || skip "7z is not installed"
  windows_iso
  local farm
  farm="$(disk_test_farm bsdtar)"

  # Act
  run laying_out_on "${farm}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"laid out as a UEFI-bootable FAT32 drive"* ]]
}

@test "kakikomi says when nothing can list an ISO" {
  # Arrange
  windows_iso
  local farm
  farm="$(disk_test_farm bsdtar 7z)"

  # Act
  run laying_out_on "${farm}"

  # Assert
  [[ "${output}" == *"neither bsdtar nor 7z is installed, so this ISO cannot be checked for a Windows installer."* ]]
}

@test "kakikomi extracts an ISO with bsdtar when 7z is missing" {
  # Arrange
  command -v bsdtar >/dev/null || skip "bsdtar is not installed"
  windows_iso
  local farm
  farm="$(disk_test_farm 7z)"

  # Act
  run laying_out_on "${farm}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"files read back identical from the new volume."* ]]
}

@test "kakikomi needs wimlib to split a large install.wim" {
  # Arrange
  windows_iso
  local farm
  farm="$(disk_test_farm wimlib-imagex)"

  # Act
  run laying_out_on "${farm}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: install.wim is over 4 GiB, which FAT32 cannot hold, and wimlib-imagex is needed to split it."* ]]
}

@test "kakikomi stops when install.wim cannot be split" {
  # Arrange
  windows_iso
  disk_test_shim wimlib-imagex "exit 1"

  # Act
  run laying_out

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: wimlib-imagex could not split install.wim."* ]]
}

@test "kakikomi needs mtools to build a Windows drive" {
  # Arrange
  windows_iso
  local farm
  farm="$(disk_test_farm mformat)"

  # Act
  run laying_out_on "${farm}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: building a Windows USB needs mtools."* ]]
}

@test "kakikomi stops when there is no room to lay the ISO out" {
  # Arrange
  windows_iso
  disk_test_shim df "printf 'Filesystem 1024-blocks Used Available Capacity Mounted\\nfake 10 10 0 100%% /\\n'"

  # Act
  run laying_out

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: laying out this ISO needs about"* ]]
}

@test "kakikomi stops when the ISO cannot be extracted" {
  # Arrange
  windows_iso
  disk_test_shim 7z "[ \"\$1\" = x ] && exit 1
exec \"\$REAL\" \"\$@\""
  disk_test_shim bsdtar "[ \"\$1\" = -xf ] && exit 1
exec \"\$REAL\" \"\$@\""

  # Act
  run laying_out

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: the ISO could not be extracted."* ]]
}

@test "kakikomi stops when the FAT32 volume cannot be built" {
  # Arrange
  windows_iso
  disk_test_shim mformat "exit 1"

  # Act
  run laying_out

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: the FAT32 volume could not be created."* ]]
}

@test "kakikomi stops when the installer files cannot be copied" {
  # Arrange
  windows_iso
  disk_test_shim mcopy "case \"\$*\" in *-s*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run laying_out

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: copying the installer files into the FAT32 volume failed."* ]]
}

@test "kakikomi names the files that did not read back from the volume" {
  # Arrange
  windows_iso
  disk_test_shim mcopy "case \"\$*\" in *-n*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run laying_out

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: these files did not copy into the FAT32 volume intact:"* ]]
  [[ "${output}" == *"setup.exe"* ]]
}
