#!/usr/bin/env bash
set -euo pipefail

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

# Install Claude Code if not already installed
if command -v claude >/dev/null 2>&1; then
    echo "Claude Code already installed: $(claude --version)"
elif ! command -v npm >/dev/null 2>&1; then
    echo "warning: 'npm' not found. Install npm or rerun with DOTFILES_BOOTSTRAP=1 before installing Claude Code." >&2
elif ! npm_prefix_writable; then
    print_npm_permission_help
else
    echo "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
fi

# Verify claude is in PATH
if command -v claude >/dev/null 2>&1; then
    echo "Claude Code is in PATH: $(which claude)"
else
    echo "warning: 'claude' not found in PATH after install. You may need to restart your shell." >&2
fi
