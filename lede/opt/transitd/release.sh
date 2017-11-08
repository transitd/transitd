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
	
	uci delete "network.${ifname}"
	uci del_list "firewall.transitdzone.network=${ifname}"
	
	uci commit network
	uci commit firewall
fi

if [ "$interface6" != "0" ]; then
	
	ifname="transitd_${interface6}"
	
	uci delete "network.${ifname}"
	uci del_list "firewall.transitdzone.network=${ifname}"
	
	uci commit network
	uci commit firewall
fi

/etc/init.d/network reload
/etc/init.d/firewall reload

exit 0
