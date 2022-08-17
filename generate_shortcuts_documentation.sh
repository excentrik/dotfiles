#!/usr/bin/env bash -i
set -o errexit

echo "Compiling list of commands available. Please wait ..."

README="$(sed '/details\./q' README.md)

## Commands available

Run \`list_dotfiles_functions\` to get a list of available commands:

\`\`\`bash"

README+=$'\n'
README+=$(list_dotfiles_functions)
README+=$'\n'
README+="$(echo "\`\`\`")"
echo "${README}" | tr -cd '\11\12\15\40-\176' | tr -d '\r' | sed "s/(B\[m//" > README.md


