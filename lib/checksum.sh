#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_openssl_name() {
  case "$1" in
  blake2b) printf 'blake2b512\n' ;;
  *) printf '%s\n' "$1" ;;
  esac
}

disk_openssl_digests() {
  disk_od_name="$(disk_openssl_name "$1")"
  openssl dgst "-${disk_od_name}" </dev/null >/dev/null 2>&1
}

disk_digest_tools() {
  case "$1" in
  md5) printf 'md5sum md5 openssl\n' ;;
  sha1 | sha224 | sha256 | sha384 | sha512) printf '%ssum shasum openssl\n' "$1" ;;
  blake2b) printf 'b2sum openssl\n' ;;
  sha3-*) printf 'openssl\n' ;;
  crc32) printf 'gzip\n' ;;
  *) return 1 ;;
  esac
}

disk_digest_tool() {
  disk_dk_tools="$(disk_digest_tools "$1")" || return 1
  for disk_dk_tool in ${disk_dk_tools}; do
    disk_cmd_exists "${disk_dk_tool}" || continue
    if [ "${disk_dk_tool}" = openssl ] && ! disk_openssl_digests "$1"; then
      continue
    fi
    printf '%s\n' "${disk_dk_tool}"
    return 0
  done
  return 1
}

disk_crc32_stdin() {
  disk_cr_tail="$(gzip -1 -c | tail -c 8 | od -An -tx1 -N4)"
  printf '%s\n' "${disk_cr_tail}" | awk '{ print $4 $3 $2 $1 }'
}

disk_digest_stdin() {
  disk_dx_tool="$(disk_digest_tool "$1")" || return 1
  case "${disk_dx_tool}" in
  shasum) disk_dx_out="$(shasum -a "${1#sha}")" ;;
  md5) disk_dx_out="$(md5 -q)" ;;
  gzip) disk_dx_out="$(disk_crc32_stdin)" ;;
  openssl)
    disk_dx_name="$(disk_openssl_name "$1")"
    disk_dx_out="$(openssl dgst "-${disk_dx_name}" -r)"
    ;;
  *) disk_dx_out="$("${disk_dx_tool}")" ;;
  esac
  printf '%s\n' "${disk_dx_out%% *}" | tr '[:upper:]' '[:lower:]'
}

disk_digest_algorithms() {
  case "$1" in
  sha512-or-blake2b) printf 'sha512 blake2b\n' ;;
  *) printf '%s\n' "$1" ;;
  esac
}

disk_digest_computable() {
  disk_cx_list="$(disk_digest_algorithms "$1")"
  for disk_cx_one in ${disk_cx_list}; do
    disk_digest_tool "${disk_cx_one}" >/dev/null && return 0
  done
  return 1
}

disk_digest_label() {
  case "$1" in
  md5) printf 'MD5\n' ;;
  crc32) printf 'CRC32\n' ;;
  blake2b) printf 'BLAKE2b\n' ;;
  sha512-or-blake2b) printf 'SHA-512 or BLAKE2b\n' ;;
  sha3-*) printf 'SHA3-%s\n' "${1#sha3-}" ;;
  *) printf 'SHA-%s\n' "${1#sha}" ;;
  esac
}

disk_digest_install_hint() {
  case "$1" in
  md5) printf 'install coreutils for md5sum, or openssl\n' ;;
  blake2b | sha512-or-blake2b) printf 'install coreutils for b2sum, or OpenSSL 1.1 or later\n' ;;
  sha3-*) printf 'install OpenSSL 1.1.1 or later\n' ;;
  crc32) printf 'install gzip\n' ;;
  *) printf 'install coreutils, perl for shasum, or openssl\n' ;;
  esac
}

disk_unpacked_name() {
  case "$1" in
  *.[Gg][Zz] | *.[Xx][Zz] | *.[Bb][Zz]2 | *.[Zz][Ss][Tt] | *.[Zz][Ss][Tt][Dd] | *.[Zz][Ii][Pp]) printf '%s\n' "${1%.*}" ;;
  *) printf '%s\n' "$1" ;;
  esac
}

