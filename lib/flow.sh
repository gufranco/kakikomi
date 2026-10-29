#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_write_cleanup() {
  [ -n "${DISK_SRC_PID}" ] && disk_stream_stop
  [ -n "${DISK_SRC_WORK}" ] && rm -rf "${DISK_SRC_WORK}"
  DISK_SRC_WORK=""
  return 0
}

disk_write_interrupted() {
  [ -n "${DISK_STOP_FILE}" ] && : >"${DISK_STOP_FILE}"
  return 0
}

disk_write_targets() {
  disk_wts_list=""
  if [ "$#" -eq 0 ]; then
    disk_wts_list="$(disk_pick_targets)" || return 1
  else
    for disk_wts_arg in "$@"; do
      disk_wts_disk="$(disk_resolve "${disk_wts_arg}")" || return 1
      disk_wts_list="${disk_wts_list}${disk_wts_disk}
"
    done
  fi
  disk_wts_unique="$(printf '%s' "${disk_wts_list}" | awk 'NF && !seen[$0]++')"
  printf '%s\n' "${disk_wts_unique}"
}

disk_write_fits() {
  disk_wf_size="$(disk_size_bytes "$1")"
  if ! disk_is_uint "${disk_wf_size}" || [ "${disk_wf_size}" -eq 0 ]; then
    disk_error "unable to determine the size of $1."
    return 1
  fi
  disk_wf_sector="$(disk_sector_bytes "$1")"
  disk_wf_size=$((disk_wf_size - disk_wf_size % disk_wf_sector))
  disk_wf_need="$(disk_padded_size "${DISK_SRC_SIZE}" "${disk_wf_sector}")"
  if [ "${disk_wf_need}" -gt "${disk_wf_size}" ]; then
    disk_error "stopped: the image needs ${disk_wf_need} bytes and $1 holds ${disk_wf_size}."
    return 1
  fi
  if [ "${disk_wf_need}" -lt "${disk_wf_size}" ] && [ "${KAKIKOMI_ZERO_TAIL:-}" != "y" ] && [ "${DISK_QUIET_TAIL}" != "1" ]; then
    disk_wf_extra="$(disk_human $((disk_wf_size - disk_wf_need)))"
    disk_warning "$1 is ${disk_wf_extra} larger than the image. that space keeps its old contents; --zero-tail blanks it."
  fi
  disk_geometry_warning "${DISK_SRC_SIZE}" "${disk_wf_size}"
  return 0
}

disk_geometry_warning() {
  case "$1:$2" in
  368640:737280 | 368640:1474560 | 737280:1474560 | 1228800:1474560 | 1474560:2949120 | 737280:2949120)
    disk_gw_image="$(disk_human "$1")"
    disk_gw_media="$(disk_human "$2")"
    disk_warning "a ${disk_gw_image} floppy image on ${disk_gw_media} media will not read in a drive built for the smaller format."
    ;;
  *) ;;
  esac
  return 0
}

disk_write_bootable_hint() {
  [ "${DISK_SRC_STREAM}" = "1" ] && return 0
  [ "${DISK_SRC_KIND}" = "raw" ] || return 0
  disk_mbr_valid "${DISK_SRC_PATH}" && return 0
  disk_wb_iso="$(disk_magic_hex "${DISK_SRC_PATH}" 32769 5)"
  [ "${disk_wb_iso}" = "4344303031" ] && return 0
  disk_warning "the image has no partition table or boot record, so the disk may not boot or show any files."
  return 0
}

disk_write_find_published() {
  disk_wq_all="$(disk_published_digests "${DISK_SRC_ORIGIN}")"
  if [ -z "${disk_wq_all}" ] && [ -n "${DISK_SRC_URL}" ]; then
    mkdir -p "${DISK_SRC_WORK}/published" || return 1
    disk_wq_all="$(disk_published_remote "${DISK_SRC_URL}" "${DISK_SRC_WORK}/published")"
  fi
  printf '%s\n' "${disk_wq_all}"
}

disk_write_published() {
  DISK_PUBLISHED_OK=0
  DISK_PUBLISHED_ALG=""
  DISK_PUBLISHED_READ=""
  disk_wp_all="$(disk_write_find_published)" || return 1
  [ -n "${disk_wp_all}" ] || return 0
  disk_published_choose "${disk_wp_all}" || return 1
  [ -n "${DISK_PUBLISHED_ALG}" ] || return 0
  [ -f "${DISK_SRC_ORIGIN}" ] || return 0
  disk_wp_where="$(disk_published_sources "${DISK_PUBLISHED_SET}" | sed -n '1p')"
  disk_wp_phrase="$(disk_published_phrase "${DISK_PUBLISHED_ALG}" "${disk_wp_where}")"
  disk_info "Checking the image against ${disk_wp_phrase}."
  disk_published_check file && disk_published_matched
  return 0
}

