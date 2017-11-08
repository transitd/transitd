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

if [ "$interface4" != "0" ]; then
	
	ifname="transitd_${interface4}"
	
	uci set "network.${ifname}=interface"
	uci set "network.${ifname}.proto=static"
	uci set "network.${ifname}.bridge=false"
	uci set "network.${ifname}.ifname=${interface4}"
	
	if [ "$ipv4gateway" != "0" ]; then
		uci set "network.${ifname}.ipaddr=${ipv4gateway}"
	fi
	
	if [ "$cidr4" != "0" ]; then
		mask="`cdr2mask $cidr4`"
		uci set "network.${ifname}.netmask=${mask}"
	fi
	
	uci add_list "firewall.transitdzone.network=${ifname}"
	
	uci commit network
	uci commit firewall
fi

if [ "$interface6" != "0" ]; then
	
	ifname="transitd_${interface6}"
	
	uci set "network.${ifname}=interface"
	uci set "network.${ifname}.proto=static"
	uci set "network.${ifname}.bridge=false"
	uci set "network.${ifname}.ifname=${interface6}"
	
	if [ "$ipv6gateway" != "0" ]; then
	if [ "$cidr6" != "0" ]; then
		uci set "network.${ifname}.ip6addr=${ipv6gateway}/${cidr6}"
		uci set "network.${ifname}.ip6prefix=128"
	fi
	fi
	
	uci add_list "firewall.transitdzone.network=${ifname}"
	
	uci commit network
	uci commit firewall
fi

/etc/init.d/network reload
/etc/init.d/firewall reload

exit 0
