
local config = require("config")

local rpc = require("json.rpc")
rpc.setTimeout(5)

local scanner = require("cjdnstools.scanner")
local tunnel = require("cjdnstools.tunnel")

local db = require("db")

local callback = function(ip)
	local addr = "http://[" .. ip .. "]:" .. config.main.rpcport .. "/jsonrpc"
	print("Checking " .. ip .. "...")
	local server = rpc.proxy(addr)
	local result, err = server.gatewayInfo()
	if err then
		print("Failed to connect to " .. ip .. ": " .. err)
	else
		if result.name and result.name then
			print("Server '" .. result.name .. "' at " .. ip)
			db.registerGateway(result.name, ip)
		end
	end
end

scanner.scan(callback)
