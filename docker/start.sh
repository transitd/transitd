#!/bin/bash

# forward logs to stdout
rm /var/log/cjdns.log
rm /var/log/transitd.log
ln -sf /dev/stdout /var/log/cjdns.log
ln -sf /dev/stdout /var/log/transitd.log

/authorize.docker.sh
/cjdns.sh &
echo "Web UI available at http://`hostname -i`:65533/"
/transitd.sh
