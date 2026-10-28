#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

MD5_ABC="900150983cd24fb0d6963f7d28e17f72"
SHA1_ABC="a9993e364706816aba3e25717850c26c9cd0d89d"
SHA224_ABC="23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"
SHA256_ABC="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
SHA384_ABC="cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"
SHA512_ABC="ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
BLAKE2B_ABC="ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
SHA3_256_ABC="3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"
CRC32_CHECK="cbf43926"
CRC32_CHECK_UPPER="CBF43926"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-published.XXXXXX")"
  DIR="${WORK}/downloads"
  mkdir -p "${DIR}"
  IMAGE="${DIR}/debian.iso"
  printf 'abc' >"${IMAGE}"
  printf 'notes\n' >"${DIR}/notes.txt"
  mkdir -p "${DIR}/old.sha256"
  NOWHERE="${WORK}/no-such-disk"
}

teardown() {
  if [[ -f "${WORK}/http.pid" ]]; then
    kill "$(cat "${WORK}/http.pid")" 2>/dev/null || true
  fi
  rm -rf "${WORK}"
}

published() {
  disk_test_call disk_published_digests "$1"
}

digest_of() {
  printf '%s' "$2" | disk_test_call disk_digest_stdin "$1"
}

digest_with_path() {
  printf 'abc' | disk_test_call_path "$1" disk_digest_stdin "$2"
}

published_with_setting() {
  export SHA256="$1"
  disk_test_call disk_published_digests "$2"
}

write_nowhere() {
  disk_test_run kakikomi "$1" "${NOWHERE}"
}

write_nowhere_path() {
  disk_test_run_path "$1" kakikomi "$2" "${NOWHERE}"
}

fake_failing_openssl() {
  printf '#!/bin/sh\nexit 1\n' >"$1/openssl"
  chmod +x "$1/openssl"
}

tool_supports() {
  printf '' | openssl dgst "-$1" >/dev/null 2>&1
}

@test "a GNU list names the image among other files" {
  # Arrange
  printf '%s  other.iso\n%s  debian.iso\n%s  third.iso\n' "${MD5_ABC}${MD5_ABC}" "${SHA256_ABC}" "${SHA512_ABC:0:64}" >"${DIR}/SHA256SUMS"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/SHA256SUMS" ]]
}

@test "a binary-mode entry with an asterisk names the image" {
  # Arrange
  printf '%s *debian.iso\n' "${SHA1_ABC}" >"${DIR}/sha1sum.txt"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha1 ${SHA1_ABC} ${DIR}/sha1sum.txt" ]]
}

@test "a BSD tag line carries its algorithm" {
  # Arrange
  printf 'SHA512 (debian.iso) = %s\n' "${SHA512_ABC}" >"${DIR}/CHECKSUM"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha512 ${SHA512_ABC} ${DIR}/CHECKSUM" ]]
}

@test "an OpenSSL line with a SHA2 label reads as SHA-256" {
  # Arrange
  printf 'SHA2-256(debian.iso)= %s\n' "${SHA256_ABC}" >"${DIR}/debian.iso.digest"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/debian.iso.digest" ]]
}

@test "a PGP-signed checksum file ignores the armor and its hash header" {
  # Arrange
  {
    printf '%s\n' '-----BEGIN PGP SIGNED MESSAGE-----' 'Hash: SHA512' ''
    printf '# debian.iso: 3 bytes\n'
    printf 'SHA256 (debian.iso) = %s\n' "${SHA256_ABC}"
    printf '%s\n' '-----BEGIN PGP SIGNATURE-----' '' "${SHA512_ABC}" '-----END PGP SIGNATURE-----'
  } >"${DIR}/Debian-13-x86_64-CHECKSUM"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/Debian-13-x86_64-CHECKSUM" ]]
}

