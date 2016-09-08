# Transit Daemon (transitd)
Transit Daemon is an automated Internet gateway publish, search and connect tool for community networks.

The goal of this package is to provide to gateway operators the ability to automatically run and advertise their Internet gateway / VPN on a community network and to provide to subscribers the automated gateway search and connect functionality.

Emerging community mesh networks seek to provide free and open access to a network built by its users.  Implementations of such networks may not necessarily povide transit to the rest of the Internet.  Access to the traditional Internet has a recurring cost (paid to transit providers), which someone has to pay.  In the case where someone does pay for it, service type/quality may not suit all users.  This makes Internet access incompatible with the open/free nature of community networks.  In most cases, one cannot simply assume that access to such networks will grant them access to the traditional Internet.  There may be multiple available Internet gateways on a particular community network, some free of charge to use and some that may come at a cost.  In all cases, setting up connection to the traditional Internet through community network gateways is a manual process.  Transitd makes the process of getting and having Internet access via a community network easy.

### Warning:  code in this repository is work in progress and currently not usable, feel free to contribute.

## Main Advantages
Although it is possible for community network users to set up Internet connectivity on their networks manually, using this package has a number of advantages.
* Quick and efficient to use
* Installs on routers
* No network administration knowledge needed
* Decentralized (uses routing protocol facilities to do breadth first search for gateways)
* Provides a selection of multiple gateways on a single network
* Supports multiple routing protocols / network configurations
* Supports multiple connection methods / tunneling configurations
* Supports payments

### Network configuration support
* cjdns
* babel <sup>to be implemented</sup>
* batman-adv <sup>to be implemented</sup>
* olsr <sup>to be implemented</sup>
* layer 2 networks <sup>to be implemented</sup>

### Tunneling configuration support
* cjdns tunneling
* openvpn/softether <sup>to be implemented</sup>
* tinc <sup>to be implemented</sup>
* ipip/gre <sup>to be implemented</sup>
* tun2socks? <sup>to be implemented</sup>
* layer 2 forwarding <sup>to be implemented</sup>

### Payment method support
* free
* cryptocurrency microtransactions <sup>to be implemented</sup>
* commercial payment processor + vpn service provider <sup>to be implemented</sup>

## Gateway functions
1. participate in general node interactions (scan network, bootstrap DHT, etc)
2. set up locally running VPN software
3. serve configuration details to subscribers
4. allow subscribers to register/unregister and tunnel through to the Internet

## Subscriber functions
1. participate in general node interactions (scan network, bootstrap DHT, etc)
2. allow local authorized users to list, test and register with gateways
3. set up local network configuration for tunneling through gateways
4. detect downtime and automatically switch between gateways, track connection quality of servers

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

A fix is required to allow CGILua to accept JSON-RPC content type (see https://github.com/keplerproject/cgilua/pull/9).  The fix has been merged into CGILua master branch, however, no stable release is available as of this writing.

A fix is required to allow JSON RPC requests to work with IPv6 (see https://github.com/diegonehab/luasocket/pull/91).  A more permanent fix has been merged into luasocket master branch, however, no stable release is available as of this writing.

## Installation

### Docker Installation
```
$ git clone --depth=1 git://github.com/intermesh-networks/transitd.git
$ cd transitd
$ docker build -t "transitd:0" .
```
### Gateway
```
$ docker run -it --privileged --name=transitd-gateway transitd:0
# transitd-cli --set gateway.enabled=yes
# exit
$ docker start -ai transitd-gateway
# apt-get update
# apt-get install tcpdump
# tcpdump -i tun0
```
### Subscriber
```
$ docker run -it --privileged --name=transitd-sub transitd:0
# transitd-cli -s
# transitd-cli -l
# transitd-cli -c ....
# ip route show
# ping 8.8.8.8
```
### Web UI
You can access `http://172.17.0.???:65533/` from your browser (where the IP address is the docker container instance address).

### Manual Installation
```
$ git clone --depth=1 git://github.com/intermesh-networks/transitd.git
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

## Configuration
```
$ cd transitd
$ cp transitd.conf.sample transitd.conf
$ vi transitd.conf
```
Add path to your cjdroute.conf config file in the [cjdns] section.

## Usage

### Run daemon
```
$ cd src
$ lua daemon.lua
```

### Run command line interface
```
$ cd src
$ lua cli.lua
```

### Web UI
You can access `http://localhost:65533` from your browser.

## Demo usage on a single host with CJDNS
In order to demo the system, you actually need 2 different machines.  You can avoid this by using 2 different config files running transitd on different ports and different database file.

### Start daemon 1
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

### Start daemon 2
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

### Trigger network scan
```
$ cd src
$ lua cli.lua -f ../transitd2.conf -s
```

### Trigger connection
```
$ cd src
$ lua cli.lua -f ../transitd2.conf -c <YOUR CJDNS IP> -p 65533
```

## Design
Each node runs a daemon.  The daemon sends and receives messages over HTTP JSON RPC interface.  The web UI is also available over HTTP.  Subscribers can request connections with gateways.  Connection sessions have a short lifetime and need to be renewed.  The daemon manages networking configuration on both ends, which can be adjusted in the configuration file.
Knowledge of available gateways on a network is gained by occasionally scanning the network and adding the new information into the DHT.

![Design](docs/design.png?raw=true)

### HTTP JSON RPC API

All interactions with the daemon and between daemon instances are done through HTTP JSON RPC API.

(incomplete)

The following RPC functions are available.

- nodeInfo()
- requestConnection(sid, name, port, method, options)
- renewConnection(sid)
- releaseConnection(sid)

In case of success, the following object is returned,
```
{ success: true, .... }
```

In case of error, the following object is returned,
```
{ success: false, errorMsg: "...." }
```