disk_write_contents_differ() {
  [ "${DISK_SRC_STREAM}" = "1" ] || [ "${DISK_SRC_PATH}" != "${DISK_SRC_ORIGIN}" ] || [ ! -f "${DISK_SRC_ORIGIN}" ]
}

disk_write_checksum() {
  disk_info "Computing the image's SHA-256."
  DISK_SRC_SHA="$(disk_source_digest sha256)"
  [ -n "${DISK_PUBLISHED_ALG}" ] || return 0
  [ "${DISK_PUBLISHED_OK}" = "1" ] && return 0
  if disk_write_contents_differ && disk_published_check contents; then
    disk_published_matched
    return 0
  fi
  disk_published_mismatch
}

disk_write_summary() {
  printf '\n'
  disk_info "Image:  ${DISK_SRC_ORIGIN}"
  disk_ws_human="$(disk_human "${DISK_SRC_SIZE}")"
  disk_info "        ${DISK_SRC_NOTE:-${DISK_SRC_KIND}}, ${disk_ws_human} (${DISK_SRC_SIZE} bytes)"
  [ -n "${DISK_SRC_SHA}" ] && disk_info "        SHA-256 ${DISK_SRC_SHA}"
  for disk_ws_target in $1; do
    disk_ws_size="$(disk_size_bytes "${disk_ws_target}")"
    disk_ws_id="$(disk_identity "${disk_ws_target}")"
    disk_ws_human="$(disk_human "${disk_ws_size}")"
    disk_info "Target: ${disk_ws_target}, ${disk_ws_human}, ${disk_ws_id:-unnamed device}"
    disk_ws_parts="$(disk_partitions_text "${disk_ws_target}")"
    if [ -n "${disk_ws_parts}" ]; then
      disk_info "        Everything on it is replaced, including:"
      disk_say 10 "${disk_ws_parts}"
    fi
  done
  printf '\n'
}

disk_write_check_targets() {
  disk_ct_clone=""
  [ "${DISK_SRC_KIND}" = "device" ] && disk_ct_clone="${DISK_SRC_PATH}"
  disk_ct_image=""
  [ "${DISK_SRC_KIND}" != "device" ] && disk_ct_image="${DISK_SRC_ORIGIN}"
  for disk_ct_target in $1; do
    if [ ! -b "${disk_ct_target}" ] && [ ! -c "${disk_ct_target}" ]; then
      disk_error "device not found or invalid: ${disk_ct_target}"
      return 1
    fi
    disk_refuse_target "${disk_ct_target}" "${disk_ct_image}" "${disk_ct_clone}" || return 1
    disk_write_fits "${disk_ct_target}" || return 1
  done
  return 0
}

disk_write_run() {
  DISK_STOP_FILE="${DISK_SRC_WORK}/stop"
  disk_wr_count="$(printf '%s\n' "$1" | sed '/^$/d' | wc -l)"
  disk_wr_count="$(printf '%s' "${disk_wr_count}" | tr -d '[:space:]')"
  if [ "${disk_wr_count}" -eq 1 ]; then
    disk_wr_id="$(disk_identity "$1")"
    disk_write_target "$1" "${disk_wr_id}"
    return "$?"
  fi
  if [ "${KAKIKOMI_REINSERT:-}" = "y" ]; then
    disk_warning "--reinsert checks one disk at a time, so it is skipped when writing several."
    KAKIKOMI_REINSERT=n
  fi
  disk_wr_pids=""
  for disk_wr_target in $1; do
    (
      DISK_LOG_TAG="${disk_wr_target##*/}"
      disk_wr_id="$(disk_identity "${disk_wr_target}")"
      disk_write_target "${disk_wr_target}" "${disk_wr_id}"
    ) &
    disk_wr_pids="${disk_wr_pids} ${disk_wr_target}=$!"
  done
  disk_wr_failed=0
  for disk_wr_pair in ${disk_wr_pids}; do
    if wait "${disk_wr_pair#*=}"; then
      disk_success "${disk_wr_pair%%=*}: written and verified."
    else
      disk_error "${disk_wr_pair%%=*}: failed, see its stopped lines above."
      disk_wr_failed=$((disk_wr_failed + 1))
    fi
  done
  [ "${disk_wr_failed}" -eq 0 ]
}

disk_write_once() {
  disk_wo_targets="$(disk_write_targets "$@")" || return 1
  [ -n "${disk_wo_targets}" ] || {
    disk_error "no target chosen."
    return 1
  }
  disk_write_check_targets "${disk_wo_targets}" || return 1
  disk_write_bootable_hint
  disk_write_summary "${disk_wo_targets}"
  disk_ask_options
  disk_confirm_names "${disk_wo_targets}" write || return 1
  disk_require_sudo || return 1
  disk_write_run "${disk_wo_targets}"
}
