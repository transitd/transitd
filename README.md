![Transit Daemon](https://raw.githubusercontent.com/transitd/transitd/master/src/www/images/logo.transitd.png)

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

## Documentation

[Docker Installation](https://github.com/transitd/transitd/blob/master/docker/README.md)

[LEDE/OpenWrt Image Build Instructions](https://github.com/transitd/transitd/blob/master/lede/README.md)

[Local Installation](https://github.com/transitd/transitd/blob/master/INSTALL.md)

[Design](https://github.com/transitd/transitd/blob/master/docs/README.md)
