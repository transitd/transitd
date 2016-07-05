
local luaproc = require("luaproc")

local lfs = require('lfs')
lfs.chdir("..")

local rpcserver = require('json.rpcserver')
local rpcInterface = require('rpc-interface')
rpcserver.serve(rpcInterface)
