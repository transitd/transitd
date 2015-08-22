
local config = require("config")

local rpc = require("json.rpc")

rpc.setTimeout(5)

local cjson_safe = require("cjson.safe")

local availableGateways = {}
local checkNodes = {}

local scanner = require("cjdnstools.scanner")
local tunnel = require("cjdnstools.tunnel")

local callback = function(ip)
	local addr = "http://[" .. ip .. "]:" .. config.server.rpcport .. "/jsonrpc"
	print("Checking " .. addr .. "...")
	local server = rpc.proxy(addr)
	local result, err = server.gatewayInfo()
	if err then
		print("Failed to connect to " .. addr .. ": " .. err)
	else
		if result.name and result.name then
			print("Server '" .. result.name .. "' at " .. ip)
			availableGateways[ip] = ip
			local mykey, err = scanner.getMyKey()
			if err then
				print("Failed to get my own IP: " .. err)
			else
				local result, err = server.requestConnection("cjdns",{key=mykey})
				if err then
					print("Failed to register with " .. addr .. ": " .. err)
				elseif result.errorMsg then
					print("Failed to register with " .. addr .. ": " .. result.errorMsg)
				else
					print("Registered with " .. addr .. "!")
					if result.timeout then
					print("Timeout is " .. result.timeout .. " seconds")
					end
				end
			end
		end
	end
end

scanner.scan(callback)
