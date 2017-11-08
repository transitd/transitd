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

if [ ! -e "$backupfile" ]; then
	uci export network > $backupfile
fi


if [ "$ipv4" != "0" ]; then
	
	if [ "$interface4" != "0" ]; then
		uci set network.wan.ifname="${interface4}"
	fi
	
	uci set network.wan.proto=static
	uci set network.wan.ipaddr="${ipv4}"
	mask="`cdr2mask $cidr4`"
	uci set network.wan.netmask="${mask}"
	
else
	
	uci set network.wan.ifname=""
	
fi

if [ "$ipv4gateway" != "0" ]; then
	uci set network.wan.gateway="$ipv4gateway"
fi

if [ "$ipv6" != "0" ]; then
	
	if [ "$interface6" != "0" ]; then
		uci set network.wan6.ifname="$interface6"
	fi
	
	uci set network.wan6.proto=static
	uci set network.wan6.ip6addr="${ipv6}/${cidr6}"
	uci set network.wan6.ip6prefix=128
	
else
	
	uci set network.wan6.ifname=""
	
fi

if [ "$ipv6gateway" != "0" ]; then
	uci set network.wan6.ip6gw="$ipv6gateway"
fi

uci commit network

/etc/init.d/network reload
/etc/init.d/firewall reload

exit 0