# Mesh Network Internet Gateway System
Mnigs is an automated Internet gateway publish, search and connect tool for mesh networks.  The goal of this package is to provide gateway owners the function to automatically advertise their gateway on the network and to provide users the automated Internet gateway search and connect function for their routers.

Emerging mesh networks make use of many different routing protocols.  These protocols may or may not be peering-compatible with the current Internet routing infrastructure.  Implementations of such networks may not necessarily want to have default routes (for Internet-bound traffic) or may not have network-wide default route.  Most access to the traditional Internet has recurring cost associated with it, which is incompatible with the idea of open community mesh networking.  In most cases, one cannot simply assume that access to such networks will grant them access to the traditional Internet.  There may be multiple available Internet gateways in a particular mesh network, some free of charge to use and some that may cost a fee.  In all cases, setting up connection to the traditional Internet through these community network gateways would be a manual process.  Mnigs makes the process of staying online through the mesh network automated.

Warning:  code in this repository is work in progress and currently not usable yet.

## Main Advantages
* Decentralized (uses routing tables to do breadth first search for mnigs servers)
* Supports multiple routing protocols
* Supports multiple connection methods
* Automatically registers with available servers and sets up WAN

## Server Component
* config file
  * JSON RPC ports
  * interfaces to run on and routing protocols to use
  * terms of access (max clients, etc)
* gateway server support
  * openvpn
  * softeather
  * cjdns gateway
  * simple forwarding configuration
  * other methods
* HTTP JSON RPC server
* JSON input/output

### Function
1. Set up external routing system(s): locally running VPN server software, etc.
2. Start JSON RPC server
  a. serve available connection details to clients
  b. allow clients to register/unregister with the server

## Client Component
* config file
  * JSON RPC ports
  * interfaces to scan and routing protocols to use
  * IP scan methods
  * connection methods
  * connection method specific configuration
* client support for all the connection methods supported by the server
* support traversing network for multiple routing protocols, including cjdns

## Function
  1. traverse the network to find nodes
  2. send JSON RPC client request to configured port(s) that servers run on
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
* jsonrpc4lua
* sha2
* bencode
* dkjson

## Installation
```
$ git clone git://github.com/pdxmeshnet/mnigs.git
$ git submodule update --init --recursive
```

## Configuration
```
$ cd mnigs
$ cp mnigs.conf.sample mnigs.conf
$ vi mings.conf
```

## Usage
```
$ lua server.lua
$ lua client.lua
```

### Run Server
```
$ cd src
$ lua server.lua
```

### Run Client
```
$ cd src
$ lua client.lua
```
