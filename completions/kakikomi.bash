# shellcheck shell=bash
# shellcheck disable=SC2207

_kakikomi() {
  local cur prev words options
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  options="--verify --no-verify --delete --no-delete --again --reinsert --no-reinsert --zero-tail --sha256 --allow-internal --keep-guard --raw"

  if [[ "${prev}" == "--sha256" ]]; then
    COMPREPLY=()
    return
  fi
  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "${options}" -- "${cur}"))
    return
  fi
  words="$(compgen -f -- "${cur}" || true)"
  if [[ "${COMP_CWORD}" -eq 1 ]]; then
    words="format release doctor version help ${words}"
  elif [[ "${COMP_WORDS[1]}" == "format" && "${COMP_CWORD}" -ge 3 ]]; then
    words="fat32 exfat fat floppy ${words}"
  fi
  COMPREPLY=($(compgen -W "${words}" -- "${cur}"))
}

complete -F _kakikomi kakikomi
