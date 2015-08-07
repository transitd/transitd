
local config = require("config")

local rpc = require("json.rpc")
local cjson_safe = require("cjson.safe")

local availableGateways = {}
local checkNodes = {}

local scanner = require("cjdnstools.scanner")

local callback = function(ip)
	local addr = "http://[" .. ip .. "]:" .. config.server.rpcport .. "/jsonrpc"
	print("Checking " .. addr .. "...")
  local server = rpc.proxy(addr)
  local result, err = server.gatewayInfo()
  if err then
    print(err)
  else
    print("Found server! " .. cjson_safe.encode(result))
		availableGateways[ip] = ip
  end
end

scanner.scan(callback)
