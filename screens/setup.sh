export PS1='$ '
export PATH="/Users/Shared/demo/bin:${SCREENS_REPO:?}/bin:${PATH}"
unset KODOUGU_THEME KAKIKOMI_THEME KODOUGU_ACCENT NO_COLOR
export KAKIKOMI_TRASH="/Users/Shared/demo/trash.sh" KAKIKOMI_FSTAB="/Users/Shared/demo/fstab" KAKIKOMI_REMOVAL_WAIT_SECONDS=1
cd /Users/Shared/demo || return 1
clear
