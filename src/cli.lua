--[[

transitd CLI main file

@file cli.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex

--]]

local socket = require("socket")

local config = require("config")
local db = require("db")
local rpc = require("rpc")
local network = require("network")

local options = require("options")
local optarg = options.getArguments()

if optarg.l then
	local gateways, error = db.getRecentGateways()
	if gateways == nil then
		print(error)
	else
		for k,v in pairs (gateways) do
		   print(v.name.." ( "..v.ip.." port "..v.port.." ) {suite:"..v.suite.."}")
		end
	end
end

if optarg.n then
	local data = optarg.n
	local setting = string.sub(data, 1, string.find(data,"=")-1)
	local value = string.sub(data, string.find(data,"=")+1)
	local result, err = set_config(setting, value)
	if err then
		print(err)
		os.exit(1)
	else
		save_config()
	end
end

if optarg.c then
	
	if config.gateway.enabled == "yes" then
		error("Cannot use connect functionality in gateway mode")
	end
	
	local ip = optarg.c
	local ip, err = network.canonicalizeIp(ip)
	if err then error(err) end
	
	local daemon = rpc.getProxy("127.0.0.1", config.daemon.rpcport)
	
	local port = config.daemon.rpcport
	
	if optarg.p then
		port = tonumber(optarg.p)
	end
	
	if not optarg.m then
		error("Suite must be specified")
	end
	
	local suite = optarg.m
	
	local result, err = daemon.connect(ip, port, suite)
	if err then
		print("Failed: " .. err)
	else
		if result.success ~= true then
			print("Failed: " .. result.errorMsg)
		else
			print("Registered with " .. ip .. " port " .. port .. "!")
			if result.ipv4             then print("IPv4:" .. result.ipv4)                        end
			if result.ipv4gateway      then print("IPv4 gateway:" .. result.ipv4gateway)         end
			if result.ipv6             then print("IPv6:" .. result.ipv6)                        end
			if result.ipv6gateway      then print("IPv6 gateway:" .. result.ipv6gateway)         end
			if result.timeoutTimestamp then print("Timeout is in " .. (result.timeoutTimestamp - result.registerTimestamp) .. " seconds") end
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
	
	local result, err = daemon.disconnect(session.sid)
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
	
	local daemon = rpc.getProxy("127.0.0.1", config.daemon.rpcport)
	
	local result, err = daemon.startScan()
	if err then
		error(err)
	else
		if result.success ~= true then
			print("Failed: " .. result.errorMsg)
		else
			print("Scan started successfully.")
		end
	end
	
end
