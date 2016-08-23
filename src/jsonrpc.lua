
local threadman = require("threadman")

function jsonRpcWrapper()
	local rpcserver = require('json.rpcserver')
	local rpcInterface = require('rpc-interface')
	rpcserver.serve(rpcInterface.getInterface())
end

local coxpcall = require("coxpcall")
local result = {coxpcall.pcall(jsonRpcWrapper)}
if not result[1] then
	local err = result[2]
	threadman.notify({type="error", ["function"]='jsonRpcWrapper', ["error"]=err})
	threadman.notify({type="exit",retval=1})
end
