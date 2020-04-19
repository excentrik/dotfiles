#!/usr/bin/env bash

set -o errexit
#----------------------------
# Setup editor
#----------------------------

# Clear EDITOR variable if it cannot be executed
if [[ -n "${EDITOR}" && ! $(type ${EDITOR} >/dev/null 2>/dev/null) ]]; then
    EDITOR=''
fi

if [[ -z "${EDITOR}" && -z "${DOTFILES_NO_INTERACTIVE}" ]] ; then
    # Detect if vi is present
    if type vi >/dev/null 2>/dev/null; then
        VI='vi'
    fi

    # Detect if nano is present
    if type nano >/dev/null 2>/dev/null; then
        NANO='nano'
    fi

    if [[ -z "$VI" && ! -z "$NANO" ]]; then
      echo "Found nano, but no vi. Using nano as default editor"
      EDITOR=nano
    fi

    if [[ ! -z "$VI" &&  -z "$NANO" ]]; then
      echo "Found vi, but no nano. Using vi as default editor"
      EDITOR=vi
    fi

    if [ -z "${EDITOR}" ] ; then
        bash -c "echo -n 'Enter your preferred editor ([vi]/nano) and press [ENTER]: '"
        read EDITOR
    fi
fi
EDITOR="${EDITOR:-vi}"

if [ ! -f ~/.extra ]; then
    touch ~/.extra
fi

case "${EDITOR}" in
vi*)   grep -q -F "EDITOR=$EDITOR" ~/.extra || printf "\nexport EDITOR=$EDITOR" >> ~/.extra ;;
nano*) grep -q -F "EDITOR=$EDITOR" ~/.extra || printf "\nexport EDITOR=$EDITOR" >> ~/.extra ;;
*)     echo "unknown editor: $EDITOR. Aborting" && exit 1 ;;
esac

# Try to use a UI editor when not connected through SSH
if [ -f "/usr/local/bin/edit" ]; then
  read -d '' TEXT <<"EOF"
EDITOR=$(if [[ -n SSH_CONNECTION && -f /usr/local/bin/edit ]]; then echo '/usr/local/bin/edit'; else echo ${EDITOR}; fi)
EOF

  grep -q -F "${TEXT}" ~/.extra || echo "${TEXT}" >> ~/.extra
fi
