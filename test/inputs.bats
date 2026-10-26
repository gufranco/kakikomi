#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-inputs.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  export XDG_CACHE_HOME="${WORK}/cache"
}

teardown() {
  rm -rf "${WORK}"
}

magic_file() {
  local file="$1"
  local head="$2"
  printf '%b' "${head}" >"${file}"
  head -c 4096 /dev/zero >>"${file}"
}

trailer_file() {
  local file="$1"
  local tail="$2"
  head -c 4096 /dev/zero >"${file}"
  printf '%b' "${tail}" >>"${file}"
  head -c $((512 - ${#tail})) /dev/zero >>"${file}"
}

opening() {
  disk_test_run kakikomi "$1" /dev/null </dev/null
}

@test "a KDMV header is a vmdk image" {
  # Arrange
  magic_file "${WORK}/disk.vmdk" 'KDMV'

  # Act
  run disk_test_call disk_source_kind "${WORK}/disk.vmdk"

  # Assert
  [[ "${output}" == "vmdk" ]]
}

@test "a vhdxfile header is a vhdx image" {
  # Arrange
  magic_file "${WORK}/disk.vhdx" 'vhdxfile'

  # Act
  run disk_test_call disk_source_kind "${WORK}/disk.vhdx"

  # Assert
  [[ "${output}" == "vhdx" ]]
}

@test "a conectix footer is a vhd image" {
  # Arrange
  trailer_file "${WORK}/disk.vhd" 'conectix'

  # Act
  run disk_test_call disk_source_kind "${WORK}/disk.vhd"

  # Assert
  [[ "${output}" == "vhd" ]]
}

@test "a koly trailer is a dmg image" {
  # Arrange
  trailer_file "${WORK}/disk.dmg" 'koly'

  # Act
  run disk_test_call disk_source_kind "${WORK}/disk.dmg"

  # Assert
  [[ "${output}" == "dmg" ]]
}

@test "a text descriptor is a vmdk image" {
  # Arrange
  printf '# Disk DescriptorFile\nversion=1\n' >"${WORK}/disk.vmdk"

  # Act
  run disk_test_call disk_source_kind "${WORK}/disk.vmdk"

  # Assert
  [[ "${output}" == "vmdk" ]]
}

@test "a raw image has no decompressor" {
  # Arrange
  local kind=raw

  # Act
  run disk_test_call disk_decompressor "${kind}"

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "the hash falls back to shasum without sha256sum" {
  # Arrange
  command -v shasum >/dev/null || skip "shasum is not installed"
  local farm
  farm="$(disk_test_farm sha256sum)"

  # Act
  run disk_test_call_path "${farm}" disk_hash_tool

  # Assert
  [[ "${output}" == "shasum" ]]
}

@test "the hash falls back to openssl without sha256sum or shasum" {
  # Arrange
  local farm
  farm="$(disk_test_farm sha256sum shasum)"

  # Act
  run disk_test_call_path "${farm}" disk_sha256_stdin </dev/null

  # Assert
  [[ "${output}" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]
}

@test "the hash through shasum matches the known empty digest" {
  # Arrange
  command -v shasum >/dev/null || skip "shasum is not installed"
  local farm
  farm="$(disk_test_farm sha256sum)"

  # Act
  run disk_test_call_path "${farm}" disk_sha256_stdin </dev/null

  # Assert
  [[ "${output}" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]
}

@test "kakikomi says when the image does not exist" {
  # Arrange
  local missing="${WORK}/missing.img"

  # Act
  run opening "${missing}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: Image not found: ${missing}"* ]]
}

@test "kakikomi refuses an empty image" {
  # Arrange
  : >"${WORK}/empty.img"

  # Act
  run opening "${WORK}/empty.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is empty or its size could not be read."* ]]
}

@test "kakikomi names the decompressor a compressed image needs" {
  # Arrange
  disk_test_random_file "${WORK}/disk.img" 1
  gzip -c "${WORK}/disk.img" >"${WORK}/disk.img.gz"
  local farm
  farm="$(disk_test_farm gzip)"

  # Act
  run disk_test_run_path "${farm}" kakikomi "${WORK}/disk.img.gz" /dev/null </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: gzip is needed to read this gzip image."* ]]
}

@test "kakikomi needs bsdtar for a zip image" {
  # Arrange
  magic_file "${WORK}/disk.zip" 'PK\003\004'
  local farm
  farm="$(disk_test_farm bsdtar)"

  # Act
  run disk_test_run_path "${farm}" kakikomi "${WORK}/disk.zip" /dev/null </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: bsdtar is needed to read a zip image."* ]]
}

@test "kakikomi refuses a zip archive it cannot read" {
  # Arrange
  command -v bsdtar >/dev/null || skip "bsdtar is not installed"
  magic_file "${WORK}/disk.zip" 'PK\003\004'

  # Act
  run opening "${WORK}/disk.zip"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"could not be read as a zip archive."* ]]
}

