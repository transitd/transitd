#!/usr/bin/env sh

set -e

uci del firewall.transitdofflinehttp

uci set firewall.transitdofflinehttp=redirect
uci set firewall.transitdofflinehttp.name='transitd-offline-http'
uci set firewall.transitdofflinehttp.src=lan
uci set firewall.transitdofflinehttp.proto=tcp
uci set firewall.transitdofflinehttp.src_dport=80
uci set firewall.transitdofflinehttp.dest_port=65530
uci set firewall.transitdofflinehttp.dest_ip='192.168.1.1'
uci set firewall.transitdofflinehttp.dest=lan

uci commit firewall

uci del dhcp.@dnsmasq[-1].address
uci add_list dhcp.@dnsmasq[-1].address=/#/192.168.1.1
uci commit dhcp

/etc/init.d/dnsmasq reload

exit 0
