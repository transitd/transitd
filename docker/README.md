# Docker Installation

## Using Docker Compose
```
$ git clone --depth=1 git://github.com/transitd/transitd.git
$ cd transitd
$ docker-compose up
```
## Building the Docker Image Manually
```
$ git clone --depth=1 git://github.com/transitd/transitd.git
$ cd transitd
$ docker build -t transitd .
```
## Running a Gateway & Subscriber Test
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
## Using the Web UI
You can access `http://172.17.0.???:65533/` from your browser (where the IP address is the docker container instance address).