@test "a DIGESTS file takes each algorithm from its header comment" {
  # Arrange
  {
    printf '# BLAKE2B HASH\n%s  debian.iso\n%s  debian.iso.CONTENTS.gz\n' "${BLAKE2B_ABC}" "${SHA512_ABC}"
    printf '# SHA512 HASH\n%s  debian.iso\n' "${SHA512_ABC}"
  } >"${DIR}/debian.iso.DIGESTS"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named blake2b ${BLAKE2B_ABC} ${DIR}/debian.iso.DIGESTS"$'\n'"named sha512 ${SHA512_ABC} ${DIR}/debian.iso.DIGESTS" ]]
}

@test "an unlabeled 128-digit digest may be SHA-512 or BLAKE2b" {
  # Arrange
  printf '%s  debian.iso\n' "${SHA512_ABC}" >"${DIR}/hashes.txt"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha512-or-blake2b ${SHA512_ABC} ${DIR}/hashes.txt" ]]
}

@test "a b2sums file names its algorithm through the file name" {
  # Arrange
  printf '%s  debian.iso\n' "${BLAKE2B_ABC}" >"${DIR}/b2sums.txt"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named blake2b ${BLAKE2B_ABC} ${DIR}/b2sums.txt" ]]
}

@test "a bare uppercase digest with a CRLF ending counts for the image it is named after" {
  # Arrange
  local upper
  upper="$(printf '%s' "${SHA256_ABC}" | tr '[:lower:]' '[:upper:]')"
  printf '%s\r\n' "${upper}" >"${IMAGE}.sha256"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${IMAGE}.sha256" ]]
}

@test "a checksum file named after the image counts even when it names an older file name" {
  # Arrange
  printf '%s  debian-13.0.0-amd64-netinst.iso\n' "${MD5_ABC}" >"${IMAGE}.md5"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named md5 ${MD5_ABC} ${IMAGE}.md5" ]]
}

@test "a checksum file named after the image without its extension counts" {
  # Arrange
  printf '%s\n' "${SHA256_ABC}" >"${DIR}/debian.sha256"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/debian.sha256" ]]
}

@test "a lone digest in a generic checksum file is loose" {
  # Arrange
  printf 'SHA256: %s\n' "${SHA256_ABC}" >"${DIR}/sha256.txt"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "loose sha256 ${SHA256_ABC} ${DIR}/sha256.txt" ]]
}

@test "a list that never names the image publishes nothing for it" {
  # Arrange
  printf '%s  other.iso\n' "${SHA256_ABC}" >"${DIR}/SHA256SUMS"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "a CertUtil report pairs the image name with the digest on the next line" {
  # Arrange
  local pairs
  pairs="$(printf '%s' "${SHA256_ABC}" | sed 's/../& /g; s/ $//')"
  printf 'SHA256 hash of C:\\Users\\me\\Downloads\\debian.iso:\r\n%s\r\nCertUtil: -hashfile command completed successfully.\r\n' "${pairs}" >"${DIR}/hash.txt"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/hash.txt" ]]
}

@test "a PowerShell table row names the image by its Windows path" {
  # Arrange
  local upper
  upper="$(printf '%s' "${SHA256_ABC}" | tr '[:lower:]' '[:upper:]')"
  printf '\nAlgorithm       Hash                Path\n---------       ----                ----\nSHA256          %s C:\\Users\\me\\Downloads\\debian.iso\n' "${upper}" >"${DIR}/hash.txt"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/hash.txt" ]]
}

@test "a PowerShell list pairs the digest with the path that follows it" {
  # Arrange
  printf 'Algorithm : SHA256\nHash      : %s\nPath      : C:\\Users\\me\\Downloads\\debian.iso\n' "${SHA256_ABC}" >"${DIR}/hash.txt"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/hash.txt" ]]
}

@test "an SFV file lists a CRC32 after the name and its dated comment is skipped" {
  # Arrange
  printf '; generated 20261027 12345678\ndebian.iso %s\n' "${CRC32_CHECK_UPPER}" >"${DIR}/release.sfv"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named crc32 ${CRC32_CHECK} ${DIR}/release.sfv" ]]
}

@test "a compressed image matches entries for itself and for its contents" {
  # Arrange
  local packed="${DIR}/disk.img.xz"
  printf 'abc' >"${packed}"
  printf '%s  disk.img.xz\n%s  disk.img\n%s  disk.img.xz.torrent\n' "${SHA256_ABC}" "${SHA512_ABC:0:64}" "${MD5_ABC}${MD5_ABC}" >"${DIR}/SHA256SUMS"

  # Act
  run published "${packed}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/SHA256SUMS"$'\n'"named sha256 ${SHA512_ABC:0:64} ${DIR}/SHA256SUMS" ]]
}

