#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-system.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
  MOUNTED=""
}

teardown() {
  disk_test_partition_nodes_stop
  if [[ -n "${MOUNTED}" ]]; then
    case "${DISK_TEST_OS}" in
    Darwin) hdiutil detach -force "${MOUNTED}" >/dev/null 2>&1 || true ;;
    *) sudo umount "${MOUNTED}" >/dev/null 2>&1 || true ;;
    esac
  fi
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

payload() {
  disk_test_random_file "${WORK}/payload.img" 1
  printf '%s\n' "${WORK}/payload.img"
}

writing() {
  local image name
  image="$(payload)"
  name="$(disk_test_name "${DEVICE}")"
  printf '%s\n' "${name}" | disk_test_run kakikomi "${image}" "${DEVICE}"
}

declining() {
  local image
  image="$(payload)"
  printf 'n\n' | disk_test_run kakikomi "${image}" "$1"
}

picking() {
  printf '%s\nn\n' "$1" | DISK_INTERACTIVE=1 disk_test_run kakikomi "$2"
}

real_timeout() {
  command -v timeout || command -v gtimeout
}

wait_for_node() {
  local tries=0
  until [[ -b "$1" || "${tries}" -ge 50 ]]; do
    sleep 0.1
    tries=$((tries + 1))
  done
}

@test "a bounded command past its limit is stopped without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 1 sleep 5

  # Assert
  [[ "${status}" -eq 124 ]]
}

@test "a bounded command within its limit keeps its status without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 3 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a bounded command uses gtimeout when timeout is missing" {
  # Arrange
  local runner
  runner="$(real_timeout)"
  disk_test_shim gtimeout "exec '${runner}' \"\$@\""
  local farm
  farm="$(disk_test_farm timeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 3 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a millisecond bound uses gtimeout when timeout is missing" {
  # Arrange
  local runner
  runner="$(real_timeout)"
  disk_test_shim gtimeout "exec '${runner}' \"\$@\""
  local farm
  farm="$(disk_test_farm timeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded_ms 1500 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a millisecond bound falls back to whole seconds without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded_ms 1500 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "the clock still reads without perl" {
  # Arrange
  disk_test_shim perl "exit 1"

  # Act
  run disk_test_call disk_now_ms

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "the clock falls back to whole seconds when date has no nanoseconds" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux reads /proc/uptime before date"
  disk_test_shim perl "exit 1"
  disk_test_shim date "case \"\$1\" in +%s%N) printf '%sN\\n' \"\$(\"\$REAL\" +%s)\"; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call disk_now_ms

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^[0-9]+000$ ]]
}

@test "the sector size falls back to 512 bytes when the drive does not say" {
  # Arrange
  disk_test_fill "${WORK}/target.img" 2 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  fake_install
  printf '/Device Block Size:/d\n' >"$(fake_dir)/info.sed"
  disk_test_shim blockdev "case \"\$*\" in *--getss*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call disk_sector_bytes "${DEVICE}"

  # Assert
  [[ "${output}" == "512" ]]
}

@test "an unknown system cannot release a disk" {
  # Arrange
  export DISK_OS=FreeBSD

  # Act
  run disk_test_call disk_release /dev/da0

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "an unknown system treats every disk as internal" {
  # Arrange
  export DISK_OS=FreeBSD

  # Act
  run disk_test_call disk_is_internal /dev/da0

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a working directory that cannot be made stops with a message" {
  # Arrange
  export TMPDIR="${BATS_TMPDIR:-/tmp}/kakikomi-missing-${RANDOM}/deeper"

  # Act
  run disk_test_call disk_make_tmpdir kakikomi

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: Unable to create a working directory"* ]]
}

@test "doctor marks a missing required tool and a missing pair" {
  # Arrange
  local farm
  farm="$(disk_test_farm dd sha256sum shasum)"

  # Act
  run disk_test_run_path "${farm}" kakikomi doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +missing\ +required ]]
  [[ "${output}" =~ (^|$'\n')sha256sum\|shasum\ +missing\ +validates ]]
}

@test "doctor passes with only optional tools missing" {
  # Arrange
  local farm
  farm="$(disk_test_farm xz bsdtar 7z)"

  # Act
  run disk_test_run_path "${farm}" kakikomi doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ (^|$'\n')xz\ +missing\ +needed ]]
  [[ "${output}" =~ (^|$'\n')bsdtar\|7z\ +missing\ +needed ]]
}

