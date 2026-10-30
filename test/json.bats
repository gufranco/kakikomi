#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

bats_require_minimum_version 1.5.0

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-json.XXXXXX")"
  WORK="$(cd "${WORK}" && pwd -P)"
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

image_facts() {
  local bytes sum
  bytes="$(wc -c <"${IMAGE}")"
  sum="$(openssl dgst -sha256 -r <"${IMAGE}")"
  printf '%s %s\n' "$((bytes))" "${sum%% *}"
}

@test "--json prints the image and each target's result as one JSON object" {
  # Arrange
  local facts bytes sha
  facts="$(image_facts)"
  read -r bytes sha <<<"${facts}"

  # Act
  run --separate-stderr disk_test_run kakikomi --json "${IMAGE}" "${DEVICE}" <<<"${NAME}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"image\":\"${IMAGE}\",\"bytes\":${bytes},\"sha256\":\"${sha}\",\"targets\":[{\"device\":\"${DEVICE}\",\"written\":true,\"verified\":true}]}" ]]
}

@test "--json with --no-verify reports a target written but not verified" {
  # Arrange
  local facts bytes sha
  facts="$(image_facts)"
  read -r bytes sha <<<"${facts}"

  # Act
  run --separate-stderr disk_test_run kakikomi --json --no-verify "${IMAGE}" "${DEVICE}" <<<"${NAME}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"image\":\"${IMAGE}\",\"bytes\":${bytes},\"sha256\":\"${sha}\",\"targets\":[{\"device\":\"${DEVICE}\",\"written\":true,\"verified\":false}]}" ]]
}
