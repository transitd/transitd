![Transit Daemon](src/www/images/logo.transitd.png?raw=true)

# Transit Daemon
Transit Daemon is an automated Internet gateway publishing tool for community networks.

The goal of this application is to provide to gateway operators the ability to automatically run and advertise their Internet gateway / VPN on a community network and to provide to subscribers the automated gateway search and connect functionality.

Emerging community mesh networks seek to provide free and open access to a network built by its users.  Implementations of such networks may not necessarily povide transit to the rest of the Internet.  Access to the traditional Internet has a recurring cost (paid to transit providers), which someone has to pay.  In the case where someone does pay for it, service type/quality may not be suitable to all users.  This makes Internet access incompatible with the open/free nature of community networks.  In most cases, one cannot simply assume that access to such networks will grant them access to the traditional Internet.  There may be multiple available Internet gateways on a particular community network, some may be free to use and some may have a fee.  In all cases, setting up connection to the traditional Internet through community network gateways is a manual process.

Transit Daemon simplifies the process of arranging Internet access via a community network.

### Warning:  code in this repository is work in progress

## How It Works

Transit Daemon has the following parts,

1. Daemon process
2. Web UI
3. CLI tool

The daemon process has the following parts,

1. Web server that hosts the Web UI and HTTP JSON-RPC interface
2. Scanner that searches the detected networks to find other hosts running transitd
3. Connection manager that manages connections/tunnels
3. Network support modules *(only cjdns module currently implemented)*
4. Tunnel support modules *(only ipip module currently functional)*
5. Payment support modules *(only free module currently implemented)*
6. DHT that keeps data about gateways on the network *(to be implemented)*

The CLI tool, Web UI, and other hosts communicate with the daemon through the HTTP JSON-RPC interface.  The network support modules interface with locally running routing software.  The tunnel support modules interface with the locally installed VPN software.  The payment support modules interface with payment processing infrastructure available on the Internet.

### Network support
* cjdns
* batman-adv *(to be implemented)*
* bmx6/7 *(to be implemented)*
* olsr/2 *(to be implemented)*
* babel *(to be implemented)*
* layer 2 networks *(to be implemented)*

### Tunnel support
* cjdns tunnels
* ipip
* gre *(to be implemented)*
* openvpn *(to be implemented)*
* softether *(to be implemented)*
* fastd *(to be implemented)*
* wireguard *(to be implemented)*
* tinc *(to be implemented)*
* tun2socks *(to be implemented)*
* pptp *(to be implemented)*
* IPSec *(to be implemented)*
* l2tp *(to be implemented)*

### Payment method support
* free
* cryptocurrency microtransactions *(to be implemented)*
* commercial payment processors *(to be implemented)*

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
* lua-copas

A fix is required to allow CGILua to accept JSON-RPC content type (see https://github.com/keplerproject/cgilua/pull/9).  The fix has been merged into CGILua master branch, however, no stable release is available as of this writing.

A fix is required to allow JSON RPC requests to work with IPv6 (see https://github.com/diegonehab/luasocket/pull/91).  A more permanent fix has been merged into luasocket master branch, however, no stable release is available as of this writing.

## Docker Installation

### Using Docker Compose
```
$ git clone --depth=1 git://github.com/transitd/transitd.git
$ cd transitd
$ docker-compose up
```
### Building the Docker Image Manually
```
$ git clone --depth=1 git://github.com/transitd/transitd.git
$ cd transitd
$ docker build -t transitd .
```
### Running a Gateway & Subscriber Test
```
$ docker run -it --cap-add=NET_ADMIN --device=/dev/net/tun --name=transitd-gateway transitd ./start.gateway.cli.sh
# apt-get update
# apt-get install tcpdump
# tcpdump -i tun0
```
```
$ docker run -it --cap-add=NET_ADMIN --device=/dev/net/tun --name=transitd-sub transitd ./start.cli.sh
# transitd-cli -s
# transitd-cli -l
# transitd-cli -c <ip> -m <suite>
# ip route show
# ping 8.8.8.8
```
### Using the Web UI
You can access `http://172.17.0.???:65533/` from your browser (where the IP address is the docker container instance address).

## Local Installation
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