@test "an image name with spaces and parentheses is found in a list" {
  # Arrange
  local spaced="${DIR}/My Disk (1).iso"
  printf 'abc' >"${spaced}"
  printf '%s  My Disk (1).iso\n%s  My Disk.iso\n' "${SHA256_ABC}" "${MD5_ABC}${MD5_ABC}" >"${DIR}/SHA256SUMS"

  # Act
  run published "${spaced}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/SHA256SUMS" ]]
}

@test "a list entry with a directory prefix still names the image" {
  # Arrange
  printf '%s  ./images/debian.iso\n' "${SHA256_ABC}" >"${DIR}/SHA256SUMS"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/SHA256SUMS" ]]
}

@test "a digest whose length contradicts its label is ignored" {
  # Arrange
  printf 'SHA256 (debian.iso) = %s\n' "${MD5_ABC}" >"${DIR}/CHECKSUM"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ -z "${output}" ]]
}

@test "an algorithm kakikomi does not know is ignored rather than misread" {
  # Arrange
  printf 'BLAKE2s (debian.iso) = %s\n' "${SHA256_ABC}" >"${DIR}/CHECKSUM"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ -z "${output}" ]]
}

@test "a SHA3 tag line reads as SHA3-256" {
  # Arrange
  printf 'SHA3-256 (debian.iso) = %s\n' "${SHA3_256_ABC}" >"${DIR}/CHECKSUM"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha3-256 ${SHA3_256_ABC} ${DIR}/CHECKSUM" ]]
}

@test "a JSON manifest spread over lines pairs the name with the digest after it" {
  # Arrange
  printf '{\n  "name": "debian.iso",\n  "sha256": "%s"\n}\n' "${SHA256_ABC}" >"${DIR}/debian.iso.json"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ${DIR}/debian.iso.json" ]]
}

@test "signatures, archives and files larger than a mebibyte are never read" {
  # Arrange
  printf '%s  debian.iso\n' "${SHA256_ABC}" >"${DIR}/SHA256SUMS.sign"
  printf '%s\n' "${SHA256_ABC}" >"${IMAGE}.zip"
  printf '%s  debian.iso\n' "${MD5_ABC}" >"${DIR}/MD5SUMS"
  head -c 1048576 /dev/zero >>"${DIR}/MD5SUMS"

  # Act
  run published "${IMAGE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "the SHA256 setting replaces every published file" {
  # Arrange
  printf '%s  debian.iso\n' "${MD5_ABC}" >"${DIR}/MD5SUMS"
  local upper
  upper="$(printf '%s' "${SHA256_ABC}" | tr '[:lower:]' '[:upper:]')"

  # Act
  run published_with_setting "${upper}" "${IMAGE}"

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} --sha256" ]]
}

@test "a downloaded image finds the checksum list next to it on the server" {
  # Arrange
  local site="${WORK}/site"
  mkdir -p "${site}"
  printf '%s  debian.iso\n' "${SHA512_ABC}" >"${site}/SHA512SUMS"
  local port
  port="$(sh "${DISK_TESTS_DIR}/http-server.sh" "${site}" "${WORK}")"
  mkdir -p "${WORK}/fetched"

  # Act
  run disk_test_call disk_published_remote "http://127.0.0.1:${port}/debian.iso" "${WORK}/fetched"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "named sha512 ${SHA512_ABC} http://127.0.0.1:${port}/SHA512SUMS" ]]
}

