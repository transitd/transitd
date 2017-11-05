# Design
Each node runs a daemon.  The daemon sends and receives messages over HTTP JSON RPC interface.  The web UI is also available over HTTP.  Subscribers can request connections with gateways.  Connection sessions have a short lifetime and need to be renewed.  The daemon manages networking configuration on both ends, which can be adjusted in the configuration file.
Knowledge of available gateways on a network is gained by occasionally scanning the network and adding the new information into the DHT.

![Design](https://raw.githubusercontent.com/transitd/transitd/master/docs/design.png)

## HTTP JSON RPC API

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
