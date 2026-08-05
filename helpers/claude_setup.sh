#!/usr/bin/env bash
set -euo pipefail

CLAUDE_CODE_PACKAGE="@anthropic-ai/claude-code@latest"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Helper: detect a non-writable npm global prefix and skip with guidance.
# `npm install -g` writes to `${npm_prefix}/lib/node_modules` and
# `${npm_prefix}/bin`. On many distros the default prefix is /usr or
# /usr/local, which is not writable by the unprivileged user the dotfiles
# run as. Rather than letting npm fail with a noisy EACCES stack, detect
# the situation up front and tell the user how to recover (per the official
# npm recommendation: configure a user-writable prefix or use a node
# version manager like nvm/fnm/asdf that owns its own prefix).
npm_prefix_writable() {
    local prefix
    prefix="$(npm config get prefix 2>/dev/null || true)"
    [ -n "${prefix}" ] && [ -w "${prefix}" ]
}

print_npm_permission_help() {
    cat >&2 <<'HELP'
warning: npm global prefix is not writable by the current user.
  Skipping install to avoid an EACCES failure. Recover with either:

    # Option A: user-owned npm prefix
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"

    # Option B: install Node via a version manager that owns its prefix
    #   nvm:  https://github.com/nvm-sh/nvm
    #   fnm:  https://github.com/Schniz/fnm
    #   asdf: https://asdf-vm.com/

  Then re-run this role.
HELP
}

remove_retired_managed_link() {
    local link_path="$1"
    local retired_target="$2"
    local current_target

    if [ ! -L "${link_path}" ]; then
        return 0
    fi

    current_target="$(readlink "${link_path}")"
    if [ "${current_target}" = "${retired_target}" ]; then
        rm "${link_path}"
        echo "Removed retired Claude managed link: ${link_path}"
    fi
}

install_default_file() {
    local source_path="$1"
    local target_path="$2"
    local label="${3:-default Claude config}"
    local mode="${4:-600}"
    local current_target

    mkdir -p "$(dirname "${target_path}")"

    if [ -L "${target_path}" ]; then
        current_target="$(readlink "${target_path}")"
        if [ "${current_target}" = "${source_path}" ]; then
            rm "${target_path}"
            echo "Migrated managed symlink to editable local file: ${target_path}"
        fi
    fi

    if [ ! -e "${target_path}" ]; then
        cp "${source_path}" "${target_path}"
        chmod "${mode}" "${target_path}"
        echo "Installed ${label}: ${target_path}"
    fi
}

merge_claude_settings_defaults() {
    local source_path="$1"
    local target_path="$2"

    if ! command -v python3 >/dev/null 2>&1; then
        echo "warning: python3 not found; skipping Claude settings defaults merge." >&2
        return 0
    fi

    if ! python3 - "${source_path}" "${target_path}" <<'PY'
import copy
import json
import os
import sys
import tempfile

source_path, target_path = sys.argv[1], sys.argv[2]

with open(source_path, "r", encoding="utf-8") as source_file:
    source = json.load(source_file)

with open(target_path, "r", encoding="utf-8") as target_file:
    target = json.load(target_file)

changed = False


def add_missing_key(container, key, value):
    global changed
    if key not in container:
        container[key] = copy.deepcopy(value)
        changed = True


permissions_missing = "permissions" not in target
permissions = target.setdefault("permissions", {})
if permissions_missing:
    changed = True
source_permissions = source.get("permissions", {})

source_deny = source_permissions.get("deny", [])
deny_missing = "deny" not in permissions
target_deny = permissions.setdefault("deny", [])
if deny_missing:
    changed = True
for rule in source_deny:
    if rule not in target_deny:
        target_deny.append(rule)
        changed = True

env_missing = "env" not in target
target_env = target.setdefault("env", {})
if env_missing:
    changed = True
for key, value in source.get("env", {}).items():
    add_missing_key(target_env, key, value)

for key in (
    "cleanupPeriodDays",
    "effortLevel",
    "autoCompactEnabled",
    "useAutoModeDuringPlan",
    "outputStyle",
):
    if key in source:
        add_missing_key(target, key, source[key])

if changed:
    directory = os.path.dirname(target_path) or "."
    fd, tmp_path = tempfile.mkstemp(prefix=".settings.", suffix=".json", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
            json.dump(target, tmp_file, indent=2)
            tmp_file.write("\n")
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, target_path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
PY
    then
        echo "warning: unable to merge default Claude settings into ${target_path}." >&2
    fi
}

install_default_file \
    "${BASE_DIR}/home_files/.claude/settings.json" \
    "$HOME/.claude/settings.json" \
    "default Claude config"
merge_claude_settings_defaults \
    "${BASE_DIR}/home_files/.claude/settings.json" \
    "$HOME/.claude/settings.json"
install_default_file \
    "${BASE_DIR}/home_files/.claude/output-styles/direct_fable.md" \
    "$HOME/.claude/output-styles/direct_fable.md" \
    "default Claude output style" \
    644

remove_retired_managed_link \
    "$HOME/.claude/hooks/notify-in-studio.sh" \
    "${BASE_DIR}/home_files/.claude/hooks/notify-in-studio.sh"
remove_retired_managed_link \
    "$HOME/.claude/statusline.sh" \
    "${BASE_DIR}/home_files/.claude/statusline.sh"

is_claude_available() {
    command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1
}

# Install Claude Code if not already installed
if is_claude_available; then
    echo "Claude Code already installed: $(claude --version)"
elif ! command -v npm >/dev/null 2>&1; then
    echo "warning: 'npm' not found. Install npm or rerun with DOTFILES_BOOTSTRAP=1 before installing Claude Code." >&2
elif ! npm_prefix_writable; then
    print_npm_permission_help
else
    echo "Installing latest Claude Code..."
    npm install -g "${CLAUDE_CODE_PACKAGE}"
fi

# Verify claude is in PATH
if command -v claude >/dev/null 2>&1; then
    echo "Claude Code is in PATH: $(which claude)"
else
    echo "warning: 'claude' not found in PATH after install. You may need to restart your shell." >&2
fi
