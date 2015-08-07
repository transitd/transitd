
local rpcserver = require('json.rpcserver')
package.path = package.path .. ";../?.lua"
local rpcInterface = require('rpc-interface')
rpcserver.serve(rpcInterface)
