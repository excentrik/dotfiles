#!/usr/bin/env bash
set -euo pipefail

if command -v bunx >/dev/null 2>&1; then
    echo "Bun already installed: $(bun --version 2>/dev/null || echo unknown)"
    exit 0
fi

install_bun_macos() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "warning: Homebrew is required to install Bun on macOS. Run the brew role first." >&2
        return 1
    fi

    brew tap oven-sh/bun
    brew install oven-sh/bun/bun
}

install_bun_linux() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "warning: 'curl' not found. Rerun with DOTFILES_BOOTSTRAP=1 or install curl before installing Bun." >&2
        BUN_INSTALL_SKIPPED=1
        return 0
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        echo "warning: 'unzip' not found. Rerun with DOTFILES_BOOTSTRAP=1 or install unzip before installing Bun." >&2
        BUN_INSTALL_SKIPPED=1
        return 0
    fi

    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    # Force an unknown shell so the upstream installer does not append to
    # managed ~/.bashrc or ~/.zshrc symlinks; home_files/.path owns PATH setup.
    curl -fsSL https://bun.sh/install | SHELL=/bin/false bash
}

ensure_bunx_compat() {
    local bun_dir="${BUN_INSTALL:-$HOME/.bun}/bin"
    local bun_path="${bun_dir}/bun"
    local bunx_path="${bun_dir}/bunx"

    [ -x "${bun_path}" ] || return 1
    [ -e "${bunx_path}" ] && return 0

    cat >"${bunx_path}" <<'EOF'
#!/usr/bin/env bash
exec "$(dirname "$0")/bun" x "$@"
EOF
    chmod +x "${bunx_path}"
    echo "Created bunx compatibility wrapper at ${bunx_path}"
}

case "${OSTYPE:-}" in
    darwin*)
        install_bun_macos
        ;;
    linux*)
        install_bun_linux
        ;;
    *)
        echo "warning: unsupported OS for automatic Bun install: ${OSTYPE:-unknown}" >&2
        exit 1
        ;;
esac

if [ "${BUN_INSTALL_SKIPPED:-0}" = "1" ]; then
    exit 0
fi

if command -v bunx >/dev/null 2>&1; then
    echo "Bun installed: $(bun --version 2>/dev/null || echo unknown)"
elif ensure_bunx_compat; then
    echo "Bun installed: $("${BUN_INSTALL:-$HOME/.bun}/bin/bun" --version 2>/dev/null || echo unknown)"
elif [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bunx" ]; then
    echo "Bun installed at ${BUN_INSTALL:-$HOME/.bun}/bin; restart your shell to pick up bunx."
else
    echo "warning: Bun install completed but bunx was not found." >&2
    exit 1
fi
