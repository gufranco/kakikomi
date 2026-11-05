#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-ui.XXXXXX")"
  disk_test_setup_env
  DEVICE=""
  unset KODOUGU_THEME KODOUGU_ACCENT KAKIKOMI_THEME NO_COLOR
  export KAKIKOMI_TEST_GUM=1
  export KAKIKOMI_TEST_GUM_LOG="${WORK}/gum.log"
  export KAKIKOMI_TEST_GUM_ANSWERS="${WORK}/answers"
  export KAKIKOMI_INTERACTIVE=1
  : >"${KAKIKOMI_TEST_GUM_LOG}"
}

teardown() {
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

attach() {
  disk_test_fill "${WORK}/target.img" "$1" '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="$(disk_test_name "${DEVICE}")"
  PAYLOAD="${WORK}/payload.img"
  disk_test_random_file "${PAYLOAD}" 1
}

answers() {
  printf '%s\n' "$@" >"${KAKIKOMI_TEST_GUM_ANSWERS}"
}

called() {
  grep -q -F -- "$1" "${KAKIKOMI_TEST_GUM_LOG}"
}

untouched() {
  local bytes
  bytes="$(disk_test_range_bytes "${WORK}/target.img" 0 1048576)"
  [[ "${bytes}" == "aa" ]]
}

@test "an image is written after the gum options and the name typed in a danger box" {
  # Arrange
  local bar
  bar="$(printf '\342\224\201')"
  attach 2
  answers "yes" "no" "no" "${NAME}"

  # Act
  run disk_test_run kakikomi "${PAYLOAD}" "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  disk_test_same_prefix "${PAYLOAD}" "${WORK}/target.img"
  [[ "${output}" == *"Image:"*"payload.img"* ]]
  [[ "${output}" == *"${bar}"* ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
  called "confirm Read everything back and compare it with the image when done? --affirmative Yes"
  called "confirm Move the image to the Trash once every disk validated? --affirmative Yes"
  called "--default=false"
  called "--border thick"
  called "input --header Type ${NAME} to write"
}

@test "an empty label answer formats the disk as UNTITLED" {
  # Arrange
  attach 4
  answers "2" "${DEVICE}" "fat" "" "yes" "no" "${NAME}"

  # Act
  run disk_test_run kakikomi </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"a new fat filesystem named UNTITLED"* ]]
}

@test "a cancelled option prompt keeps its default" {
  # Arrange
  attach 2
  answers "<cancel>" "<cancel>" "<cancel>" "${NAME}"

  # Act
  run disk_test_run kakikomi "${PAYLOAD}" "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
  [[ -f "${PAYLOAD}" ]]
}

@test "a cancelled typed name writes nothing" {
  # Arrange
  attach 2
  answers "yes" "no" "no" "<cancel>"

  # Act
  run disk_test_run kakikomi "${PAYLOAD}" "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"WARN kakikomi: cancelled, nothing was touched."* ]]
  untouched
}

@test "the menu writes an image to a disk picked from a gum list" {
  # Arrange
  attach 2
  answers "1" "${PAYLOAD}" "${DEVICE}" "yes" "no" "no" "${NAME}"

  # Act
  run disk_test_run kakikomi </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"write disk images to removable media, verified, never mounted"* ]]
  [[ "${output}" == *"Validated: ${DEVICE} matches the image"* ]]
  called "choose --header What would you like to do?"
  called "input --header Image file, URL or source disk"
  called "choose --header Write to which disk(s)?"
  called "--no-limit"
}

@test "the menu formats a disk with the filesystem picked from a gum list" {
  # Arrange
  attach 4
  answers "2" "${DEVICE}" "fat" "menu" "yes" "no" "${NAME}"

  # Act
  run disk_test_run kakikomi </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"a new fat filesystem named MENU"* ]]
  called "choose --header Format which disk?"
  called "choose --header Filesystem"
  called "--placeholder UNTITLED"
}

@test "the menu runs doctor" {
  # Arrange
  answers "3"

  # Act
  run disk_test_run kakikomi </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Tool"*"State"*"Detail"* ]]
}

@test "the next disk prompt finishes the run when asked" {
  # Arrange
  attach 2
  answers "yes" "no" "no" "${NAME}" "no"
  export KAKIKOMI_AGAIN=y

  # Act
  run disk_test_run kakikomi "${PAYLOAD}" "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "confirm Insert the next disk, then write it? --affirmative Write --negative Finish"
}

@test "doctor reports a missing tool below the table" {
  # Arrange
  local farm
  farm="$(disk_test_farm dd)"

  # Act
  run disk_test_run_path "${farm}" kakikomi doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"ERROR kakikomi: a required tool is missing."* ]]
}

@test "doctor fails without gum" {
  # Arrange
  local farm
  farm="$(disk_test_farm gum)"

  # Act
  KAKIKOMI_TEST_GUM=0 run disk_test_run_path "${farm}" kakikomi doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"gum                missing  install with: brew install gum"* ]]
}

@test "version shows the version and platform as badges" {
  # Arrange
  local version
  version="$(sed -n 's/^KAKIKOMI_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run kakikomi version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "kakikomi ${version} platform "* ]]
}

@test "help is formatted with gum" {
  # Arrange
  local expected="## Usage"

  # Act
  run disk_test_run kakikomi help </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${expected}"* ]]
  called "format --theme pink"
}

@test "format help is formatted with gum" {
  # Arrange
  local expected="# kakikomi format"

  # Act
  run disk_test_run kakikomi format help </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${expected}"* ]]
  called "format --theme pink"
}

@test "--theme picks the palette over the environment" {
  # Arrange
  local theme="nord"

  # Act
  KODOUGU_THEME=dracula KAKIKOMI_THEME=gruvbox run disk_test_run kakikomi --theme "${theme}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #88C0D0"
}

@test "--theme= with a value picks the palette" {
  # Arrange
  local option="--theme=tokyo-night"

  # Act
  run disk_test_run kakikomi "${option}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #7AA2F7"
}

@test "an unknown theme stops before the disk is touched" {
  # Arrange
  attach 2

  # Act
  KODOUGU_THEME=solarized run disk_test_run kakikomi "${PAYLOAD}" "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"got: solarized"* ]]
  untouched
}

@test "--theme without a value stops with the usage hint" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run kakikomi version "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"option '--theme' needs a value. run 'kakikomi help' for usage."* ]]
}

@test "--theme after -- names the image" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run kakikomi -- "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"--theme"* ]]
}

@test "a message after a progress bar still running starts on its own line" {
  # Arrange
  local call='disk_progress Writing 512 1024 0; disk_info "Told macOS not to mount the volume."'

  # Act
  run disk_test_call eval "disk_ui_setup && ${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"%"*$'\n'"Told macOS not to mount the volume."* ]]
}