@test "kakikomi refuses a path that is neither a device nor a mount point" {
  # Arrange
  local image
  image="$(payload)"
  local file="${WORK}/not-a-disk"
  : >"${file}"

  # Act
  run disk_test_run kakikomi "${image}" "${file}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: Not a device or mount point: ${file}"* ]]
}

@test "kakikomi refuses a folder that is not a mount point" {
  # Arrange
  local image
  image="$(payload)"
  local folder="${WORK}/folder"
  mkdir -p "${folder}"

  # Act
  run disk_test_run kakikomi "${image}" "${folder}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: No device found for mount point: ${folder}"* ]]
}

@test "kakikomi resolves a mount point to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KAKIKOMIMNT
  local mount_point
  case "${DISK_TEST_OS}" in
  Darwin)
    local listing
    listing="$(hdiutil attach "${WORK}/fat.img")"
    DEVICE="${listing%%[[:space:]]*}"
    MOUNTED="${DEVICE}"
    mount_point="$(printf '%s\n' "${listing}" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
    ;;
  *)
    DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
    disk_test_partition_nodes_start
    mount_point="${WORK}/mnt"
    mkdir -p "${mount_point}"
    wait_for_node "${DEVICE}p1"
    sudo mount "${DEVICE}p1" "${mount_point}"
    MOUNTED="${mount_point}"
    ;;
  esac

  # Act
  run declining "${mount_point}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Target: ${DEVICE}"* ]]
}

@test "kakikomi resolves a partition to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KAKIKOMIPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  local partition
  case "${DISK_TEST_OS}" in
  Darwin) partition="${DEVICE}s1" ;;
  *) partition="${DEVICE}p1" ;;
  esac
  wait_for_node "${partition}"

  # Act
  run declining "${partition}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Target: ${DEVICE}"* ]]
}

@test "kakikomi writes a disk the system had mounted without calling it a breach" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux mounts are covered by the partition and whole-disk tests"
  disk_test_fat_image "${WORK}/fat.img" 8 KAKIKOMIAUTO
  local listing
  listing="$(hdiutil attach "${WORK}/fat.img")"
  DEVICE="${listing%%[[:space:]]*}"
  MOUNTED="${DEVICE}"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" != *"was mounted, so the system may have written to it"* ]]
}

@test "kakikomi unmounts each volume when the whole disk will not unmount on macOS" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux unmounts each partition already"
  disk_test_fat_image "${WORK}/fat.img" 8 KAKIKOMISLICE
  local listing
  listing="$(hdiutil attach "${WORK}/fat.img")"
  DEVICE="${listing%%[[:space:]]*}"
  MOUNTED="${DEVICE}"
  fake_install
  fake_flag unmount-fails

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Disk unmounted"* ]]
}

@test "kakikomi unmounts a mounted partition before it writes on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS unmounts the whole disk through diskutil"
  disk_test_fat_image "${WORK}/fat.img" 8 KAKIKOMIPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  mkdir -p "${WORK}/mnt"
  wait_for_node "${DEVICE}p1"
  sudo mount "${DEVICE}p1" "${WORK}/mnt"
  MOUNTED="${WORK}/mnt"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Disk unmounted"* ]]
}

@test "kakikomi unmounts a filesystem on the whole disk before it writes on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS unmounts the whole disk through diskutil"
  disk_test_image "${WORK}/whole.img" 8
  mkfs.fat -F 16 -s 1 -n KAKIKOMIALL "${WORK}/whole.img" >/dev/null
  DEVICE="$(disk_test_attach "${WORK}/whole.img")"
  mkdir -p "${WORK}/mnt"
  sudo mount "${DEVICE}" "${WORK}/mnt"
  MOUNTED="${WORK}/mnt"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Disk unmounted"* ]]
}

@test "kakikomi lists only removable disks in the picker" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS reads the internal flag from diskutil"
  unset ALLOW_INTERNAL
  disk_test_fill "${WORK}/target.img" 2 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  local name="${DEVICE##*/}"
  disk_test_shim lsblk "case \"\$*\" in *RM,HOTPLUG,TRAN*${name}*) printf '1 0 usb\\n'; exit 0 ;; *RM,HOTPLUG,TRAN*) printf '0 0 sata\\n'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""
  local image
  image="$(payload)"

  # Act
  run picking "${name}" "${image}"

  # Assert
  [[ "${output}" == *"${DEVICE}"* ]]
}

@test "kakikomi says when no removable disk is attached" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "an attached disk image is always removable on macOS"
  unset ALLOW_INTERNAL
  local image
  image="$(payload)"

  # Act
  run disk_test_run kakikomi "${image}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: No external or removable disk is attached."* ]]
}
