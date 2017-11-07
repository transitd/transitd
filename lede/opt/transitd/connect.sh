#!/usr/bin/env sh

sessionid=$1
meshIp=$2
ipv4=$3
ipv4gateway=$4
ipv6=$5
ipv6gateway=$6
interface=$7

backupfile=/opt/transitd/uci.network.normal.config

if [ ! -e "$backupfile" ]; then
        uci export network > $backupfile
fi


if [ "$ipv4" != "0" ]; then

if [ "$interface" != "0" ]; then
        uci set network.wan.ifname="$interface"
fi

        uci set network.wan.proto=static
        uci set network.wan.ipaddr="$ipv4"
        # hack
        uci set network.wan.netmask="255.255.255.0"
fi

if [ "$ipv4gateway" != "0" ]; then
        uci set network.wan.gateway="$ipv4gateway"
fi

if [ "$ipv6" != "0" ]; then

if [ "$interface" != "0" ]; then
        uci set network.wan6.ifname="$interface"
fi

        uci set network.wan6.proto=static
        uci set network.wan6.ip6addr="$ipv6"
        # hack
        uci set network.wan6.ip6prefix=120
fi

if [ "$ipv6gateway" != "0" ]; then
        uci set network.wan6.ip6gw="$ipv6gateway"
fi

uci commit network
/etc/init.d/network reload
/etc/init.d/firewall reload
