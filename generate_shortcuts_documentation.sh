#!/usr/bin/env bash
set -o errexit

echo "Compiling list of commands available. Please wait ..."

README="$(sed '/details\./q' README.md)

## Commands available

\`\`\`bash"

README+=$'\n'
README+="$(docker-compose run --rm -v "/dev/null:/home/rohea/.hushlogin" dotfiles -c "DOTFILES_NO_INTERACTIVE=1 ~/.dotfiles/install >/dev/null 2>/dev/null; HUSH=1 bash -c -i 'list_dotfiles_functions --full'")"
README+="$(echo "\`\`\`")"
echo "${README}" | tr -cd '\11\12\15\40-\176' | tr -d '\r' | sed "s/(B\[m//" > README.md


