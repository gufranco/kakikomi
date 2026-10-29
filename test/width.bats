#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d /tmp/disk-width.XXXXXX)"
}

teardown() {
  rm -rf "${WORK}"
}

widest_line() {
  awk '{ if (length($0) > widest) { widest = length($0) } } END { print widest + 0 }'
}

@test "help never prints a line wider than 80 columns" {
  # Arrange
  local page widest

  # Act
  page="$(KAKIKOMI_TERMINAL=1 disk_test_run kakikomi help)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "version never prints a line wider than 80 columns" {
  # Arrange
  local page widest

  # Act
  page="$(KAKIKOMI_TERMINAL=1 disk_test_run kakikomi version)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "an error longer than 80 columns wraps between words" {
  # Arrange
  local message="the drive answered the write but read back a different byte on every pass of this chunk"

  # Act
  KAKIKOMI_TERMINAL=1 run disk_test_call disk_error "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${#lines[@]}" -eq 2 ]]
  [[ "${lines[0]}" == "kakikomi: the drive answered the write but read back a different byte on every" ]]
  [[ "${lines[1]}" == "pass of this chunk" ]]
}

@test "an error sent to a pipe stays on one line, however long" {
  # Arrange
  local message="the drive answered the write but read back a different byte on every pass of this chunk"

  # Act
  run disk_test_call disk_error "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "kakikomi: ${message}" ]]
}

@test "a word wider than 80 columns stays whole on its own line" {
  # Arrange
  local volume="/Volumes/The-Family-Archive-Of-Every-Scanned-Letter-And-Photograph-1968-To-1985"

  # Act
  KAKIKOMI_TERMINAL=1 run disk_test_call disk_info "Device: ${volume}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "Device:" ]]
  [[ "${lines[1]}" == "        ${volume}" ]]
}

@test "a doctor row stays on one line on a terminal, however long" {
  # Arrange
  local expected="sha256sum|shasum   ok       /opt/homebrew/opt/uutils-coreutils/libexec/uubin/sha256sum, uutils 0.12.0"

  # Act
  KAKIKOMI_TERMINAL=1 run disk_test_call disk_doctor_row "sha256sum|shasum" ok "/opt/homebrew/opt/uutils-coreutils/libexec/uubin/sha256sum, uutils 0.12.0"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "internal DISK_ variables from the environment change nothing" {
  # Arrange
  local expected="kakikomi: unknown option '--nope'. run 'kakikomi help' for usage."

  # Act
  DISK_WIDTH=20 KAKIKOMI_TERMINAL=1 run disk_test_run kakikomi --nope

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}
