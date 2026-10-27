#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_wipe_attempt() {
  disk_wa_started="$(disk_now_ms)"
  disk_wa_moved=1
  if [ "$1" = "write" ]; then
    disk_move write "$2" "$3" "$4" "$5" || disk_wa_moved=0
  else
    disk_move read "$3" "${DISK_TMPDIR}/readback" "$4" "$5" || disk_wa_moved=0
  fi
  if [ "${disk_wa_moved}" -eq 0 ]; then
    [ "${DISK_INTERRUPTED:-0}" -eq 1 ] && return 4
    [ "${DISK_TIMED_OUT:-0}" -eq 1 ] && return 3
    disk_wa_detail="$(disk_get_error)"
    disk_wa_class="$(disk_error_class "${disk_wa_detail}")"
    [ "${disk_wa_class}" = "bus" ] && return 2
    if [ "${disk_wa_class}" = "media" ] && disk_head_crash_family; then
      return 5
    fi
    return 1
  fi
  if [ -n "${DISK_STOP_FILE:-}" ] && [ -f "${DISK_STOP_FILE}" ]; then
    DISK_INTERRUPTED=1
    return 4
  fi
  disk_wa_now="$(disk_now_ms)"
  disk_is_uint "${disk_wa_started}" || disk_wa_started="${disk_wa_now}"
  disk_is_uint "${disk_wa_now}" || disk_wa_now="${disk_wa_started}"
  DISK_ELAPSED=$((disk_wa_now - disk_wa_started))
  if [ "${DISK_MOVED}" -ne "$5" ]; then
    disk_set_error "chunk $6 moved ${DISK_MOVED} of $5 bytes"
    return 1
  fi
  [ "$1" = "read" ] || return 0
  disk_wa_reference="$(disk_exact_reference "$2" "$5")" || return 1
  if ! cmp -s "${DISK_TMPDIR}/readback" "${disk_wa_reference}"; then
    disk_set_error "chunk $6 did not read back as $7"
    DISK_BITS="$(disk_bit_report "${disk_wa_reference}" "${DISK_TMPDIR}/readback" "$5")"
    return 1
  fi
  return 0
}

disk_exact_reference() {
  disk_er_size="$(disk_file_size "$1")"
  if [ "${disk_er_size}" -eq "$2" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  head -c "$2" "$1" >"${DISK_TMPDIR}/reference" || return 1
  printf '%s\n' "${DISK_TMPDIR}/reference"
}

disk_chunk_failed() {
  disk_cf_disk="$1"
  disk_cf_where="$2 chunk $3 of $4"
  disk_log_lines disk_error "${DISK_BITS}"
  case "${DISK_OUTCOME}" in
    4)
      disk_error "stopped: interrupted during ${disk_cf_where}."
      disk_error "nothing else will be written. ejecting so the head leaves the surface."
      disk_eject_now "${disk_cf_disk}"
      ;;
    3)
      disk_cf_shown="$(disk_duration "${DISK_DEADLINE}")"
      disk_fault "${disk_cf_disk}" "${disk_cf_where} went silent for ${disk_cf_shown} at offset $5." stall
      ;;
    2)
      disk_fault "${disk_cf_disk}" "${disk_cf_where} stopped answering at offset $5."
      ;;
    *)
      if [ "${DISK_OUTCOME}" -eq 5 ] || disk_head_crash_family; then
        disk_fault "${disk_cf_disk}" "${disk_cf_where} did not come back clean at offset $5." fatal
      else
        disk_fault "${disk_cf_disk}" "${disk_cf_where} failed ${DISK_ATTEMPTS:-1} times at offset $5."
      fi
      ;;
  esac
  return 1
}

