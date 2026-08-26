#!/usr/bin/env bash
set -euo pipefail

# GitHub Copilot CLI currently requires Node.js 24+ at runtime.
COPILOT_MIN_NODE_MAJOR="24"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_NODE_INSTALL_DIR="$HOME/.local/node-v${COPILOT_MIN_NODE_MAJOR}"
LOCAL_NODE_BIN_DIR="$HOME/.local/bin"
COPILOT_SKILLS=(
    evidence-research
    grill-with-docs
    handoff
    tdd
    teach
)
COPILOT_PLUGIN_NAME="impeccable"
COPILOT_PLUGIN_SOURCE="pbakaus/impeccable"

install_default_file() {
    local source_path="$1"
    local target_path="$2"
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
        echo "Installed default Copilot config: ${target_path}"
    fi
}

ensure_experimental_default() {
    local target_path="$1"

    if ! command -v python3 >/dev/null 2>&1; then
        echo "warning: python3 not found; skipping Copilot settings defaults merge." >&2
        return 0
    fi

    if ! python3 - "${target_path}" <<'PY'
import json
import os
import sys
import tempfile

target_path = sys.argv[1]

with open(target_path, "r", encoding="utf-8") as target_file:
    target = json.load(target_file)

if "experimental" in target:
    raise SystemExit(0)

target["experimental"] = True
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
        echo "warning: unable to merge default Copilot settings into ${target_path}." >&2
    fi
}

install_default_file \
    "${BASE_DIR}/home_files/.copilot/settings.json" \
    "$HOME/.copilot/settings.json"
install_default_file \
    "${BASE_DIR}/home_files/.copilot/copilot-instructions.md" \
    "$HOME/.copilot/copilot-instructions.md"
ensure_experimental_default "$HOME/.copilot/settings.json"

link_copilot_skills() {
    local skill
    local source_dir
    local target_dir
    local current_target
    local target_entries

    mkdir -p "$HOME/.copilot/skills"
    for skill in "${COPILOT_SKILLS[@]}"; do
        source_dir="${BASE_DIR}/home_files/.copilot/skills/${skill}"
        target_dir="$HOME/.copilot/skills/${skill}"

        if [ ! -d "${source_dir}" ]; then
            echo "error: managed Copilot skill source is missing: ${source_dir}" >&2
            return 1
        fi

        if [ -L "${target_dir}" ]; then
            current_target="$(readlink "${target_dir}")"
            if [ "${current_target}" = "${source_dir}" ]; then
                echo "Copilot skill already linked: ${skill}"
            else
                echo "error: refusing to replace unrelated Copilot skill symlink: ${target_dir}" >&2
                return 1
            fi
        elif [ -d "${target_dir}" ]; then
            target_entries="$(find "${target_dir}" -mindepth 1 -maxdepth 1 -print | wc -l)"
            if [ "${target_entries}" -eq 1 ] \
                && [ -f "${target_dir}/SKILL.md" ] \
                && cmp -s "${source_dir}/SKILL.md" "${target_dir}/SKILL.md"; then
                rm -rf "${target_dir}"
                ln -s "${source_dir}" "${target_dir}"
                echo "Migrated managed Copilot skill copy to a symlink: ${target_dir}"
            else
                echo "error: refusing to replace an existing Copilot skill directory: ${target_dir}" >&2
                return 1
            fi
        elif [ -e "${target_dir}" ]; then
            echo "error: Copilot skill target is not a directory: ${target_dir}" >&2
            return 1
        else
            ln -s "${source_dir}" "${target_dir}"
            echo "Linked Copilot skill: ${skill}"
        fi
    done
}

link_copilot_skills

ensure_copilot_plugin() {
    local installed_plugins

    if ! installed_plugins="$(copilot plugin list 2>&1)"; then
        echo "error: unable to list installed Copilot plugins: ${installed_plugins}" >&2
        return 1
    fi

    if printf '%s\n' "${installed_plugins}" |
        grep -Eq "(^|[[:space:]])${COPILOT_PLUGIN_NAME}([@[:space:]]|$)"; then
        echo "Copilot plugin already installed: ${COPILOT_PLUGIN_NAME}"
        return 0
    fi

    echo "Installing Copilot plugin: ${COPILOT_PLUGIN_NAME} (${COPILOT_PLUGIN_SOURCE})"
    copilot plugin install "${COPILOT_PLUGIN_SOURCE}"
}

