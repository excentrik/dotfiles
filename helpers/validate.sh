#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${BASE_DIR}"

usage() {
  cat <<'USAGE'
Usage: helpers/validate.sh [--all-roles]

Runs non-mutating validation checks:
  - Bash syntax checks
  - Optional zsh syntax checks when zsh is installed
  - Host role reference checks
  - Dotbot link target checks
  - Dotbot dry-runs using a temporary HOME

By default, role checks are limited to Linux/WSL-oriented hosts: unix, wsl, docker.
Use --all-roles to include every role config, including macOS, zsh, and Mongo.
USAGE
}

ALL_ROLES=0
for arg in "$@"; do
  case "${arg}" in
    --all-roles)
      ALL_ROLES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

status() {
  printf '\n==> %s\n' "$1"
}

add_unique() {
  local item="$1"
  shift
  local existing
  for existing in "$@"; do
    if [ "${existing}" = "${item}" ]; then
      return 1
    fi
  done
  return 0
}

collect_role_configs() {
  local configs=()
  local role
  local host
  local host_file
  local role_file

  configs+=("meta/base.yaml")

  if [ "${ALL_ROLES}" -eq 1 ]; then
    for role_file in meta/roles/*.yaml; do
      configs+=("${role_file}")
    done
  else
    for host in unix wsl docker; do
      host_file="meta/hosts/${host}.yaml"
      if [ ! -f "${host_file}" ]; then
        echo "Missing host file: ${host_file}" >&2
        return 1
      fi

      while IFS= read -r role; do
        [ -n "${role}" ] || continue
        role_file="meta/roles/${role}.yaml"
        if [ ! -f "${role_file}" ]; then
          echo "${host_file} references missing role: ${role}" >&2
          return 1
        fi
        if add_unique "${role_file}" "${configs[@]}"; then
          configs+=("${role_file}")
        fi
      done < <(sed -n 's/^[[:space:]]*-[[:space:]]*\([^:[:space:]]*\):.*/\1/p' "${host_file}")
    done
  fi

  printf '%s\n' "${configs[@]}"
}

check_bash_syntax() {
  status "Checking Bash syntax"
  local files=(
    install
    install-role
    generate_shortcuts_documentation.sh
    helpers/*.sh
    home_files/.bash_profile
    home_files/.bashrc
    home_files/.bash_aliases
    home_files/.path
    home_files/.exports
    home_files/.profile
    home_files/.startup
    home_files/.bash_prompt
    home_files/.aliases/*.sh
  )
  bash -n "${files[@]}"
}

check_zsh_syntax() {
  status "Checking zsh syntax"
  if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh not found; skipping zsh syntax checks"
    return 0
  fi

  zsh -n \
    home_files/.zshrc \
    home_files/.ohmyzshrc \
    home_files/.zshenv \
    home_files/.zsh_aliases \
    home_files/.zsh_prompt
}

check_link_targets() {
  status "Checking Dotbot link targets"
  local configs=("$@")
  local failures=0
  local yaml
  local target

  while IFS=: read -r yaml target; do
    [ -n "${target}" ] || continue
    if [ ! -e "${target}" ]; then
      echo "${yaml} references missing target: ${target}" >&2
      failures=$((failures + 1))
    fi
  done < <(
    awk '{
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^home_files\//) {
          gsub(/[,"'\''"]/, "", $i)
          print FILENAME ":" $i
        }
      }
    }' "${configs[@]}"
  )

  if [ "${failures}" -ne 0 ]; then
    return 1
  fi
}

check_dotbot_dry_runs() {
  status "Running Dotbot dry-runs"
  local configs=("$@")
  local tmp_home
  local cfg
  local output

  if [ ! -x "./dotbot/bin/dotbot" ]; then
    echo "Dotbot is missing. Run: git submodule update --init --recursive" >&2
    return 1
  fi

  tmp_home="$(mktemp -d)"

  for cfg in "${configs[@]}"; do
    printf 'Dry-run %s\n' "${cfg}"
    if ! output="$(HOME="${tmp_home}" ./dotbot/bin/dotbot -d "${BASE_DIR}" --plugin dotbot-brew -c "${cfg}" --dry-run --exit-on-failure 2>&1)"; then
      echo "${output}" >&2
      rm -rf "${tmp_home}"
      return 1
    fi
  done

  rm -rf "${tmp_home}"
}

main() {
  local configs
  mapfile -t configs < <(collect_role_configs)

  check_bash_syntax
  check_zsh_syntax
  check_link_targets "${configs[@]}"
  check_dotbot_dry_runs "${configs[@]}"

  status "Validation passed"
}

main "$@"
