
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
	local con = _G.config
	local tokens = {}
	for token in string.gmatch(setting, "%w+") do table.insert(tokens, token) end
	for num,section in pairs(tokens) do
		if not con[section] then
			error("Invalid configuration token '"..section.."'")
		else
			if type(con[section]) ~= "table" then
				if num ~= #tokens then
					error("Configuration token '"..section.."' does not have subelements")
				end
				con[section] = value
				save_config()
			else
				if num == #tokens then
					error("Configuration token '"..section.."' cannot have a value")
				else
					con = con[section]
				end
			end
		end
	end
end

if optarg.c then
	
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
			print("Timeout: " .. result.timeout)
			if result.ipv4 then
				print("IPv4: " .. result.ipv4)
			end
			if result.ipv6 then
				print("IPv6: " .. result.ipv6)
			end
		end
	end
end

if optarg.s then
	require "scanner"
end