node_major_version() {
    node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true
}

prepend_local_node_bin() {
    mkdir -p "${LOCAL_NODE_BIN_DIR}"
    PATH=":${PATH}:"
    PATH="${PATH//:${LOCAL_NODE_BIN_DIR}:/:}"
    PATH="${LOCAL_NODE_BIN_DIR}:${PATH#:}"
    PATH="${PATH%:}"
    export PATH
}

activate_local_node_install() {
    local tool

    [ -x "${LOCAL_NODE_INSTALL_DIR}/bin/node" ] || return 1

    mkdir -p "${LOCAL_NODE_BIN_DIR}"
    for tool in node npm npx corepack; do
        if [ -x "${LOCAL_NODE_INSTALL_DIR}/bin/${tool}" ]; then
            ln -sf "${LOCAL_NODE_INSTALL_DIR}/bin/${tool}" "${LOCAL_NODE_BIN_DIR}/${tool}"
        fi
    done

    prepend_local_node_bin
    hash -r
}

install_local_node_for_copilot() {
    local platform
    local arch
    local shasums_url
    local archive_name
    local archive_url
    local tmp_dir
    local extracted_dir

    if ! command -v curl >/dev/null 2>&1; then
        echo "warning: Node.js ${COPILOT_MIN_NODE_MAJOR}+ is required for Copilot, but 'curl' is unavailable to install it." >&2
        return 1
    fi

    if ! command -v tar >/dev/null 2>&1; then
        echo "warning: Node.js ${COPILOT_MIN_NODE_MAJOR}+ is required for Copilot, but 'tar' is unavailable to install it." >&2
        return 1
    fi

    case "$(uname -s)" in
        Linux) platform="linux" ;;
        Darwin) platform="darwin" ;;
        *)
            echo "warning: automatic Node.js install for Copilot is unsupported on $(uname -s)." >&2
            return 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch="x64" ;;
        arm64|aarch64) arch="arm64" ;;
        *)
            echo "warning: automatic Node.js install for Copilot is unsupported on architecture $(uname -m)." >&2
            return 1
            ;;
    esac

    shasums_url="https://nodejs.org/dist/latest-v${COPILOT_MIN_NODE_MAJOR}.x/SHASUMS256.txt"
    archive_name="$(curl -fsSL "${shasums_url}" | awk '/node-v[0-9]+\.[0-9]+\.[0-9]+-'"${platform}"'-'"${arch}"'\.tar\.gz$/ {print $2; exit}')"
    if [ -z "${archive_name}" ]; then
        echo "warning: unable to resolve a Node.js ${COPILOT_MIN_NODE_MAJOR}.x download for ${platform}-${arch}." >&2
        return 1
    fi

    archive_url="https://nodejs.org/dist/latest-v${COPILOT_MIN_NODE_MAJOR}.x/${archive_name}"
    tmp_dir="$(mktemp -d)"
    curl -fsSL "${archive_url}" -o "${tmp_dir}/${archive_name}"
    tar -xzf "${tmp_dir}/${archive_name}" -C "${tmp_dir}"
    extracted_dir="${tmp_dir}/${archive_name%.tar.gz}"

    if [ ! -x "${extracted_dir}/bin/node" ]; then
        rm -rf "${tmp_dir}"
        echo "warning: downloaded Node.js archive did not contain a runnable node binary." >&2
        return 1
    fi

    rm -rf "${LOCAL_NODE_INSTALL_DIR}"
    mkdir -p "$(dirname "${LOCAL_NODE_INSTALL_DIR}")"
    mv "${extracted_dir}" "${LOCAL_NODE_INSTALL_DIR}"
    rm -rf "${tmp_dir}"

    if [ ! -x "${LOCAL_NODE_INSTALL_DIR}/bin/node" ]; then
        echo "warning: local Node.js install did not produce ${LOCAL_NODE_INSTALL_DIR}/bin/node." >&2
        return 1
    fi

    activate_local_node_install
    echo "Installed Node.js $("${LOCAL_NODE_INSTALL_DIR}/bin/node" --version 2>/dev/null || echo unknown) for GitHub Copilot CLI at ${LOCAL_NODE_INSTALL_DIR}"
}

