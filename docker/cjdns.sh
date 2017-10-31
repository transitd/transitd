#!/bin/bash
if [ ! -f /etc/cjdroute.conf ]; then
	cjdroute --genconf > /etc/cjdroute.conf
fi

# keep restarting cjdroute if it crashes
while :
do
	killall -s 9 cjdroute
	cjdroute --nobg < /etc/cjdroute.conf >/var/log/cjdns.log 2>&1
	sleep 1
done