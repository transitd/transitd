#!/usr/bin/env sh

set -e

sessionid=$1
meshIp=$2
ipv4=$3
ipv4gateway=$4
cidr4=$5
ipv6=$6
ipv6gateway=$7
cidr6=$8
interface4=$9
interface6=$10

source /opt/transitd/include.sh

if [ -e "$backupfile" ]; then
	-- TODO: fix this, write proper undo
	cat $backupfile | uci import network
	rm $backupfile
fi

uci commit network

/etc/init.d/network reload
/etc/init.d/firewall reload

exit 0
