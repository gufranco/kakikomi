#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-golden.XXXXXX")"
  WORK="$(cd "${WORK}" && pwd -P)"
  disk_test_setup_env
  export KAKIKOMI_CHUNK_TARGET_MS=600000
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

@test "a write prints the same transcript as the recorded one" {
  # Arrange
  local answer="${NAME}"

  # Act
  run disk_test_run kakikomi "${IMAGE}" "${DEVICE}" <<<"${answer}"

  # Assert
  [[ "${status}" -eq 0 ]]
  disk_test_matches_golden write "${output}"
}