disk_digest_names() {
  disk_hn_inner="$(disk_unpacked_name "$1")"
  printf '%s\n' "$1"
  [ "${disk_hn_inner}" = "$1" ] || printf '%s\n' "${disk_hn_inner}"
  return 0
}

disk_checksum_named() {
  case "$1" in
  *[Ss][Uu][Mm]* | *[Hh][Aa][Ss][Hh]* | *[Dd][Ii][Gg][Ee][Ss][Tt]* | *[Ss][Hh][Aa]* | *[Mm][Dd]5* | *[Bb]2* | *[Bb][Ll][Aa][Kk][Ee]* | *[Cc][Rr][Cc]* | *.[Ss][Ff][Vv]) return 0 ;;
  *) return 1 ;;
  esac
}

disk_checksum_skipped() {
  case "$1" in
  *.[Ss][Ii][Gg] | *.[Ss][Ii][Gg][Nn] | *.[Aa][Ss][Cc] | *.[Gg][Pp][Gg] | *.[Tt][Oo][Rr][Rr][Ee][Nn][Tt] | *.[Pp][Aa][Rr][Tt] | *.[Cc][Rr][Dd][Oo][Ww][Nn][Ll][Oo][Aa][Dd]) return 0 ;;
  *.[Gg][Zz] | *.[Xx][Zz] | *.[Bb][Zz]2 | *.[Zz][Ss][Tt] | *.[Zz][Ii][Pp] | *.7[Zz] | *.[Ii][Ss][Oo] | *.[Ii][Mm][Gg] | *.[Ii][Mm][Aa] | *.[Dd][Mm][Gg]) return 0 ;;
  *) return 1 ;;
  esac
}

disk_checksum_prefixed() {
  case "$1" in
  "$2".* | "$2"-* | "$2"_*) return 0 ;;
  *) return 1 ;;
  esac
}

disk_checksum_role() {
  DISK_DIGEST_ROLE=""
  [ "$1" = "$2" ] && return 1
  disk_checksum_skipped "$1" && return 1
  if disk_checksum_prefixed "$1" "$2" || disk_checksum_prefixed "$1" "$3"; then
    DISK_DIGEST_ROLE=tied
    return 0
  fi
  disk_checksum_named "$1" || return 1
  DISK_DIGEST_ROLE=listed
  if disk_checksum_prefixed "$1" "${2%.*}" || disk_checksum_prefixed "$1" "${3%.*}"; then
    DISK_DIGEST_ROLE=tied
  fi
  return 0
}

disk_published_scan() {
  disk_pk_tied=0
  [ "$2" = tied ] && disk_pk_tied=1
  disk_pk_found="$(DISK_DIGEST_NAMES="$4" DISK_DIGEST_TIED="${disk_pk_tied}" DISK_DIGEST_FILE="${1##*/}" awk -f "${DISK_LIB}/digests.awk" "$1")"
  [ -n "${disk_pk_found}" ] || return 0
  printf '%s\n' "${disk_pk_found}" | while IFS= read -r disk_pk_line; do
    printf '%s %s\n' "${disk_pk_line}" "$3"
  done
}

disk_published_local() {
  disk_px_dir="${1%/*}"
  [ "${disk_px_dir}" = "$1" ] && disk_px_dir="."
  disk_px_image="${1##*/}"
  disk_px_inner="$(disk_unpacked_name "${disk_px_image}")"
  disk_px_names="$(disk_digest_names "${disk_px_image}")"
  for disk_px_file in "${disk_px_dir}"/*; do
    [ -f "${disk_px_file}" ] || continue
    disk_checksum_role "${disk_px_file##*/}" "${disk_px_image}" "${disk_px_inner}" || continue
    disk_px_size="$(disk_file_size "${disk_px_file}")"
    [ "${disk_px_size}" -le "${DISK_PUBLISHED_LIMIT}" ] || continue
    disk_published_scan "${disk_px_file}" "${DISK_DIGEST_ROLE}" "${disk_px_file}" "${disk_px_names}"
  done
}

