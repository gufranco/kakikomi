#!/bin/sh
set -eu

: "${SCREENS_REPO:?}"
demo=/Users/Shared/demo
rm -rf "${demo}"
mkdir -p "${demo}/bin"
cp -f "${SCREENS_REPO}/test/shim/sudo" "${demo}/bin/sudo"
mkdir -p "${demo}/Trash"
: >"${demo}/fstab"
# shellcheck disable=SC2016
printf '#!/bin/sh\nmv -f "$1" %s/Trash/\n' "${demo}" >"${demo}/trash.sh"
chmod +x "${demo}/trash.sh"
if [ -d /Volumes/STICK ]; then
  hdiutil detach -quiet /Volumes/STICK
fi
hdiutil create -quiet -size 32m -fs "MS-DOS FAT16" -volname STICK -layout MBRSPUD "${demo}/stick.dmg"
listing=$(hdiutil attach "${demo}/stick.dmg")
device=$(printf '%s\n' "${listing}" | awk 'NR == 1 { print $1 }')
hdiutil create -quiet -size 8m -fs "MS-DOS FAT16" -volname RETRO -layout NONE "${demo}/retro.dmg"
hdiutil attach -quiet "${demo}/retro.dmg"
mkdir -p /Volumes/RETRO/games
for name in tetris pacman galaga; do
  head -c 262144 /dev/urandom >"/Volumes/RETRO/games/${name}.rom"
done
hdiutil detach -quiet /Volumes/RETRO
hdiutil convert -quiet "${demo}/retro.dmg" -format UDTO -o "${demo}/retro-games"
mv -f "${demo}/retro-games.cdr" "${demo}/retro-games.img"
rm -f "${demo}/retro.dmg"
(cd "${demo}" && shasum -a 256 retro-games.img >retro-games.img.sha256)
printf 'DISK=%s\n' "${device##*/}" >"${demo}/demo.env"
