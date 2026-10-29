#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
duplicates=$(cat "${root}"/bin/kakikomi "${root}"/lib/*.sh |
  sed -n 's/^\([a-z_][a-z0-9_]*\)() {$/\1/p' | sort | uniq -d)
if [ -n "${duplicates}" ]; then
  printf 'function defined more than once:\n%s\n' "${duplicates}" >&2
  exit 1
fi

unprefixed=$(cat "${root}"/bin/kakikomi "${root}"/lib/*.sh |
  grep -oE '[$][{]?[A-Z][A-Z0-9_]*' | sed 's/^[$][{]*//' | sort -u |
  grep -vE '^(DISK|KAKIKOMI)_' | grep -vxE 'HOME|PATH|TMPDIR|NF|XDG_CACHE_HOME|ZSH_VERSION' || true)
if [ -n "${unprefixed}" ]; then
  printf 'environment variable without the KAKIKOMI_ prefix:\n%s\n' "${unprefixed}" >&2
  exit 1
fi

scrub="for disk_inherited in \$(env | sed -n 's/^\\(DISK_[A-Za-z0-9_]*\\)=.*/\\1/p'); do"
if ! grep -qF "${scrub}" "${root}/bin/kakikomi"; then
  printf 'bin/kakikomi must clear every inherited DISK_ variable before it starts\n' >&2
  exit 1
fi
