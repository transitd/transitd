#!/bin/bash

if [[ -z "${AUTHORIZED_NETWORKS}" ]]; then
	AUTHORIZED_NETWORKS="`ip route|awk '/default/ { print "127.0.0.1/8,::1/128," $3 }'`"
fi

transitd-cli --set "daemon.authorizedNetworks=${AUTHORIZED_NETWORKS}"
