FROM alpine:3.3
MAINTAINER Alex <alex@maximum.guru>
RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories
RUN apk add --no-cache bash lua5.1 lua5.1-filesystem lua5.1-dev build-base luarocks5.1 git nodejs python linux-headers unzip sqlite-dev
RUN luarocks-5.1 install luasocket
RUN luarocks-5.1 install cgilua
RUN luarocks-5.1 install lua-cjson
RUN luarocks-5.1 install inifile
RUN luarocks-5.1 install xavante
RUN luarocks-5.1 install wsapi-xavante
RUN luarocks-5.1 install jsonrpc4lua
RUN luarocks-5.1 install sha2
RUN luarocks-5.1 install bencode
RUN luarocks-5.1 install dkjson
RUN luarocks-5.1 install bit32
RUN luarocks-5.1 install alt-getopt
RUN luarocks-5.1 install luaproc
RUN luarocks-5.1 install luasql-sqlite3
RUN git clone https://github.com/pdxmeshnet/mnigs.git
RUN git clone https://github.com/cjdelisle/cjdns.git
RUN patch -p0 /usr/share/lua/5.1/socket/http.lua /mnigs/patches/luasocket-ipv6-fix.patch
RUN patch -p0 /usr/share/lua/5.1/cgilua/post.lua /mnigs/patches/cgilua-content-type-fix.patch
RUN { cd /cjdns; ./do; install -m755 -oroot -groot cjdroute /usr/bin/cjdroute; }
RUN { cd /mnigs; cp mnigs.conf.sample mnigs.conf; }
RUN { echo "cjdroute --genconf > /etc/cjdroute.conf" > /start.sh; echo "cjdroute < /etc/cjdroute.conf" >> /start.sh; }
CMD bash -C '/start.sh';'bash'
