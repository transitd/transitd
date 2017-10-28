#!/bin/bash
if [ ! -f /etc/cjdroute.conf ]; then
	cjdroute --genconf > /etc/cjdroute.conf
fi
cjdroute --nobg < /etc/cjdroute.conf >/var/log/cjdns.log 2>&1
