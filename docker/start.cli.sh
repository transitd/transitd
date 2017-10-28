#!/bin/bash 

# disable log forwarding to stdout
rm /var/log/cjdns.log
rm /var/log/transitd.log

/authorize.docker.sh
/cjdns.sh & 
/transitd.sh & 
echo "Web UI available at http://`hostname -i`:65533/" 
echo "# transitd-cli -h" 
transitd-cli -h 
bash
