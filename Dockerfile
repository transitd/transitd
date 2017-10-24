# @file Dockerfile
# @license The MIT License (MIT)
# @copyright 2016 Alex <alex@maximum.guru>

FROM ubuntu:16.04

MAINTAINER Alex <alex@maximum.guru>

# install alpine packages
RUN { \
	apt-get update && apt-get install -yq \
	bash \
	iptables \
	net-tools \
	iproute2 \
	inetutils-ping \
	lua5.1 \
	lua-filesystem \
	liblua5.1-0-dev \
	build-essential \
	luarocks \
	git \
	nodejs \
	python \
	linux-headers-generic \
	unzip \
	libsqlite3-dev \
	sqlite3; \
}

RUN { \
	rm /bin/sh && \
	ln -s bash /bin/sh; \
}

# install lua dependencies
RUN { \
	luarocks install luasocket && \
	luarocks install cgilua && \
	luarocks install lua-cjson && \
	luarocks install inifile && \
	luarocks install xavante && \
	luarocks install wsapi-xavante && \
	luarocks install jsonrpc4lua && \
	luarocks install sha2 && \
	luarocks install bencode && \
	luarocks install dkjson && \
	luarocks install bit32 && \
	luarocks install alt-getopt && \
	luarocks install luaproc && \
	luarocks install luasql-sqlite3; \
}

# install cjdns
RUN { \
	git clone --depth=1 https://github.com/cjdelisle/cjdns.git -b cjdns-v20 && \
	cd cjdns && ./do && install -m755 -oroot -groot cjdroute /usr/sbin/cjdroute && \
	rm -rf /cjdns && \
	echo $'#!/bin/bash \n\
if [ ! -f /etc/cjdroute.conf ]; then \n\
	cjdroute --genconf > /etc/cjdroute.conf \n\
fi \n\
cjdroute --nobg < /etc/cjdroute.conf >/var/log/cjdns.log 2>&1 \n\
' > /cjdns.sh && \
	chmod a+x /cjdns.sh; \
}

# install transitd and patch dependencies
COPY ./ /transitd/
RUN { \
	cd / && \
	patch -p0 /usr/local/share/lua/5.1/socket/http.lua /transitd/patches/luasocket-ipv6-fix.patch && \
	patch -p0 /usr/local/share/lua/5.1/cgilua/post.lua /transitd/patches/cgilua-content-type-fix.patch && \
	echo $'#!/bin/bash \n\
if [ ! -f /transitd/transitd.conf ]; then \n\
	 cp /transitd/transitd.conf.sample /transitd/transitd.conf; \n\
fi \n\
cd /transitd/src/; sleep 3; lua5.1 daemon.lua -f ../transitd.conf >/var/log/transitd.log 2>&1 \n\
' > /transitd.sh && \
	chmod a+x /transitd.sh && \
	echo $'#!/bin/bash \n\
cd /transitd/src/; lua5.1 cli.lua "$@" \n\
' > /usr/sbin/transitd-cli && \
	chmod a+x /usr/sbin/transitd-cli; \
}

# cleanup
RUN { \
	apt-get purge -y --auto-remove liblua5.1-0-dev build-essential luarocks git nodejs python linux-headers-generic unzip libsqlite3-dev; \
	apt-get autoremove; \
	apt-get clean; \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
}

# startup script
RUN { \
	echo $'#!/bin/bash \n\
transitd-cli --set \"`ip route|awk \'/default/ { print \"daemon.authorizedNetworks=127.0.0.1/8,::1/128,\" $3 }\'`\" \n\
/cjdns.sh & \n\
/transitd.sh & \n\
echo \"Web UI available at http://`hostname -i`:65533/\" \n\
echo \"# transitd-cli -h\" \n\
transitd-cli -h \n\
bash \n\
' > /start.sh && \
	chmod a+x /start.sh; \
}

CMD ["/start.sh"]