@test "a server whose lists never name the image publishes nothing" {
  # Arrange
  local site="${WORK}/site"
  mkdir -p "${site}"
  printf '%s  other.iso\n' "${SHA256_ABC}" >"${site}/SHA256SUMS"
  local port
  port="$(sh "${DISK_TESTS_DIR}/http-server.sh" "${site}" "${WORK}")"
  mkdir -p "${WORK}/fetched"

  # Act
  run disk_test_call disk_published_remote "http://127.0.0.1:${port}/debian.iso" "${WORK}/fetched"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "MD5 of abc matches the RFC 1321 vector" {
  # Arrange
  local algorithm="md5"

  # Act
  run digest_of "${algorithm}" abc

  # Assert
  [[ "${output}" == "${MD5_ABC}" ]]
}

@test "SHA-1 of abc matches the FIPS 180 vector" {
  # Arrange
  local algorithm="sha1"

  # Act
  run digest_of "${algorithm}" abc

  # Assert
  [[ "${output}" == "${SHA1_ABC}" ]]
}

@test "SHA-224 of abc matches the FIPS 180 vector" {
  # Arrange
  local algorithm="sha224"

  # Act
  run digest_of "${algorithm}" abc

  # Assert
  [[ "${output}" == "${SHA224_ABC}" ]]
}

@test "SHA-384 of abc matches the FIPS 180 vector" {
  # Arrange
  local algorithm="sha384"

  # Act
  run digest_of "${algorithm}" abc

  # Assert
  [[ "${output}" == "${SHA384_ABC}" ]]
}

@test "SHA-512 of abc matches the FIPS 180 vector" {
  # Arrange
  local algorithm="sha512"

  # Act
  run digest_of "${algorithm}" abc

  # Assert
  [[ "${output}" == "${SHA512_ABC}" ]]
}

@test "BLAKE2b of abc matches the RFC 7693 vector" {
  # Arrange
  command -v b2sum >/dev/null || tool_supports blake2b512 || skip "no BLAKE2b tool is installed"

  # Act
  run digest_of blake2b abc

  # Assert
  [[ "${output}" == "${BLAKE2B_ABC}" ]]
}

@test "SHA3-256 of abc matches the FIPS 202 vector" {
  # Arrange
  tool_supports sha3-256 || skip "openssl here has no SHA3"

  # Act
  run digest_of sha3-256 abc

  # Assert
  [[ "${output}" == "${SHA3_256_ABC}" ]]
}

@test "CRC32 of the standard check string is cbf43926" {
  # Arrange
  local text="123456789"

  # Act
  run digest_of crc32 "${text}"

  # Assert
  [[ "${output}" == "${CRC32_CHECK}" ]]
}

@test "MD5 falls back to openssl without md5sum or md5" {
  # Arrange
  local farm
  farm="$(disk_test_farm md5sum md5)"

  # Act
  run digest_with_path "${farm}" md5

  # Assert
  [[ "${output}" == "${MD5_ABC}" ]]
}

@test "SHA-512 falls back to shasum without sha512sum" {
  # Arrange
  command -v shasum >/dev/null || skip "shasum is not installed"
  local farm
  farm="$(disk_test_farm sha512sum)"

  # Act
  run disk_test_call_path "${farm}" disk_digest_tool sha512

  # Assert
  [[ "${output}" == "shasum" ]]
}

@test "SHA-512 falls back to openssl without sha512sum or shasum" {
  # Arrange
  local farm
  farm="$(disk_test_farm sha512sum shasum)"

  # Act
  run digest_with_path "${farm}" sha512

  # Assert
  [[ "${output}" == "${SHA512_ABC}" ]]
}

@test "MD5 uses the BSD md5 when md5sum is missing" {
  # Arrange
  command -v md5 >/dev/null || skip "md5 is not installed"
  local farm
  farm="$(disk_test_farm md5sum)"

  # Act
  run digest_with_path "${farm}" md5

  # Assert
  [[ "${output}" == "${MD5_ABC}" ]]
}

@test "BLAKE2b falls back to openssl without b2sum" {
  # Arrange
  tool_supports blake2b512 || skip "openssl here has no BLAKE2b"
  local farm
  farm="$(disk_test_farm b2sum)"

  # Act
  run digest_with_path "${farm}" blake2b

  # Assert
  [[ "${output}" == "${BLAKE2B_ABC}" ]]
}

@test "no tool computes BLAKE2b without b2sum or a capable openssl" {
  # Arrange
  local farm
  farm="$(disk_test_farm b2sum openssl)"

  # Act
  run disk_test_call_path "${farm}" disk_digest_tool blake2b

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ -z "${output}" ]]
}

