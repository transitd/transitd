
local socket = require("socket")

local config = require("config")
local db = require("db")
local rpc = require("rpc")

local options = require("options")
local optarg = options.getArguments()

if optarg.l then
	local gateways, error = db.getRecentGateways()
	if gateways == nil then
		print(error)
	else
		for k,v in pairs (gateways) do
		   print(v.name.." ( "..v.ip.." port "..v.port.." ) {method:"..v.method.."}")
		end
	end
end

if optarg.n then
	local data = optarg.n
	local setting = string.sub(data, 1, string.find(data,"=")-1)
	local value = string.sub(data, string.find(data,"=")+1)
	set_config(setting, value)
	save_config()
end

if optarg.c then
	
	if config.gateway.enabled == "yes" then
		error("Cannot use connect functionality in gateway mode")
	end
	
	local ip = optarg.c
	
	local daemon = rpc.getProxy("127.0.0.1", config.daemon.rpcport)
	
	local port = config.daemon.rpcport
	
	if optarg.p then
		port = tonumber(optarg.p)
	end
	
	local result, err = daemon.connectTo(ip, port, "cjdns")
	if err then
		print("Failed: " .. err)
	else
		if result.success ~= true then
			print("Failed: " .. result.errorMsg)
		else
			print("Registered with " .. ip .. " port " .. port .. "!")
			if result.ipv4        then print("IPv4:" .. result.ipv4)                        end
			if result.ipv4gateway then print("IPv4 gateway:" .. result.ipv4gateway)         end
			if result.ipv6        then print("IPv6:" .. result.ipv6)                        end
			if result.ipv6gateway then print("IPv6 gateway:" .. result.ipv6gateway)         end
			if result.dns         then print("IPv6 DNS:" .. result.dns)                     end
			if result.timeout     then print("Timeout is " .. result.timeout .. " seconds") end
		end
	end
end

if optarg.d then
	
	if config.gateway.enabled == "yes" then
		error("Cannot use connect functionality in gateway mode")
	end
	
	local daemon = rpc.getProxy("127.0.0.1", config.daemon.rpcport)
	
	local sessions, err = db.getActiveSessions()
	if err then
		error(err)
	end
	
	if #sessions < 1 then
		error("No active sessions")
	end
	
	local session = sessions[1]
	
	local result, err = daemon.disconnect(session)
	if err then
		error(err)
	else
		if result.success ~= true then
			print("Failed: " .. result.errorMsg)
		else
			print("Disconnected.")
		end
	end
end

if optarg.s then
	require "scanner"
end
