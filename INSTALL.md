# Installation on a Local System

## Dependencies
* lua >= 5.1
* luasocket
* cgilua
* lua-cjson
* inifile
* xavante
* wsapi-xavante
* jsonrpc4lua
* sha2
* bencode
* dkjson (cjdns lua library code dependency)
* bit32
* luasql-sqlite3
* alt-getopt
* luaproc
* coxpcall
* lua-copas

A fix is required to allow CGILua to accept JSON-RPC content type (see https://github.com/keplerproject/cgilua/pull/9).  The fix has been merged into CGILua master branch, however, no stable release is available as of this writing.

A fix is required to allow JSON RPC requests to work with IPv6 (see https://github.com/diegonehab/luasocket/pull/91).  A more permanent fix has been merged into luasocket master branch, however, no stable release is available as of this writing.

## Installation

```
$ git clone --depth=1 git://github.com/transitd/transitd.git
$ cd transitd
$ sudo luarocks install cgilua
$ sudo luarocks install lua-cjson
$ sudo luarocks install inifile
$ sudo luarocks install xavante
$ sudo luarocks install wsapi-xavante
$ sudo luarocks install jsonrpc4lua
$ sudo luarocks install sha2
$ sudo luarocks install bencode
$ sudo luarocks install dkjson
$ sudo luarocks install bit32
$ sudo luarocks install alt-getopt
$ sudo luarocks install luaproc
$ sudo luarocks install coxpcall
$ sudo apt-get install libsqlite3-dev
$ sudo luarocks install luasql-sqlite3
$ sudo patch -p0 /usr/share/lua/5.1/cgilua/post.lua patches/cgilua-content-type-fix.patch
```
Then, either,
```
$ sudo patch -p0 /usr/share/lua/5.1/socket/http.lua patches/luasocket-ipv6-fix.patch
```
OR (unstable luasocket version)
```
$ sudo luarocks install https://raw.githubusercontent.com/diegonehab/luasocket/master/luasocket-scm-0.rockspec
```
If you are using --local flag with luarocks, make sure you have ``` eval `luarocks path` ``` in your .bashrc file.

### Configuration
```
$ cd transitd
$ cp transitd.conf.sample transitd.conf
$ vi transitd.conf
```
Add path to your cjdroute.conf config file in the [cjdns] section.

### Runing Local Daemon
```
$ cd src
$ lua daemon.lua
```

### Using CLI
```
$ cd src
$ lua cli.lua
```

### Using the Web UI
You can access `http://localhost:65533` from your browser.

## Demo Usage on a Single Host with CJDNS
In order to demo the system, you actually need 2 different machines.  You can avoid this by using 2 different config files running transitd on different ports and different database file.

### Running Gateway & Subscriber Test
```
$ cd transitd
$ cp transitd.conf.sample transitd1.conf
$ cd src
$ lua cli.lua -f ../transitd1.conf --set cjdns.config=<path/to/cjdroute.conf>
$ lua cli.lua -f ../transitd1.conf --set daemon.rpcport=65533
$ lua cli.lua -f ../transitd1.conf --set daemon.scanports=65533,65534
$ lua cli.lua -f ../transitd1.conf --set gateway.enabled=yes
$ lua cli.lua -f ../transitd1.conf --set database.file=transitd1.db
$ lua daemon.lua -f ../transitd1.conf
```
```
$ cd transitd
$ cp transitd.conf.sample transitd2.conf
$ cd src
$ lua cli.lua -f ../transitd2.conf --set cjdns.config=<path/to/cjdroute.conf>
$ lua cli.lua -f ../transitd2.conf --set daemon.rpcport=65534
$ lua cli.lua -f ../transitd2.conf --set daemon.scanports=65533,65534
$ lua cli.lua -f ../transitd2.conf --set gateway.enabled=no
$ lua cli.lua -f ../transitd2.conf --set database.file=transitd2.db
$ lua daemon.lua -f ../transitd2.conf
```

### Trigger a Network Scan
```
$ cd src
$ lua cli.lua -f ../transitd2.conf -s
```

### Trigger a Connection
```
$ cd src
$ lua cli.lua -f ../transitd2.conf -c <YOUR CJDNS IP> -m cjdns-cjdns-free -p 65533
```