disk_published_digests() {
  if [ -n "${KAKIKOMI_SHA256:-}" ]; then
    disk_nb_hex="$(printf '%s\n' "${KAKIKOMI_SHA256}" | tr '[:upper:]' '[:lower:]')"
    printf 'named sha256 %s --sha256\n' "${disk_nb_hex}"
    return 0
  fi
  [ -f "$1" ] || return 0
  disk_published_local "$1"
}

disk_remote_sums() {
  printf '%s\n' "$1.sha256" SHA256SUMS sha256sums.txt sha256sum.txt "$1.sha256sum" \
    "$1.sha512" SHA512SUMS sha512sums.txt "$1.DIGESTS" "$1.CHECKSUM" CHECKSUM b2sums.txt \
    "$1.sha1" SHA1SUMS "$1.md5" MD5SUMS md5sum.txt
}

disk_published_remote() {
  disk_ru_base="${1%%\?*}"
  disk_ru_dir="${disk_ru_base%/*}"
  disk_ru_image="${disk_ru_base##*/}"
  disk_ru_inner="$(disk_unpacked_name "${disk_ru_image}")"
  disk_ru_names="$(disk_digest_names "${disk_ru_image}")"
  disk_ru_list="$(disk_remote_sums "${disk_ru_image}")"
  for disk_ru_name in ${disk_ru_list}; do
    disk_checksum_role "${disk_ru_name}" "${disk_ru_image}" "${disk_ru_inner}" || continue
    disk_ru_file="$2/${disk_ru_name}"
    if ! curl -fsL --connect-timeout 10 --max-time 30 --max-filesize "${DISK_PUBLISHED_LIMIT}" -o "${disk_ru_file}" "${disk_ru_dir}/${disk_ru_name}" 2>/dev/null; then
      rm -f "${disk_ru_file}"
      continue
    fi
    disk_ru_found="$(disk_published_scan "${disk_ru_file}" "${DISK_DIGEST_ROLE}" "${disk_ru_dir}/${disk_ru_name}" "${disk_ru_names}")"
    [ -n "${disk_ru_found}" ] || continue
    printf '%s\n' "${disk_ru_found}"
    return 0
  done
  return 0
}

disk_published_where() {
  case "$1" in
  --sha256) printf 'expected\n' ;;
  *) printf 'published in %s\n' "$1" ;;
  esac
}

disk_published_phrase() {
  disk_ph_label="$(disk_digest_label "$1")"
  disk_ph_where="$(disk_published_where "$2")"
  case "${disk_ph_where}" in
  expected) printf 'the expected %s\n' "${disk_ph_label}" ;;
  *) printf 'the %s %s\n' "${disk_ph_label}" "${disk_ph_where}" ;;
  esac
}

disk_published_sources() {
  printf '%s\n' "$1" | awk '{ sub(/^[^ ]+ /, ""); if (!seen[$0]++) print }'
}

disk_published_refuse() {
  disk_rx_where="$(disk_published_sources "$2" | sed -n '1p')"
  disk_rx_label="$(disk_digest_label "$1")"
  disk_rx_hint="$(disk_digest_install_hint "$1")"
  if [ "${DISK_PUBLISHED_KIND}" = loose ]; then
    disk_warning "${disk_rx_where} holds a ${disk_rx_label} checksum, and no tool here computes it, so it is not checked."
    return 0
  fi
  disk_error "stopped: ${disk_rx_where} publishes a ${disk_rx_label} checksum, and no tool here computes it: ${disk_rx_hint}."
  return 1
}

