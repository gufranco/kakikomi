#!/bin/sh
[ -n "${ZSH_VERSION:-}" ] && emulate sh

DISK_LIB="$(cd "$(dirname "$0")/../lib" && pwd)" || exit 1

# shellcheck source=SCRIPTDIR/../lib/core.sh
. "${DISK_LIB}/core.sh"
# shellcheck source=SCRIPTDIR/../lib/io.sh
. "${DISK_LIB}/io.sh"
# shellcheck source=SCRIPTDIR/../lib/calibrate.sh
. "${DISK_LIB}/calibrate.sh"
# shellcheck source=SCRIPTDIR/../lib/wipe.sh
. "${DISK_LIB}/wipe.sh"
# shellcheck source=SCRIPTDIR/../lib/source.sh
. "${DISK_LIB}/source.sh"
# shellcheck source=SCRIPTDIR/../lib/guard.sh
. "${DISK_LIB}/guard.sh"
# shellcheck source=SCRIPTDIR/../lib/ui.sh
. "${DISK_LIB}/ui.sh"
# shellcheck source=SCRIPTDIR/../lib/write.sh
. "${DISK_LIB}/write.sh"
# shellcheck source=SCRIPTDIR/../lib/after.sh
. "${DISK_LIB}/after.sh"
# shellcheck source=SCRIPTDIR/../lib/boot.sh
. "${DISK_LIB}/boot.sh"
# shellcheck source=SCRIPTDIR/../lib/cli.sh
. "${DISK_LIB}/cli.sh"

call_breach() {
  disk_make_tmpdir breach || return 1
  disk_breach_start "$1"
  sleep 1
  "$2" "$1"
  sleep 2
  disk_breach_stop "$1"
}

call_changed_source() {
  disk_source_open "$1" || return 1
  DISK_SRC_SHA="0000"
  DELETE=y
  VERIFY=y
  disk_delete_source
}

call_first_boot_disk() {
  disk_cb_list="$(disk_boot_disks)"
  printf '%s\n' "${disk_cb_list}" | sed -n '1p'
}

call_watch() {
  disk_watch "$@" && return 0
  printf '%s\n' "${DISK_REASON}"
  return 1
}

call_partition_starts() {
  disk_make_tmpdir starts || return 1
  disk_partition_starts "$1" "$1"
  printf 'unsupported=%s\n' "${DISK_GUARD_UNSUPPORTED}"
}

call_fstab_append() {
  disk_make_tmpdir fstab || return 1
  disk_fstab_append "$1" "$2" || return 1
  disk_cf_path="$(disk_fstab_path)"
  cat "${disk_cf_path}"
}

"$@"
