#!/usr/bin/env bash

# Get the IP of the host inside a Docker container
getHostIp() {
    # Check if HOST_IP is already set
    if [ -z "$HOST_IP" ]; then
        # Assume latest Docker with internal host
        HOST_IP=`getent hosts host.docker.internal | awk '{ print $1 }'`

        # check if is Docker for Mac
        if [ -z "$HOST_IP" ]; then
            HOST_IP=`getent hosts docker.for.mac.localhost | awk '{ print $1 }'`
        fi

        # check if is Docker for Windows
        if [ -z "$HOST_IP" ]; then
            HOST_IP=`getent hosts docker.for.win.localhost | awk '{ print $1 }'`
        fi

        # else get host ip from route
        if [ -z "$HOST_IP" ]; then
            HOST_IP=`/sbin/ip route|awk '/default/ { print $3 }'`
        fi
    fi
    echo ${HOST_IP}
}
