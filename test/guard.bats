#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kakikomi-guard.XXXXXX")"
  disk_test_setup_env
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
}

teardown() {
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

craft() {
  local file="$1"
  local size="$2"
  local writes="$3"
  python3 -c '
import struct, sys
path, size, writes = sys.argv[1], int(sys.argv[2]), sys.argv[3]
data = bytearray(size)
for item in writes.split():
    offset, hexbytes = item.split("=")
    raw = bytes.fromhex(hexbytes)
    data[int(offset):int(offset) + len(raw)] = raw
open(path, "wb").write(bytes(data))
' "${file}" "${size}" "${writes}"
}

signature="510=55aa"

writing() {
  printf '%s\n' "${NAME}" | disk_test_run_env "${1:-}" kakikomi "${IMAGE}" "${DEVICE}"
}

@test "kakikomi refuses an image holding an HFS+ partition" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "the fstab guard exists only on macOS"
  craft "${WORK}/hfs.img" 2097152 "450=af 454=00080000 ${signature}"
  IMAGE="${WORK}/hfs.img"
  disk_test_fill "${WORK}/target.img" 4 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="$(disk_test_name "${DEVICE}")"

  # Act
  run writing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: this image holds an HFS+ partition, whose volume identity cannot be read from its header alone."* ]]
}
