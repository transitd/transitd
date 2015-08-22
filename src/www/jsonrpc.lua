
local rpcserver = require('json.rpcserver')
local lfs = require('lfs')
lfs.chdir("..")
local rpcInterface = require('rpc-interface')
rpcserver.serve(rpcInterface)
