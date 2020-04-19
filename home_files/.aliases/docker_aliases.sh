#!/usr/bin/env bash
# ------------------------------------
# Docker alias and function
# ------------------------------------

if [ -x "$(command -v docker)" ]; then
  if docker ps 2>&1 | grep -q "permission denied"; then
    __docker="sudo -E docker"
  else
    __docker="docker"
  fi

  # Get latest container ID
  alias dl="${__docker} ps -l -q"

  # Get container processes
  alias dps="${__docker} ps"

  # Get all docker processes including stopped containers
  alias dpa="${__docker} ps -a"

  # List docker images
  alias di="${__docker} images"

  # Run deamonized container, e.g., $dkd base /bin/echo hello
  alias dkd="${__docker} run -d -P"

  # Run interactive container, e.g., $dki base /bin/bash
  alias dki="${__docker} run -i -t -P"

  # Execute interactive container, e.g., $dex base /bin/bash
  alias dex="${__docker} exec -i -t"

  # Stop all containers
  alias dstop="${__docker}"' stop $(${_docker} ps -a -q)'

  # Remove all containers
  alias drm="${__docker}"' rm $(${_docker} ps -a -q) -f'

  # Stop and remove all containers
  alias drmf="${__docker}"' stop $(${_docker} ps -a -q) && ${_docker} rm $(${_docker} ps -a -q)'

  # Remove all docker images
  alias dri="${__docker}"' rmi $(${_docker} images -q -a) -f'

  # Print ${_docker} logs
  alias dkl="${__docker}"' logs'

  # Attach into php-nginx
  eval "function dcdev() {
    if [[ ! \$(is_running_inside_container) ]]; then
      echo 'You cannot connect to a container from inside another container'
      return 1
    fi
    ${__docker}-compose exec --user rohea php-nginx bash
  }"

  # Cleanup docker images and containers
  alias dcleanup=${__docker}' rm $('${__docker}' ps -q -f "status=exited"); '${__docker}' rmi $('${__docker}' images -q -f "dangling=true"); '${__docker}' volume rm $('${__docker}' volume ls -q -f "dangling=true")'

  # Presents a top-like display, showing memory, CPU, network I/O and block I/O
  alias dktop=${__docker}' stats --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}  {{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"'

  # Prune docker system
  alias dkprune=${__docker}' system prune -af'

  unset __docker
fi

if [ -x "$(command -v kubectl)" ]; then
  source <(kubectl completion bash)
fi


# Detect if this command is running inside a docker container
function is_running_inside_container() {
    # Special case to handle WSL under Windows
    if [[ "$(uname -r | sed -r -n 's/.*( *Microsoft *).*/\1/p')" = "Microsoft" ]]; then
        echo 1
    else
        grep docker /proc/1/cgroup -qa 2>/dev/null && echo 1 || echo 0
    fi
}