@test "no tool computes CRC32 without gzip" {
  # Arrange
  local farm
  farm="$(disk_test_farm gzip)"

  # Act
  run disk_test_call_path "${farm}" disk_digest_tool crc32

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "a relative image path finds the list in the current directory" {
  # Arrange
  printf '%s  debian.iso\n' "${SHA256_ABC}" >"${DIR}/SHA256SUMS"
  cd "${DIR}"

  # Act
  run published debian.iso

  # Assert
  [[ "${output}" == "named sha256 ${SHA256_ABC} ./SHA256SUMS" ]]
}

@test "a missing image path publishes nothing" {
  # Arrange
  printf '%s  debian.iso\n' "${SHA256_ABC}" >"${DIR}/SHA256SUMS"

  # Act
  run published "${DIR}/gone.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "an algorithm kakikomi does not know has no tool" {
  # Arrange
  local algorithm="whirlpool"

  # Act
  run disk_test_call disk_digest_tool "${algorithm}"

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "an openssl without BLAKE2b is passed over" {
  # Arrange
  local farm
  farm="$(disk_test_farm b2sum openssl)"
  fake_failing_openssl "${farm}"

  # Act
  run disk_test_call_path "${farm}" disk_digest_tool blake2b

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "the install hint for MD5 names md5sum" {
  # Arrange
  local algorithm="md5"

  # Act
  run disk_test_call disk_digest_install_hint "${algorithm}"

  # Assert
  [[ "${output}" == "install coreutils for md5sum, or openssl" ]]
}

@test "the install hint for CRC32 names gzip" {
  # Arrange
  local algorithm="crc32"

  # Act
  run disk_test_call disk_digest_install_hint "${algorithm}"

  # Assert
  [[ "${output}" == "install gzip" ]]
}

@test "the install hint for SHA-256 names coreutils, shasum and openssl" {
  # Arrange
  local algorithm="sha256"

  # Act
  run disk_test_call disk_digest_install_hint "${algorithm}"

  # Assert
  [[ "${output}" == "install coreutils, perl for shasum, or openssl" ]]
}

@test "kakikomi stops before any disk when the image does not match a published MD5" {
  # Arrange
  printf 'd41d8cd98f00b204e9800998ecf8427e  debian.iso\n' >"${DIR}/MD5SUMS"

  # Act
  run write_nowhere "${IMAGE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: stopped: the image does not match the MD5 published in ${DIR}/MD5SUMS."$'\n'"kakikomi: expected d41d8cd98f00b204e9800998ecf8427e"$'\n'"kakikomi: read     ${MD5_ABC}"* ]]
  [[ "${output}" != *"not a device or mount point"* ]]
}

@test "kakikomi goes on to the target once the image matches a published SHA-512" {
  # Arrange
  printf '%s  debian.iso\n' "${SHA512_ABC}" >"${DIR}/SHA512SUMS"

  # Act
  run write_nowhere "${IMAGE}"

  # Assert
  [[ "${output}" == *"Checking the image against the SHA-512 published in ${DIR}/SHA512SUMS."$'\n'"The image matches the SHA-512 published in ${DIR}/SHA512SUMS."* ]]
  [[ "${output}" == *"kakikomi: not a device or mount point: ${NOWHERE}"* ]]
}

@test "kakikomi settles an unlabeled 128-digit digest as BLAKE2b when SHA-512 does not match" {
  # Arrange
  command -v b2sum >/dev/null || tool_supports blake2b512 || skip "no BLAKE2b tool is installed"
  printf '%s  debian.iso\n' "${BLAKE2B_ABC}" >"${DIR}/hashes.txt"

  # Act
  run write_nowhere "${IMAGE}"

  # Assert
  [[ "${output}" == *"Checking the image against the SHA-512 or BLAKE2b published in ${DIR}/hashes.txt."$'\n'"The image matches the BLAKE2b published in ${DIR}/hashes.txt."* ]]
}

@test "kakikomi matches a CRC32 from an SFV file" {
  # Arrange
  printf 'debian.iso 352441C2\n' >"${DIR}/release.sfv"

  # Act
  run write_nowhere "${IMAGE}"

  # Assert
  [[ "${output}" == *"The image matches the CRC32 published in ${DIR}/release.sfv."* ]]
}

@test "kakikomi only warns when a loose digest that names no image differs" {
  # Arrange
  printf '%s\n' "${SHA512_ABC:0:64}" >"${DIR}/sha256.txt"

  # Act
  run write_nowhere "${IMAGE}"

  # Assert
  [[ "${output}" == *"kakikomi: warning: the image does not match the SHA-256 published in ${DIR}/sha256.txt, which names no image, so it may belong to another download."* ]]
  [[ "${output}" == *"kakikomi: not a device or mount point: ${NOWHERE}"* ]]
}

@test "kakikomi stops when no tool here computes the published algorithm" {
  # Arrange
  printf '%s  debian.iso\n' "${BLAKE2B_ABC}" >"${DIR}/b2sums.txt"
  local farm
  farm="$(disk_test_farm b2sum openssl)"

  # Act
  run write_nowhere_path "${farm}" "${IMAGE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: stopped: ${DIR}/b2sums.txt publishes a BLAKE2b checksum, and no tool here computes it: install coreutils for b2sum, or OpenSSL 1.1 or later."* ]]
  [[ "${output}" != *"not a device or mount point"* ]]
}

