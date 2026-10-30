#!/bin/sh
os="$(uname -s)"
if [ "${os}" = "Darwin" ]; then
  diskutil mountDisk "$1" >/dev/null
else
  mount_dir="$(mktemp -d)"
  sudo mount "$1p1" "${mount_dir}"
fi
