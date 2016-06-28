
local config = require("config")

local rpc = require("json.rpc")
rpc.setTimeout(10)

local db = require("db")

require "alt_getopt"

local long_opts = {
   help = "h",
}

optarg,optind = alt_getopt.get_opts (arg, "hlc:s", long_opts)

if optarg.h or not (optarg.l or optarg.c or optarg.s) then
	print("Program arguments: \
	 -l      List available gateways \
	 -c ip   Connect to a gateway \
	 -s      Run a scanner to look for gateways \
	")
end

if optarg.l then
	local gateways, error = db.getRecentGateways()
	if gateways == nil then
		print(error)
	else
		for k,v in pairs (gateways) do
		   print(v.ip.."\t"..v.name)
		end
	end
end

if optarg.c then
	
	local ip = optarg.c
	
	local addr = "http://[" .. ip .. "]:" .. config.main.rpcport .. "/jsonrpc"
	local gateway = rpc.proxy(addr)
	
	local record = db.lookupGateway(ip)
	
	if record == nil then
		print("Checking " .. ip .. "...")
		local result, err = gateway.gatewayInfo()
		if err then
			print("Failed to connect to " .. ip .. ": " .. err)
		else
			if result.name and result.name then
				print("Gateway '" .. result.name .. "' at " .. ip)
				db.registerGateway(result.name, ip)
				record = db.lookupGateway(ip)
			end
		end
	end
	
	if record == nil then
		print("No mnigs at " .. ip)
		return
	end
	
	local scanner = require("cjdnstools.scanner")
	
	print("Connecting to gateway '" .. record.name .. "' at " .. record.ip)
	local mykey, err = scanner.getMyKey()
	if err then
		print("Failed to get my own IP: " .. err)
	else
		local result, err = gateway.requestConnection(config.main.name,"cjdns",{key=mykey})
		if err then
			print("Failed to register with " .. record.ip .. ": " .. err)
		elseif result.errorMsg then
			print("Failed to register with " .. record.ip .. ": " .. result.errorMsg)
		elseif result.success == false then
			print("Failed to register with " .. record.ip .. ": Unknown error")
		else
			print("Registered with " .. record.ip .. "!")
			if result.timeout then
			print("Timeout is " .. result.timeout .. " seconds")
			end
		end
	end
end

if optarg.s then
	require "scanner"
end