@test "kakikomi names the converter a virtual disk needs" {
  # Arrange
  magic_file "${WORK}/disk.vmdk" 'KDMV'
  local farm
  farm="$(disk_test_farm qemu-img)"

  # Act
  run disk_test_run_path "${farm}" kakikomi "${WORK}/disk.vmdk" /dev/null </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: a vmdk image needs qemu-img to become a raw image"* ]]
}

@test "kakikomi names the converter a dmg image needs" {
  # Arrange
  trailer_file "${WORK}/disk.dmg" 'koly'
  local farm
  farm="$(disk_test_farm hdiutil)"

  # Act
  run disk_test_run_path "${farm}" kakikomi "${WORK}/disk.dmg" /dev/null </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: a dmg image needs hdiutil to become a raw image"* ]]
}

@test "kakikomi stops when a virtual disk will not fit in the work directory" {
  # Arrange
  magic_file "${WORK}/disk.vmdk" 'KDMV'
  disk_test_shim qemu-img "exit 0"
  disk_test_shim df "printf 'Filesystem 1024-blocks Used Available Capacity Mounted\\nfake 10 10 0 100%% /\\n'"

  # Act
  run opening "${WORK}/disk.vmdk"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"free bytes in"* ]]
}

@test "kakikomi stops when a virtual disk cannot be converted" {
  # Arrange
  magic_file "${WORK}/disk.vmdk" 'KDMV'
  disk_test_shim qemu-img "exit 1"

  # Act
  run opening "${WORK}/disk.vmdk"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: qemu-img could not convert"* ]]
}

@test "kakikomi needs curl to download an image" {
  # Arrange
  local farm
  farm="$(disk_test_farm curl)"

  # Act
  run disk_test_run_path "${farm}" kakikomi "https://example.invalid/disk.img" /dev/null </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"curl is required to download https://example.invalid/disk.img"* ]]
}

@test "kakikomi writes nothing when a download fails" {
  # Arrange
  disk_test_shim curl "exit 22"

  # Act
  run opening "https://example.invalid/disk.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: the download of https://example.invalid/disk.img failed, so nothing was written."* ]]
}

@test "kakikomi converts a dmg image to raw with hdiutil" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "hdiutil ships with macOS only"
  mkdir -p "${WORK}/folder"
  printf 'payload\n' >"${WORK}/folder/file.txt"
  hdiutil create -srcfolder "${WORK}/folder" -format UDZO -o "${WORK}/disk.dmg" >/dev/null

  # Act
  run opening "${WORK}/disk.dmg"

  # Assert
  [[ "${output}" == *"Converting the dmg image to raw so it can be written and verified byte for byte."* ]]
  [[ "${output}" != *"could not convert"* ]]
}

@test "kakikomi stops when hdiutil cannot convert a dmg image" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "hdiutil ships with macOS only"
  mkdir -p "${WORK}/folder"
  printf 'payload\n' >"${WORK}/folder/file.txt"
  hdiutil create -srcfolder "${WORK}/folder" -format UDZO -o "${WORK}/disk.dmg" >/dev/null
  disk_test_shim hdiutil "[ \"\$1\" = convert ] && exit 1
exec \"\$REAL\" \"\$@\""

  # Act
  run opening "${WORK}/disk.dmg"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: hdiutil could not convert ${WORK}/disk.dmg."* ]]
}

@test "kakikomi refuses a target that is not a block device" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS reports a device node for every mounted volume"
  disk_test_random_file "${WORK}/disk.img" 1

  # Act
  run disk_test_run kakikomi "${WORK}/disk.img" /dev/shm </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: Device not found or invalid: "* ]]
}
