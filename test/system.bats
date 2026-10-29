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

on_terminal() {
  case "${DISK_TEST_OS}" in
  Darwin) script -q /dev/null "$@" </dev/null ;;
  *) script -qec "$(printf '%q ' "$@")" /dev/null </dev/null ;;
  esac
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

@test "a bounded command without timeout is checked within milliseconds, not once a second" {
  # Arrange
  local farm first second
  farm="$(disk_test_farm timeout gtimeout)"
  disk_test_shim sleep "printf '%s\\n' \"\$1\" >>'${WORK}/sleeps'
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call_path "${SHIMS}:${farm}" disk_bounded 3 perl -e 'select(undef, undef, undef, 1)'

  # Assert
  [[ "${status}" -eq 0 ]]
  { read -r first; read -r second; } <"${WORK}/sleeps"
  [[ "${first}" == "0.010" ]]
  [[ "${second}" == "0.020" ]]
}

@test "a bounded command uses gtimeout when timeout is missing" {
  # Arrange
  disk_test_shim gtimeout "while [ \"\$#\" -gt 0 ]; do
  case \"\$1\" in
    -k) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
exec \"\$@\""
  local farm
  farm="$(disk_test_farm timeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 3 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a millisecond bound uses gtimeout when timeout is missing" {
  # Arrange
  disk_test_shim gtimeout "while [ \"\$#\" -gt 0 ]; do
  case \"\$1\" in
    -k) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
exec \"\$@\""
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

@test "the disk picker leaves out an internal disk" {
  # Arrange
  export DISK_OS=Linux
  unset ALLOW_INTERNAL
  disk_test_shim findmnt "exit 1"
  disk_test_shim lsblk "case \"\$*\" in
  *NAME,TYPE,SIZE*) printf 'sdy disk 1000\\nsdz disk 1000\\n' ;;
  */dev/sdy*) printf '0 0 sata\\n' ;;
  *) printf '1 1 usb\\n' ;;
esac"

  # Act
  run disk_test_call disk_eligible

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "/dev/sdz" ]]
}

@test "a working directory that cannot be made stops with a message" {
  # Arrange
  export TMPDIR="${BATS_TMPDIR:-/tmp}/kakikomi-missing-${RANDOM}/deeper"

  # Act
  run disk_test_call disk_make_tmpdir kakikomi

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: unable to create a working directory."* ]]
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
  [[ "${output}" == *"kakikomi: not a device or mount point: ${file}"* ]]
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
  [[ "${output}" == *"kakikomi: no device found for mount point: ${folder}"* ]]
}

@test "kakikomi resolves a mount point to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KKMOUNT
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
    disk_test_wait_partition "${DEVICE}p1"
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

@test "kakikomi reads a mount point given as the source as its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KKSOURCE
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
    disk_test_wait_partition "${DEVICE}p1"
    sudo mount "${DEVICE}p1" "${mount_point}"
    MOUNTED="${mount_point}"
    ;;
  esac

  # Act
  run disk_test_run kakikomi "${mount_point}" "${WORK}/no-such-disk" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" != *"image not found"* ]]
  [[ "${output}" == *"kakikomi: not a device or mount point: ${WORK}/no-such-disk"* ]]
}

@test "kakikomi refuses a source folder that is not a mount point" {
  # Arrange
  local folder="${WORK}/source-folder"
  mkdir -p "${folder}"

  # Act
  run disk_test_run kakikomi "${folder}" "${WORK}/no-such-disk" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kakikomi: no device found for mount point: ${folder}" ]]
}

@test "kakikomi resolves a partition to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KKPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  local partition
  case "${DISK_TEST_OS}" in
  Darwin) partition="${DEVICE}s1" ;;
  *) partition="${DEVICE}p1" ;;
  esac
  disk_test_wait_partition "${partition}"

  # Act
  run declining "${partition}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Target: ${DEVICE}"* ]]
}

@test "kakikomi writes a disk the system had mounted without calling it a breach" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux mounts are covered by the partition and whole-disk tests"
  disk_test_fat_image "${WORK}/fat.img" 8 KKAUTO
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
  disk_test_fat_image "${WORK}/fat.img" 8 KKSLICE
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
  disk_test_fat_image "${WORK}/fat.img" 8 KKPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  mkdir -p "${WORK}/mnt"
  disk_test_wait_partition "${DEVICE}p1"
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
  mkfs.fat -F 16 -s 1 -n KKWHOLE "${WORK}/whole.img" >/dev/null
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
  [[ "${output}" == *"kakikomi: no external or removable disk is attached."* ]]
}

@test "a mounted partition of a disk named with letters counts as mounted" {
  # Arrange
  disk_test_shim mount "printf '/dev/sdz1 on /media/usb type vfat (rw)\\n'"

  # Act
  run disk_test_call disk_is_mounted /dev/sdz

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a mounted partition after a trailing digit counts as mounted" {
  # Arrange
  disk_test_shim mount "printf '/dev/loop7p1 on /mnt/usb type vfat (rw)\\n'"

  # Act
  run disk_test_call disk_is_mounted /dev/loop7

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a disk whose name extends the target's does not count as mounted" {
  # Arrange
  disk_test_shim mount "printf '/dev/disk41s1 on /Volumes/OTHER (msdos, local)\\n'"

  # Act
  run disk_test_call disk_is_mounted /dev/disk4

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "an unmeasured disk expects no time for a transfer" {
  # Arrange
  export DISK_RATE_WRITE=0

  # Act
  run disk_test_call disk_expected_ms write 4096

  # Assert
  [[ "${output}" == "0" ]]
}

@test "MATSHITA LS-120 is superdisk" {
  # Arrange
  local identity="MATSHITA LS-120"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "superdisk" ]]
}

@test "IOMEGA JAZ 2GB is jaz" {
  # Arrange
  local identity="IOMEGA JAZ 2GB"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "jaz" ]]
}

@test "IOMEGA POCKETZIP is pocketzip" {
  # Arrange
  local identity="IOMEGA POCKETZIP"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "pocketzip" ]]
}

@test "progress redraws one line on a terminal" {
  # Arrange
  local -a shell_words
  read -r -a shell_words <<<"${DISK_SHELL:-sh}"
  local search_path
  search_path="$(disk_test_path)"

  # Act
  run on_terminal env PATH="${search_path}" "${shell_words[@]}" "${DISK_TESTS_DIR}/call.sh" disk_progress Writing 1048576 1048576 0

  # Assert
  [[ "${output}" == *"Writing 100%"* ]]
}

@test "the last error is read from memory when no error file is kept" {
  # Arrange
  export DISK_LAST_ERROR="dd: error reading: Input/output error"

  # Act
  run disk_test_call disk_get_error

  # Assert
  [[ "${output}" == "dd: error reading: Input/output error" ]]
}

@test "a chunk is not judged once a stop is pending" {
  # Arrange
  : >"${WORK}/stop"
  export DISK_STOP_FILE="${WORK}/stop" STALL_SECONDS=1

  # Act
  run disk_test_call call_watch write write 3 9 1048576 5000

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "" ]]
}
