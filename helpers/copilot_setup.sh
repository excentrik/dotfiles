#!/usr/bin/env bash
set -euo pipefail

# Helper: detect a non-writable npm global prefix and skip with guidance.
# See helpers/claude_setup.sh for the longer rationale; the same check
# applies to any `npm install -g` invocation.
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

# Install GitHub Copilot CLI if not already installed
if command -v copilot >/dev/null 2>&1; then
    echo "GitHub Copilot CLI is already installed: $(copilot --version 2>/dev/null || which copilot)"
elif ! command -v npm >/dev/null 2>&1; then
    echo "warning: 'npm' not found. Install npm or rerun with DOTFILES_BOOTSTRAP=1 before installing GitHub Copilot CLI." >&2
elif ! npm_prefix_writable; then
    print_npm_permission_help
else
    echo "Installing GitHub Copilot CLI..."
    npm install -g @github/copilot
fi

# Verify copilot is in PATH
if command -v copilot >/dev/null 2>&1; then
    echo "GitHub Copilot CLI is in PATH: $(which copilot)"
else
    echo "warning: 'copilot' not found in PATH after install. You may need to restart your shell." >&2
fi