disk_published_choose() {
  DISK_PUBLISHED_ALG=""
  DISK_PUBLISHED_SET=""
  DISK_PUBLISHED_KIND=named
  printf '%s\n' "$1" | grep -q '^named ' || DISK_PUBLISHED_KIND=loose
  disk_ca_first=""
  disk_ca_first_set=""
  for disk_ca_alg in ${DISK_DIGEST_RANK}; do
    disk_ca_set="$(printf '%s\n' "$1" | awk -v kind="${DISK_PUBLISHED_KIND}" -v alg="${disk_ca_alg}" '$1 == kind && $2 == alg { sub(/^[^ ]+ [^ ]+ /, ""); print }')"
    [ -n "${disk_ca_set}" ] || continue
    if [ -z "${disk_ca_first}" ]; then
      disk_ca_first="${disk_ca_alg}"
      disk_ca_first_set="${disk_ca_set}"
    fi
    disk_digest_computable "${disk_ca_alg}" || continue
    DISK_PUBLISHED_ALG="${disk_ca_alg}"
    DISK_PUBLISHED_SET="${disk_ca_set}"
    return 0
  done
  disk_published_refuse "${disk_ca_first}" "${disk_ca_first_set}"
}

disk_published_hex() {
  if [ "$1" = file ]; then
    disk_digest_stdin "$2" <"${DISK_SRC_ORIGIN}"
  elif [ "$2" = sha256 ] && [ -n "${DISK_SRC_SHA}" ]; then
    printf '%s\n' "${DISK_SRC_SHA}"
  else
    disk_source_digest "$2"
  fi
}

disk_published_check() {
  disk_hc_list="$(disk_digest_algorithms "${DISK_PUBLISHED_ALG}")"
  for disk_hc_alg in ${disk_hc_list}; do
    disk_digest_tool "${disk_hc_alg}" >/dev/null || continue
    disk_hc_hex="$(disk_published_hex "$1" "${disk_hc_alg}")"
    DISK_PUBLISHED_READ="${DISK_PUBLISHED_READ} ${disk_hc_hex}"
    disk_hc_from="$(printf '%s\n' "${DISK_PUBLISHED_SET}" | awk -v hex="${disk_hc_hex}" '$1 == hex { sub(/^[^ ]+ /, ""); print; exit }')"
    if [ -n "${disk_hc_from}" ]; then
      DISK_PUBLISHED_FROM="${disk_hc_from}"
      DISK_PUBLISHED_HIT="${disk_hc_alg}"
      return 0
    fi
  done
  return 1
}

disk_published_matched() {
  DISK_PUBLISHED_OK=1
  disk_pm_phrase="$(disk_published_phrase "${DISK_PUBLISHED_HIT}" "${DISK_PUBLISHED_FROM}")"
  disk_success "The image matches ${disk_pm_phrase}."
}

disk_published_mismatch() {
  disk_mm_where="$(disk_published_sources "${DISK_PUBLISHED_SET}" | sed -n '1p')"
  disk_mm_phrase="$(disk_published_phrase "${DISK_PUBLISHED_ALG}" "${disk_mm_where}")"
  disk_mm_expected="$(printf '%s\n' "${DISK_PUBLISHED_SET}" | awk '!seen[$1]++ { print "expected " $1 }')"
  disk_mm_read="$(printf '%s\n' "${DISK_PUBLISHED_READ}" | awk '{ for (i = 1; i <= NF; i++) if (!seen[$i]++) print "read     " $i }')"
  if [ "${DISK_PUBLISHED_KIND}" = loose ]; then
    disk_warning "the image does not match ${disk_mm_phrase}, which names no image, so it may belong to another download."
    return 0
  fi
  disk_error "stopped: the image does not match ${disk_mm_phrase}."
  disk_log_lines disk_error "${disk_mm_expected}"
  disk_log_lines disk_error "${disk_mm_read}"
  return 1
}
