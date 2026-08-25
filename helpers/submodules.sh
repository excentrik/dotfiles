#!/usr/bin/env bash

dotfiles_has_dry_run() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --dry-run|-n)
        return 0
        ;;
    esac
  done
  return 1
}

dotfiles_is_checked_out_submodule() {
  local path="$1"
  local superproject

  [ -d "${path}" ] || return 1

  superproject="$(git -C "${path}" rev-parse --show-superproject-working-tree 2> /dev/null || true)"
  [ -n "${superproject}" ] || return 1

  [ "$(cd "${superproject}" && pwd)" = "${BASE_DIR}" ]
}

dotfiles_build_submodule_backup_path() {
  local source_path="$1"
  local timestamp="$2"
  local candidate="${source_path}.pre-submodule-backup.${timestamp}"
  local counter=1

  while [ -e "${candidate}" ]; do
    candidate="${source_path}.pre-submodule-backup.${timestamp}.${counter}"
    counter=$((counter + 1))
  done

  printf '%s' "${candidate}"
}

dotfiles_prepare_submodule_paths() {
  local submodule_paths
  local timestamp
  local entry
  local path
  local backup_path

  if ! submodule_paths="$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2> /dev/null)"; then
    return 0
  fi

  timestamp="$(date +%Y%m%d%H%M%S)"
  while IFS= read -r entry; do
    path="${entry#* }"
    [ -n "${path}" ] || continue
    [ -e "${path}" ] || continue

    if dotfiles_is_checked_out_submodule "${path}"; then
      continue
    fi

    backup_path="$(dotfiles_build_submodule_backup_path "${path}" "${timestamp}")"
    echo "Found pre-existing content at ${path}; moving it to ${backup_path} (backup only)"
    echo "To restore it later: mv '${backup_path}' '${path}'"
    mv "${path}" "${backup_path}"
  done <<< "${submodule_paths}"
}

dotfiles_require_initialized_submodules() {
  if [ ! -x "${BASE_DIR}/dotbot/bin/dotbot" ]; then
    echo "error: dry-run requires initialized submodules; Dotbot is missing." >&2
    echo "Run ./install without --dry-run to initialize recorded submodules." >&2
    return 1
  fi
  if [ ! -f "${BASE_DIR}/dotbot/lib/pyyaml/lib/yaml/__init__.py" ]; then
    echo "error: dry-run requires initialized submodules; vendored PyYAML is missing." >&2
    echo "Run ./install without --dry-run to initialize recorded submodules." >&2
    return 1
  fi
}

dotfiles_initialize_submodules() {
  if dotfiles_has_dry_run "$@"; then
    echo "Dry-run requested; skipping submodule update"
    dotfiles_require_initialized_submodules
    return
  fi

  local submodule_args=(--init --recursive --force)
  if [ "${DOTFILES_UPDATE_SUBMODULES:-}" = "1" ]; then
    submodule_args+=(--remote)
    echo "Updating submodules from upstream remotes"
  else
    echo "Updating submodules to recorded commits"
  fi

  dotfiles_prepare_submodule_paths
  git submodule update "${submodule_args[@]+"${submodule_args[@]}"}"
}
