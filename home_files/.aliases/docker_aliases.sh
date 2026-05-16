#!/usr/bin/env bash
# ------------------------------------
# Docker alias and function
# ------------------------------------

if [ -x "$(command -v docker)" ]; then
  # Determine whether docker needs sudo without invoking the docker CLI at
  # shell init time. The previous `docker ps 2>&1 | grep "permission denied"`
  # probe was slow and noisy when the daemon was down or unreachable (it
  # could hang while the socket timed out, and emitted error text to the
  # pipeline). Use a static socket-permission check instead:
  #   - macOS / Docker Desktop: /var/run/docker.sock typically does not
  #     exist; default to plain `docker`.
  #   - Linux with the user in the `docker` group: socket exists and is
  #     writable; default to plain `docker`.
  #   - Linux without docker-group membership: socket exists but is not
  #     writable; fall back to `sudo -E docker`.
  #   - Rootless docker: the per-user socket lives under $XDG_RUNTIME_DIR;
  #     /var/run/docker.sock is usually absent, so plain `docker` is used.
  __docker="docker"
  if [ -e /var/run/docker.sock ] && [ ! -w /var/run/docker.sock ]; then
    __docker="sudo -E docker"
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
  alias dstop="${__docker} stop \$(${__docker} ps -a -q)"

  # Remove all containers (asks for confirmation; no-op if no containers exist)
  eval "function drm() {
    local ids
    ids=\$(${__docker} ps -a -q)
    if [ -z \"\$ids\" ]; then echo 'No containers to remove.'; return 0; fi
    confirm ${__docker} rm \$ids -f
  }"

  # Stop and remove all containers (asks for confirmation; no-op if none)
  eval "function drmf() {
    local ids
    ids=\$(${__docker} ps -a -q)
    if [ -z \"\$ids\" ]; then echo 'No containers to remove.'; return 0; fi
    local _run
    read -s -t 3 -n 1 -p 'Stop and remove ALL containers? [yN] ' _run; echo
    case \"\$_run\" in
      y|Y) ${__docker} stop \$ids && ${__docker} rm \$ids ;;
    esac
  }"

  # Remove all docker images (asks for confirmation; no-op if no images)
  eval "function dri() {
    local ids
    ids=\$(${__docker} images -q -a)
    if [ -z \"\$ids\" ]; then echo 'No images to remove.'; return 0; fi
    confirm ${__docker} rmi \$ids -f
  }"

  # Print docker logs
  alias dkl="${__docker}"' logs'

  # Attach into php-nginx
  eval "function dcdev() {
    if [[ \"\$(is_running_inside_container)\" == '1' ]]; then
      echo 'You cannot connect to a container from inside another container'
      return 1
    fi
    if ${__docker} compose version >/dev/null 2>&1; then
      ${__docker} compose exec --user rohea php-nginx bash
    else
      ${__docker}-compose exec --user rohea php-nginx bash
    fi
  }"

  # Cleanup docker images and containers (asks for confirmation; no-op when nothing matches)
  eval "function dcleanup() {
    local _run
    read -s -t 3 -n 1 -p 'Cleanup exited containers + dangling images + dangling volumes? [yN] ' _run; echo
    case \"\$_run\" in
      y|Y)
        local containers images volumes
        containers=\$(${__docker} ps -q -f 'status=exited')
        images=\$(${__docker} images -q -f 'dangling=true')
        volumes=\$(${__docker} volume ls -q -f 'dangling=true')
        [ -n \"\$containers\" ] && ${__docker} rm \$containers
        [ -n \"\$images\" ] && ${__docker} rmi \$images
        [ -n \"\$volumes\" ] && ${__docker} volume rm \$volumes
        ;;
    esac
  }"

  # Presents a top-like display, showing memory, CPU, network I/O and block I/O
  alias dktop=${__docker}' stats --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}  {{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"'

  # Prune docker system (asks for confirmation)
  eval "function dkprune() {
    confirm ${__docker} system prune -af
  }"

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
