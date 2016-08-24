FROM alpine:3.3

MAINTAINER Alex <alex@maximum.guru>

# install alpine packages
RUN { \
	echo http://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories; \
	apk add --no-cache bash iptables lua5.1 lua5.1-filesystem lua5.1-dev build-base luarocks5.1 git nodejs python linux-headers unzip sqlite-dev sqlite-libs; \
}

# install lua dependencies
RUN { \
	luarocks-5.1 install luasocket; \
	luarocks-5.1 install cgilua; \
	luarocks-5.1 install lua-cjson; \
	luarocks-5.1 install inifile; \
	luarocks-5.1 install xavante; \
	luarocks-5.1 install wsapi-xavante; \
	luarocks-5.1 install jsonrpc4lua; \
	luarocks-5.1 install sha2; \
	luarocks-5.1 install bencode; \
	luarocks-5.1 install dkjson; \
	luarocks-5.1 install bit32; \
	luarocks-5.1 install alt-getopt; \
	luarocks-5.1 install luaproc; \
	luarocks-5.1 install luasql-sqlite3; \
}

# install cjdns
RUN { \
	git clone --depth=1 https://github.com/cjdelisle/cjdns.git; \
	cd /cjdns; ./do; install -m755 -oroot -groot cjdroute /usr/sbin/cjdroute; \
	rm -rf /cjdns; \
	echo $'#!/bin/bash \n\
if [ ! -f /etc/cjdroute.conf ]; then \n\
	cjdroute --genconf > /etc/cjdroute.conf \n\
fi \n\
cjdroute --nobg < /etc/cjdroute.conf >/var/log/cjdns.log 2>&1 \n\
' > /cjdns.sh; \
	chmod a+x /cjdns.sh; \
}

# install transitd and patch dependencies
RUN { \
	git clone --depth=1 https://github.com/intermesh-networks/transitd.git; \
	patch -p0 /usr/share/lua/5.1/socket/http.lua /transitd/patches/luasocket-ipv6-fix.patch; \
	patch -p0 /usr/share/lua/5.1/cgilua/post.lua /transitd/patches/cgilua-content-type-fix.patch; \
	echo $'#!/bin/bash \n\
if [ ! -f /transitd/transitd.conf ]; then \n\
	 cp /transitd/transitd.conf.sample /transitd/transitd.conf; \n\
fi \n\
cd /transitd/src/; sleep 3; lua5.1 daemon.lua -f ../transitd.conf >/var/log/transitd.log 2>&1 \n\
' > /transitd.sh; \
	chmod a+x /transitd.sh; \
	echo $'#!/bin/bash \n\
cd /transitd/src/; lua5.1 cli.lua "$@" \n\
' > /usr/sbin/transitd-cli; \
	chmod a+x /usr/sbin/transitd-cli; \
}

# cleanup
RUN { \
	apk del --no-cache lua5.1-dev build-base luarocks5.1 git nodejs python linux-headers unzip sqlite-dev; \
}

# startup script
RUN { \
	echo $'#!/bin/bash \n\
transitd-cli --set "`ip route|awk \'/default/ { print "daemon.authorizedNetworks=127.0.0.1/8,::1/128," $3 }\'`" \n\
/cjdns.sh & \n\
/transitd.sh & \n\
echo "Web UI available at http://`hostname -i`:65533/" \n\
echo "# transitd-cli -h" \n\
transitd-cli -h \n\
bash \n\
' > /start.sh; \
	chmod a+x /start.sh; \
}

CMD ["/start.sh"]
