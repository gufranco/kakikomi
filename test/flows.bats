#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-flows.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
  EXTRA=""
}

teardown() {
  local device
  for device in ${DEVICE} ${EXTRA}; do
    disk_test_detach "${device}"
  done
  rm -rf "${WORK}"
}

attach() {
  local bytes="$1"
  { head -c "${bytes}" /dev/zero || true; } | LC_ALL=C tr '\000' '\252' >"${WORK}/target.img"
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="$(disk_test_name "${DEVICE}")"
}

answering() {
  local answers="$1"
  shift
  printf '%b' "${answers}" | DISK_INTERACTIVE=1 disk_test_run kakikomi "$@"
}

writing_with() {
  local settings="$1"
  local image="$2"
  printf '%s\n' "${NAME}" | disk_test_run_env "${settings}" kakikomi "${image}" "${DEVICE}"
}

@test "kakikomi menu writes the image it asks for" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1

  # Act
  run answering "1\n${WORK}/payload.img\n${NAME}\n\n\n\n${NAME}\n"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
}

@test "kakikomi stops when no target is picked" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1

  # Act
  run answering "\n" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: no target chosen."* ]]
}

@test "kakikomi menu formats the disk it asks for" {
  # Arrange
  attach 4194304

  # Act
  run answering "2\n${NAME}\nfat\nmenu\n\n\n${NAME}\n"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"a new fat filesystem named MENU"* ]]
}

@test "kakikomi format asks for exactly one disk" {
  # Arrange
  attach 4194304
  disk_test_fill "${WORK}/extra.img" 4 '\252'
  EXTRA="$(disk_test_attach "${WORK}/extra.img")"

  # Act
  run answering "1, 2\n" format

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: pick exactly one disk."* ]]
}

@test "kakikomi format needs mtools for a FAT filesystem" {
  # Arrange
  attach 4194304
  local farm
  farm="$(disk_test_farm mformat)"

  # Act
  run disk_test_run_path "${farm}" kakikomi format "${DEVICE}" fat </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: FAT formatting needs mtools."* ]]
}

@test "kakikomi format stops when the filesystem cannot be built" {
  # Arrange
  attach 4194304
  disk_test_shim mformat "exit 1"

  # Act
  run disk_test_run kakikomi format "${DEVICE}" fat </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: the fat filesystem could not be created."* ]]
}

@test "kakikomi format stops when the disk size cannot be read" {
  # Arrange
  attach 4194304
  fake_install
  fake_size_unknown

  # Act
  run disk_test_run kakikomi format "${DEVICE}" fat </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: unable to determine the size of ${DEVICE}."* ]]
}

@test "kakikomi warns that a small floppy image will not read on larger media" {
  # Arrange
  attach 1474560
  head -c 737280 /dev/urandom >"${WORK}/dd.ima"

  # Act
  run writing_with "" "${WORK}/dd.ima"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"a 720.0 KiB floppy image on 1.4 MiB media will not read in a drive built for the smaller format."* ]]
}

@test "kakikomi accepts a compressed image whose published SHA-256 is of its contents" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1
  local sha
  sha="$(disk_test_call disk_sha256_stdin <"${WORK}/payload.img")"
  gzip -c "${WORK}/payload.img" >"${WORK}/payload.img.gz"

  # Act
  run writing_with "SHA256=${sha}" "${WORK}/payload.img.gz"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"The image matches the expected SHA-256."* ]]
}

@test "kakikomi pads an image that ends inside a sector" {
  # Arrange
  attach 2097152
  head -c 1500000 /dev/urandom >"${WORK}/odd.img"

  # Act
  run writing_with "" "${WORK}/odd.img"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
}

@test "kakikomi stops when the image cannot be read partway" {
  # Arrange
  attach 4194304
  disk_test_random_file "${WORK}/payload.img" 3
  disk_test_shim dd "case \"\$*\" in *if=*payload.img*skip=[1-9]*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing_with "" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: the image could not be read at offset"* ]]
}

@test "kakikomi stops when the whole-disk read back does not match" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1
  disk_test_shim dd "case \"\$*\" in *if=*${NAME}\\ bs=1048576) printf 'X'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run writing_with "" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"does not hold the image. expected SHA-256"* ]]
}

@test "kakikomi keeps the image when the trash refuses it" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1
  printf '#!/bin/sh\nexit 1\n' >"${WORK}/refuse.sh"
  chmod +x "${WORK}/refuse.sh"

  # Act
  run writing_with "DELETE=y DISK_TRASH=${WORK}/refuse.sh" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -f "${WORK}/payload.img" ]]
  [[ "${output}" != *"to the Trash."* ]]
}

@test "kakikomi takes the default for an answer it does not recognize" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1

  # Act
  run answering "maybe\n\n\n${NAME}\n" "${WORK}/payload.img" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
}

@test "kakikomi skips the reinsertion check when the disk does not return" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1

  # Act
  run writing_with "REINSERT=y REINSERT_WAIT_SECONDS=1" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"the disk did not come back within 1s, so the reinsertion check was skipped."* ]]
}

