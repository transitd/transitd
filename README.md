# Mesh Network Internet Gateway System
Mnigs is an automated Internet gateway publish, search and connect tool for mesh networks.  The goal of this package is to provide gateway owners the function to automatically advertise their gateway on the network and to provide users the automated Internet gateway search and connect function for their routers.

Emerging mesh networks make use of many different routing protocols.  These protocols may or may not be peering-compatible with the current Internet routing infrastructure.  Implementations of such networks may not necessarily want to have default routes (for Internet-bound traffic) or may not have network-wide default route.  Most access to the traditional Internet has recurring cost associated with it, which is incompatible with the idea of open community mesh networking.  In most cases, one cannot simply assume that access to such networks will grant them access to the traditional Internet.  There may be multiple available Internet gateways in a particular mesh network, some free of charge to use and some that may cost a fee.  In all cases, setting up connection to the traditional Internet through these community network gateways would be a manual process.  Mnigs makes the process of staying online through the mesh network automated.

Warning:  code in this repository is work in progress and currently not usable, feel free to contribute.

## Main Advantages
* Decentralized (uses routing tables to do breadth first search for mnigs servers)
* Supports multiple routing protocols
* Supports multiple connection methods
* Automatically registers with available servers and sets up WAN

## Gateway Component
* config file
  * JSON RPC ports
  * interfaces to run on and routing protocols to use
  * terms of access (max subscribers, etc)
* gateway server support
  * openvpn/softether
  * ipip/gre
  * cjdns gateway
  * simple default gateway configuration (in Layer 2 networks)
  * tun2socks?
  * other methods
* HTTP JSON RPC server
* JSON input/output

### Function
1. set up external routing system(s): locally running VPN server software, etc.
2. start JSON RPC server
  a. serve available connection details to subscribers
  b. allow subscribers to register/unregister with the server

## Subscriber Component
* config file
  * JSON RPC ports
  * interfaces to scan and routing protocols to use
  * IP scan methods
  * connection methods
  * connection method specific configuration
* subscriber support for all the connection methods supported by the server
* support traversing network for multiple routing protocols, including cjdns

### Function
  1. traverse the network to find nodes
  2. send JSON RPC request to configured port(s) that servers run on
  3. register with the server over JSON RPC if connection is possible
  4. set up connection with the appropriate method, retry with different methods on failure
  5. detect downtime and search for another server, track connection quality of servers

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
* lua-llthreads2

This fix is required to allow CGILua to accept JSON-RPC content type: https://github.com/pdxmeshnet/cgilua/commit/1b35d812c7d637b91f2ac0a8d91f9698ba84d8d9.patch
(see https://github.com/keplerproject/cgilua/pull/9)

This fix is required to allow JSON RPC requests to work with IPv6: https://github.com/darklajid/luasocket/commit/4785d9e6fcf107721602afbc61352475d56f921a.patch
(see https://github.com/diegonehab/luasocket/pull/91)

## Installation
```
$ git clone git://github.com/pdxmeshnet/mnigs.git
$ cd mnigs
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
$ sudo luarocks install lua-llthreads2
$ sudo apt-get install libsqlite3-dev
$ sudo luarocks install luasql-sqlite3
$ sudo patch /path/to/.../cgilua/post.lua < 1b35d812c7d637b91f2ac0a8d91f9698ba84d8d9.patch
```
Then, either,
```
$ sudo patch /path/to/.../socket/http.lua < 4785d9e6fcf107721602afbc61352475d56f921a.patch
```
OR
```
$ sudo luarocks install https://raw.githubusercontent.com/diegonehab/luasocket/master/luasocket-scm-0.rockspec
```
If you are using --local flag with luarocks, make sure you have ``` eval `luarocks path` ``` in your .bashrc file.

## Configuration
```
$ cd mnigs
$ cp mnigs.conf.sample mnigs.conf
$ vi mings.conf
```

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
