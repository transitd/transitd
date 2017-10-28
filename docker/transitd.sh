#!/bin/bash 
if [ ! -f /transitd/transitd.conf ]; then 
         cp /transitd/transitd.conf.sample /transitd/transitd.conf; 
fi 
cd /transitd/src/
sleep 3
lua5.1 daemon.lua -f ../transitd.conf >/var/log/transitd.log 2>&1