is_supported_node_major() {
    local major="$1"

    case "${major}" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "${major}" -ge "${COPILOT_MIN_NODE_MAJOR}" ] ;;
    esac
}

ensure_supported_node() {
    local major

    prepend_local_node_bin
    major="$(node_major_version)"
    if is_supported_node_major "${major}"; then
        return 0
    fi

    if activate_local_node_install; then
        major="$(node_major_version)"
        if is_supported_node_major "${major}"; then
            return 0
        fi
    fi

    if [ -n "${major}" ]; then
        echo "warning: GitHub Copilot CLI requires Node.js ${COPILOT_MIN_NODE_MAJOR} or newer; found Node.js ${major}. Installing a local Node.js ${COPILOT_MIN_NODE_MAJOR}.x runtime..." >&2
    else
        echo "warning: GitHub Copilot CLI requires Node.js ${COPILOT_MIN_NODE_MAJOR} or newer; Node.js was not found. Installing a local Node.js ${COPILOT_MIN_NODE_MAJOR}.x runtime..." >&2
    fi

    if install_local_node_for_copilot; then
        major="$(node_major_version)"
        if is_supported_node_major "${major}"; then
            return 0
        fi
    fi

    echo "warning: unable to provision Node.js ${COPILOT_MIN_NODE_MAJOR}+; skipping GitHub Copilot CLI install." >&2
    return 1
}

copilot_version_output() {
    local output
    local status

    if ! command -v copilot >/dev/null 2>&1; then
        return 1
    fi

    set +e
    if command -v timeout >/dev/null 2>&1; then
        output="$(timeout 10 copilot --version </dev/null 2>&1)"
    else
        output="$(copilot --version </dev/null 2>&1)"
    fi
    status=$?
    set -e
    printf '%s\n' "${output}"
    [ "${status}" -eq 0 ] || return "${status}"

    if printf '%s\n' "${output}" | grep -Eq "Cannot find GitHub Copilot CLI|Install GitHub Copilot CLI"; then
        return 1
    fi

    printf '%s\n' "${output}" | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+'
}

is_copilot_available() {
    copilot_version_output >/dev/null
}

if is_copilot_available; then
    echo "GitHub Copilot CLI already installed: $(copilot_version_output | head -1)"
else
    node_ready=1
    if ensure_supported_node; then
        node_ready=0
    fi

    if ! command -v npm >/dev/null 2>&1; then
        echo "warning: 'npm' not found. Install npm or rerun with DOTFILES_BOOTSTRAP=1 before installing GitHub Copilot CLI." >&2
    elif [ "${node_ready}" -ne 0 ]; then
        echo "warning: skipping GitHub Copilot CLI install because Node.js ${COPILOT_MIN_NODE_MAJOR}+ is unavailable." >&2
    else
        mkdir -p "${HOME}/.local/bin"
        prepend_local_node_bin
        echo "Installing/updating GitHub Copilot CLI (latest)..."
        NPM_CONFIG_PREFIX="${HOME}/.local" npm install -g "@github/copilot"
    fi
fi

# Verify copilot is in PATH
if command -v copilot >/dev/null 2>&1; then
    if copilot_version="$(copilot_version_output)"; then
        echo "GitHub Copilot CLI is in PATH: $(which copilot) ($(printf '%s\n' "${copilot_version}" | head -1))"
        ensure_copilot_plugin
    else
        echo "warning: 'copilot' is in PATH but did not report a non-interactive version. Check the Node.js version used by the shim." >&2
    fi
else
    echo "warning: 'copilot' not found in PATH after install. You may need to restart your shell." >&2
fi
