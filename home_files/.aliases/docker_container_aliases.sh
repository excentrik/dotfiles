#!/usr/bin/env bash

# Implementation notes for getHostIp() below:
#
# Resolution order:
#   1. host.docker.internal      (Docker Desktop / recent Docker Engine)
#   2. docker.for.mac.localhost  (legacy Docker for Mac)
#   3. docker.for.win.localhost  (legacy Docker for Windows)
#   4. default-gateway parsing   (Linux + iproute2 + CAP_NET_ADMIN-equivalent)
#
# Each step is best-effort: hostnames may resolve to empty when the embedded
# Docker DNS resolver isn't reachable (rootless docker, custom networks),
# and the route fallback needs /sbin/ip and visibility into the container's
# route table. When every step fails we explicitly print an error to stderr
# and return non-zero rather than silently echoing an empty string, so
# callers like ssh_tunnels.sh fail loudly instead of building bogus URLs.

# Get the IP of the host inside a Docker container
getHostIp() {
    if [ -n "$HOST_IP" ]; then
        echo "${HOST_IP}"
        return 0
    fi

    local resolved=""

    # Step 1-3: try the well-known Docker hostnames.
    if command -v getent >/dev/null 2>&1; then
        for name in host.docker.internal docker.for.mac.localhost docker.for.win.localhost; do
            resolved="$(getent hosts "${name}" 2>/dev/null | awk 'NR==1{print $1}')"
            [ -n "${resolved}" ] && break
        done
    fi

    # Step 4: parse the default gateway from the container's route table.
    if [ -z "${resolved}" ] && [ -x /sbin/ip ]; then
        resolved="$(/sbin/ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
    fi

    if [ -z "${resolved}" ]; then
        echo "getHostIp: could not resolve host IP (no host.docker.internal, no default route)." >&2
        echo "  Set HOST_IP=... explicitly, or expose the host via --add-host=host.docker.internal:host-gateway." >&2
        return 1
    fi

    HOST_IP="${resolved}"
    echo "${HOST_IP}"
}
