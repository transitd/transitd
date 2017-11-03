#!/usr/bin/env sh

sessionid=$1
meshIp=$2
ipv4=$3
ipv4gateway=$4
ipv6=$5
ipv6gateway=$6
interface=$7

backupfile=/opt/transitd/uci.network.normal.config

if [ -e "$backupfile" ]; then
cat $backupfile | uci import network
rm $backupfile
fi

uci commit network

/etc/init.d/network reload
/etc/init.d/firewall reload
