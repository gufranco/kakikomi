#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-after.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  IMAGE="${WORK}/fat.img"
  disk_test_fat_image "${IMAGE}" 8 AFTER
  disk_test_fill "${WORK}/t1.img" 16 '\252'
  disk_test_fill "${WORK}/t2.img" 16 '\252'
  DEV1="$(disk_test_attach "${WORK}/t1.img")"
  DEV2="$(disk_test_attach "${WORK}/t2.img")"
  ATTACHED="${DEV1} ${DEV2}"
}

teardown() {
  local device
  for device in ${ATTACHED}; do
    disk_test_detach "${device}"
  done
  rm -rf "${WORK}"
}

answer_and_write() {
  local answers="$1"
  local settings="$2"
  shift 2
  printf '%b' "${answers}" | disk_test_run_env "${settings}" kakikomi "$@"
}

write_on_path() {
  local search_path="$1"
  local answers="$2"
  shift 2
  printf '%b' "${answers}" | disk_test_run_path "${search_path}" kakikomi "$@"
}

@test "kakikomi AGAIN=y writes the same image to the next disk" {
  # Arrange
  local answers="${DEV1##*/}\n\n${DEV2##*/}\n${DEV2##*/}\nq\n"

  # Act
  run answer_and_write "${answers}" "AGAIN=y" "${IMAGE}" "${DEV1}"

  # Assert
  [[ "${status}" -eq 0 ]]
  disk_test_same_prefix "${IMAGE}" "${WORK}/t1.img"
  disk_test_same_prefix "${IMAGE}" "${WORK}/t2.img"
}

@test "kakikomi REINSERT=y compares the disk again after it comes back" {
  # Arrange
  local log="${WORK}/run.log"
  printf '%s\n' "${DEV1##*/}" | disk_test_run_env "REINSERT=y" kakikomi "${IMAGE}" "${DEV1}" >"${log}" 2>&1 &
  local runner="$!"
  disk_test_wait_for "${log}" "plug it back in" 1200 || cat "${log}"

  # Act
  local returned
  returned="$(disk_test_attach "${WORK}/t1.img")"
  ATTACHED="${ATTACHED} ${returned}"
  local status_code=0
  wait "${runner}" || status_code="$?"

  # Assert
  [[ "${status_code}" -eq 0 ]] || cat "${log}"
  grep -q "still matches the image byte for byte" "${log}"
}

@test "kakikomi asks what to do after the write when run in a terminal" {
  # Arrange
  local answers="y\ny\nn\n${DEV1##*/}\n"

  # Act
  run answer_and_write "${answers}" "DISK_INTERACTIVE=1" "${IMAGE}" "${DEV1}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Move the image to the Trash once every disk validated?"* ]]
  [[ -f "${WORK}/Trash/fat.img" ]]
}

@test "kakikomi moves the image with the trash command on the PATH" {
  # Arrange
  disk_test_shim trash "mkdir -p '${WORK}/Bin' && mv -f \"\$1\" '${WORK}/Bin/'"

  # Act
  run answer_and_write "${DEV1##*/}\n" "DELETE=y DISK_TRASH=" "${IMAGE}" "${DEV1}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Moved ${IMAGE} to the Trash."* ]]
  [[ -f "${WORK}/Bin/fat.img" ]]
}

@test "kakikomi moves the image with gio when there is no trash command" {
  # Arrange
  disk_test_shim gio "[ \"\$1\" = trash ] || exit 1
mkdir -p '${WORK}/Gio' && mv -f \"\$2\" '${WORK}/Gio/'"
  local farm
  farm="$(disk_test_farm trash)"
  export DELETE=y DISK_TRASH=""

  # Act
  run write_on_path "${farm}" "${DEV1##*/}\n" "${IMAGE}" "${DEV1}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -f "${WORK}/Gio/fat.img" ]]
}

@test "kakikomi checks only one disk again when it writes several" {
  # Arrange
  local answers="${DEV1##*/} ${DEV2##*/}\n"

  # Act
  run answer_and_write "${answers}" "REINSERT=y" "${IMAGE}" "${DEV1}" "${DEV2}"

  # Assert
  [[ "${output}" == *"REINSERT=y checks one disk at a time, so it is skipped when writing several."* ]]
}
