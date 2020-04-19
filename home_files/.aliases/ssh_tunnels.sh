#!/usr/bin/env bash

#     ssh(1) obtains configuration data from the following sources in the
#     following order:
#
#           1.   command-line options
#           2.   user's configuration file (~/.ssh/config)
#           3.   system-wide configuration file (/etc/ssh/ssh_config)
#
#     For each parameter, the first obtained value will be used.  The config‐
#     uration files contain sections separated by Host specifications, and
#     that section is only applied for hosts that match one of the patterns
#     given in the specification.  The matched host name is usually the one
#     given on the command line (see the CanonicalizeHostname option for
#     exceptions).
#
#     Since the first obtained value for each parameter is used, more host-
#     specific declarations should be given near the beginning of the file,
#     and general defaults at the end.


_build_ssh_tunnel_arguments() {
  local array=()
  for arg in ${*:2}; do
      array+=("-L $arg")
  done
  echo "-fN -4 ${array[*]} $(_base_ssh_options "${1}") -o ServerAliveInterval=30 -o ServerAliveCountMax=10 -o StrictHostKeyChecking=no -o KeepAlive=yes -o ExitOnForwardFailure=yes -o ControlMaster=auto -oControlPath=/tmp/${1}  ${1}"
}

_assert_ports_are_available() {
  local TUNNELS
  local ports_used=()
  TUNNELS=$(list_open_tunnels)
  for arg in ${*:1}; do
      if [ "$(echo "$arg" | tr ':' ' ' | wc -w)" = "4" ]; then
        PORT=$(echo "$arg" | cut -d ':' -f 2)
      else
        # Assuming
        PORT=$(echo "$arg" | cut -d ':' -f 1)
      fi
      if echo "$TUNNELS" | grep -q ":$PORT"; then
        ports_used+=("$PORT")
      fi
  done
  set +u
  if [ -n "${ports_used[*]}" ]; then
    echo "Port(s) ${ports_used[*]} are already used. Cannot create a new tunnel before they are freed up, e.g. \`killall ssh\`"
    exit 1
  fi
  set -u
}

# Start an SSH connection to the first argument, while creating a tunnel for each of the remaining arguments. Example: `start_tunnel github.com 8888:127.0.0.1:27017 `
start_tunnel() {
  # shellcheck disable=SC2046
  _assert_ports_are_available "${*:2}" && ssh $(_build_ssh_tunnel_arguments "${1}" "${*:2}")
}

_ssh_check_connection() {
  if [ ! -x "$(command -v nc)" ]; then
    echo "Netcat is not available. Please install it to check if tunnels are enabled. Assuming tunnels were set up correctly."
    return 0
  fi
  local failed_count=0
  until [ "$(nc -v -z -n 127.0.0.1 "${@}" 2>&1 | grep -E "open|succeeded" --count)" -eq "$#" ]; do
    sleep 0.2
    ((failed_count++))
    echo "Testing connection... $failed_count"
    if [ ${failed_count} -ge 5 ]; then
      echo "Pipe does not seem to working properly. Please try to restart the tunnel."
      return 1
    fi
  done
  echo "Pipe is fully working"
}

