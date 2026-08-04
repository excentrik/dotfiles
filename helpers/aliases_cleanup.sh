#!/usr/bin/env bash
set -euo pipefail

aliases_dir="${HOME}/.aliases"

if [ ! -d "${aliases_dir}" ]; then
    exit 0
fi

for alias_link in "${aliases_dir}"/*; do
    [ -L "${alias_link}" ] || continue
    [ -e "${alias_link}" ] && continue

    rm "${alias_link}"
    echo "Removed broken alias symlink: ${alias_link}"
done
