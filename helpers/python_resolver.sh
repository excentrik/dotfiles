#!/usr/bin/env bash

dotfiles_python_major() {
  local interpreter="$1"

  "${interpreter}" -c \
    'import sys; sys.stdout.write(str(sys.version_info[0]))' 2>/dev/null
}

dotfiles_python_is_v3() {
  [ "$(dotfiles_python_major "$1" || true)" = 3 ]
}

dotfiles_python_candidates() {
  local command
  local candidate
  local existing
  local duplicate
  local candidates=()

  for command in python3 python; do
    candidate="$(command -v "${command}" 2>/dev/null || true)"
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
      duplicate=0
      for existing in "${candidates[@]+"${candidates[@]}"}"; do
        if [ "${existing}" = "${candidate}" ]; then
          duplicate=1
          break
        fi
      done
      if [ "${duplicate}" -eq 0 ]; then
        candidates+=("${candidate}")
      fi
    fi
  done

  if [ "${#candidates[@]}" -gt 0 ]; then
    printf '%s\n' "${candidates[@]+"${candidates[@]}"}"
  fi
}

dotfiles_find_python3() {
  local candidate
  local major
  local rejected_python2=0

  while IFS= read -r candidate; do
    [ -n "${candidate}" ] || continue
    major="$(dotfiles_python_major "${candidate}" || true)"
    case "${major}" in
      3)
        printf '%s\n' "${candidate}"
        return 0
        ;;
      2)
        rejected_python2=1
        ;;
    esac
  done < <(dotfiles_python_candidates)

  if [ "${rejected_python2}" -eq 1 ]; then
    echo "error: Python 2 interpreter rejected; Python 3 is required." >&2
  else
    echo "error: no Python 3 interpreter available; checked PATH python3 then python." >&2
  fi
  return 1
}
