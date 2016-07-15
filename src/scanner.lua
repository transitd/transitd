
local config = require("config")

local rpc = require("rpc")

local scanner = require("cjdnstools.scanner")
local tunnel = require("cjdnstools.tunnel")

local db = require("db")

local callback = function(ip)
	print("Checking " .. ip .. "...")
	ports = {}
	for port in string.gmatch(config.daemon.scanports, "%d+") do 
		local port = tonumber(port)
		local gateway = rpc.getProxy(ip, port)
		local info, err = gateway.gatewayInfo()
		if err then
			print("Failed to connect to " .. ip .. ": " .. err)
		else
			if info.name and info.name then
				db.registerNode(info.name, ip, port)
				if info.methods then
					print("Gateway '" .. info.name .. "' at " .. ip .. ":" .. tostring(port) .. "!")
					for k, m in pairs(info.methods) do
						-- register methods
						if m and m.name then
							db.registerGateway(info.name, ip, port, m.name)
						end
					end
				else
					print("Node '" .. info.name .. "' at " .. ip .. ":" .. tostring(port) .. "!")
				end
			end
		end
	end
end

scanner.scan(callback)