@test "kakikomi stops when the system mounts the disk as it returns" {
  # Arrange
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1
  fake_install
  local log="${WORK}/run.log"
  printf '%s\n' "${NAME}" | disk_test_run_env "REINSERT=y" kakikomi "${WORK}/payload.img" "${DEVICE}" >"${log}" 2>&1 &
  local runner="$!"
  disk_test_wait_for "${log}" "plug it back in" 1200 || cat "${log}"

  # Act
  EXTRA="$(disk_test_attach "${WORK}/target.img")"
  printf '%s on /Volumes/BACK (msdos, local)\n/mnt/back\n' "${EXTRA}" >"$(fake_dir)/mounts"
  local status_code=0
  wait "${runner}" || status_code="$?"

  # Assert
  [[ "${status_code}" -eq 1 ]]
  grep -q "stopped: the system mounted ${EXTRA} when it came back." "${log}"
}

@test "kakikomi runs when called by name from PATH" {
  # Arrange
  local bin="${REPO_DIR}/bin"
  local -a shell_words
  read -r -a shell_words <<<"${DISK_SHELL:-sh}"

  # Act
  run bash -c 'cd "$1" && shift && PATH="$PWD:$PATH" "$@" kakikomi version' _ "${bin}" "${shell_words[@]}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == kakikomi\ * ]]
}

@test "kakikomi format names the package exFAT needs on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS builds exFAT with newfs_exfat"
  attach 4194304
  local farm
  farm="$(disk_test_farm mkfs.exfat)"

  # Act
  run disk_test_run_path "${farm}" kakikomi format "${DEVICE}" exfat </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: mkfs.exfat is not installed. install the exfatprogs package."* ]]
}

@test "kakikomi refuses an internal disk unless asked" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "an attached disk image is always external on macOS"
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1
  unset ALLOW_INTERNAL

  # Act
  run disk_test_run kakikomi "${WORK}/payload.img" "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: ${DEVICE} is an internal disk. use --allow-internal to write to it on purpose."* ]]
}

@test "kakikomi refuses to write over the disk that holds the image" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KKHOLD
  local folder
  case "${DISK_TEST_OS}" in
  Darwin)
    local listing
    listing="$(hdiutil attach "${WORK}/fat.img")"
    DEVICE="${listing%%[[:space:]]*}"
    folder="$(printf '%s\n' "${listing}" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
    disk_test_random_file "${folder}/payload.img" 1
    ;;
  *)
    DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
    disk_test_partition_nodes_start
    folder="${WORK}/mnt"
    mkdir -p "${folder}"
    disk_test_wait_partition "${DEVICE}p1"
    sudo mount "${DEVICE}p1" "${folder}"
    disk_test_random_file "${WORK}/payload.img" 1
    sudo cp -f "${WORK}/payload.img" "${folder}/payload.img"
    ;;
  esac

  # Act
  run disk_test_run kakikomi "${folder}/payload.img" "${DEVICE}" </dev/null

  # Assert
  case "${DISK_TEST_OS}" in
  Darwin) hdiutil detach -force "${DEVICE}" >/dev/null 2>&1 || true ;;
  *) sudo umount "${folder}" >/dev/null 2>&1 || true ;;
  esac
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is stored on ${DEVICE}, so writing would destroy the image mid-copy."* ]]
}

@test "kakikomi stops when the system cannot be kept from mounting the disk on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS guards through the fstab"
  attach 2097152
  disk_test_random_file "${WORK}/payload.img" 1
  disk_test_shim tee "exit 1"

  # Act
  run writing_with "" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: could not stop the system from mounting ${DEVICE}."* ]]
}

@test "kakikomi stops a chunk that finishes after an interrupt" {
  # Arrange
  attach 4194304
  disk_test_random_file "${WORK}/payload.img" 3
  mkdir -p "${WORK}/tmp"
  disk_test_shim dd "\"\$REAL\" \"\$@\"; status=\$?
case \"\$*\" in */chunk\\ of=*${NAME}*)
  for work in '${WORK}'/tmp/disk_write_src.*; do : >\"\$work/stop\"; done ;;
esac
exit \"\$status\""

  # Act
  run writing_with "TMPDIR=${WORK}/tmp" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: interrupted during write chunk"* ]]
}

@test "kakikomi writes no further chunk once a stop arrives between chunks" {
  # Arrange
  attach 4194304
  disk_test_random_file "${WORK}/payload.img" 3
  mkdir -p "${WORK}/tmp"
  local armed="${WORK}/armed"
  disk_test_shim dd "case \"\$*\" in *of=*readback*) : >'${armed}' ;; esac
exec \"\$REAL\" \"\$@\""
  disk_test_shim perl "if [ -e '${armed}' ]; then
  for work in '${WORK}'/tmp/disk_write_src.*; do : >\"\$work/stop\"; done
fi
exec \"\$REAL\" \"\$@\""

  # Act
  run writing_with "TMPDIR=${WORK}/tmp" "${WORK}/payload.img"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: interrupted during write chunk"* ]]
}