@test "kakikomi warns and goes on when no tool computes a loose digest" {
  # Arrange
  printf 'SHA3-256: %s\n' "${SHA3_256_ABC}" >"${DIR}/hash.txt"
  local farm
  farm="$(disk_test_farm openssl)"

  # Act
  run write_nowhere_path "${farm}" "${IMAGE}"

  # Assert
  [[ "${output}" == *"kakikomi: warning: ${DIR}/hash.txt holds a SHA3-256 checksum, and no tool here computes it, so it is not checked."* ]]
  [[ "${output}" == *"kakikomi: not a device or mount point: ${NOWHERE}"* ]]
}

@test "kakikomi matches a compressed image by the MD5 of its contents" {
  # Arrange
  printf 'abc' | gzip -c >"${DIR}/disk.img.gz"
  printf '%s  disk.img\n' "${MD5_ABC}" >"${DIR}/MD5SUMS"

  # Act
  run write_nowhere "${DIR}/disk.img.gz"

  # Assert
  [[ "${output}" == *"Checking the image against the MD5 published in ${DIR}/MD5SUMS."*"The image matches the MD5 published in ${DIR}/MD5SUMS."* ]]
}

@test "kakikomi stops a download that does not match the list on its server" {
  # Arrange
  local site="${WORK}/site"
  mkdir -p "${site}"
  printf 'abc' >"${site}/debian.iso"
  printf '%s  debian.iso\n' "${SHA512_ABC:0:64}" >"${site}/SHA256SUMS"
  local port
  port="$(sh "${DISK_TESTS_DIR}/http-server.sh" "${site}" "${WORK}")"

  # Act
  run disk_test_run_env "XDG_CACHE_HOME=${WORK}/cache" kakikomi "http://127.0.0.1:${port}/debian.iso" "${NOWHERE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: stopped: the image does not match the SHA-256 published in http://127.0.0.1:${port}/SHA256SUMS."* ]]
}

@test "doctor names the missing BLAKE2b tool without failing" {
  # Arrange
  local farm
  farm="$(disk_test_farm b2sum openssl)"

  # Act
  run disk_test_run_path "${farm}" kakikomi doctor

  # Assert
  [[ "${output}" =~ (^|$'\n')b2sum\|openssl\ +missing\ +checks\ a\ published\ BLAKE2b\ checksum ]]
}
