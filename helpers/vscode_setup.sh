#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_SOURCE="${BASE_DIR}/home_files/vscode/settings.json"
MACHINE_SETTINGS_SOURCE="${BASE_DIR}/home_files/vscode/machine-settings.json"
KEYBINDINGS_SOURCE="${BASE_DIR}/home_files/vscode/keybindings.json"
EXTENSIONS_SOURCE="${BASE_DIR}/home_files/vscode/extensions.txt"

install_default_file() {
    local source_path="$1"
    local target_path="$2"
    local label="$3"
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
        chmod 600 "${target_path}"
        echo "Installed ${label}: ${target_path}"
    fi
}

seed_user_settings() {
    local user_dir="$1"
    local product_label="$2"

    install_default_file \
        "${SETTINGS_SOURCE}" \
        "${user_dir}/settings.json" \
        "${product_label} user settings"
    install_default_file \
        "${KEYBINDINGS_SOURCE}" \
        "${user_dir}/keybindings.json" \
        "${product_label} keybindings"
}

seed_machine_settings() {
    local machine_dir="$1"
    local product_label="$2"

    install_default_file \
        "${MACHINE_SETTINGS_SOURCE}" \
        "${machine_dir}/settings.json" \
        "${product_label} machine settings"
}

seed_profile() {
    local data_dir="$1"
    local product_label="$2"

    seed_user_settings "${data_dir}/User" "${product_label}"
    seed_machine_settings "${data_dir}/Machine" "${product_label}"
}

install_extensions() {
    local cli_name="$1"
    local product_label="$2"
    local extension_id

    if [ "${DOTFILES_VSCODE_SKIP_EXTENSIONS:-}" = "1" ]; then
        echo "Skipping ${product_label} extension install because DOTFILES_VSCODE_SKIP_EXTENSIONS=1."
        return
    fi

    if ! command -v "${cli_name}" >/dev/null 2>&1; then
        echo "Skipping ${product_label} extension install because '${cli_name}' is unavailable."
        return
    fi

    while IFS= read -r extension_id || [ -n "${extension_id}" ]; do
        case "${extension_id}" in
            ""|\#*) continue ;;
        esac

        echo "Installing ${product_label} extension: ${extension_id}"
        "${cli_name}" --install-extension "${extension_id}"
    done < "${EXTENSIONS_SOURCE}"
}

case "$(uname -s)" in
    Darwin)
        seed_profile "${HOME}/Library/Application Support/Code" "VS Code"
        install_extensions code "VS Code"
        if [ -d "${HOME}/Library/Application Support/Cursor" ]; then
            seed_profile "${HOME}/Library/Application Support/Cursor" "Cursor"
            install_extensions cursor "Cursor"
        fi
        ;;
    Linux)
        seed_profile "${HOME}/.config/Code" "VS Code"
        seed_profile "${HOME}/.vscode-server/data" "VS Code Server"
        install_extensions code "VS Code"
        if [ -d "${HOME}/.config/Cursor" ]; then
            seed_profile "${HOME}/.config/Cursor" "Cursor"
            install_extensions cursor "Cursor"
        fi
        if [ -d "${HOME}/.cursor-server" ]; then
            seed_profile "${HOME}/.cursor-server/data" "Cursor Server"
        fi
        ;;
    *)
        echo "warning: VS Code setup is unsupported on $(uname -s)." >&2
        ;;
esac
