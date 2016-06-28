--- @module rpc-interface.cjdns
local cjdns = {}

local config = require("config")
local gateway = require("gateway")
local db = require("db")
local cjdnsTunnel = require("cjdnstools.tunnel")

local rpc = require("json.rpc")
rpc.setTimeout(10)


function cjdns.requestConnection(name, method, options)
	
	local subscriberip = cgilua.servervariable("REMOTE_ADDR")
	
	if options.key == nil then
		return { success = false, errorMsg = "Key option is required" }
	end
	
	-- come up with random ips based on settings in config
	ipv4, error4 = gateway.allocateIpv4();
	ipv6, error5 = gateway.allocateIpv6();
	if error4 ~= nil and error6 ~= nil then
		if error4 ~= nil then
			return { success = false, errorMsg = error4 }
		end
		if error6 ~= nil then
			return { success = false, errorMsg = error6 }
		end
	end
	
	local sid, error = gateway.allocateSid()
	if error ~= nil then
		return { success = false, errorMsg = error, temporaryError = true }
	end
	
	local response, err = cjdnsTunnel.addKey(options.key, ipv4, ipv6)
	if err then
		return { success = false, errorMsg = "Error adding cjdns key at gateway: " .. err }
	else
		
		db.registerSubscriber(sid, name, method, subscriberip, nil, ipv4, ipv6)
		db.registerCjdnsSubscriber(sid, options.key)
		
		return { success = true, timeout = config.gateway.subscriberTimeout, ['ipv4'] = ivp4, ['ipv6'] = ipv6 }
	end
	
end

function cjdns.renewConnection(sid)
	
	return true, nil
end

function cjdns.releaseConnection(sid)
	if sid then
		local key, error = db.getCjdnsClientKey(sid)
		if error then
			return { success = false, errorMsg = "Error releasing connection: " .. err }
		else
			local response, err = cjdnsTunnel.deauthorizeKey(key)
			if err then
				return { success = false, errorMsg = "Error releasing connection: " .. err }
			else
				return { success = true }
			end
		end
	else
		return { success = false, errorMsg = "'sid' option is invalid" }
	end
end

function cjdns.connectTo(ip, method)
	
	local addr = "http://[" .. ip .. "]:" .. config.main.rpcport .. "/jsonrpc"
	local gateway = rpc.proxy(addr)
	
	local record = db.lookupGateway(ip)
	
	if record == nil then
		print("Checking " .. ip .. "...")
		local result, err = gateway.gatewayInfo()
		if err then
			return {success = false, errorMsg = "Failed to connect to " .. ip .. ": " .. err}
		else
			if result.name and result.name then
				print("Gateway '" .. result.name .. "' at " .. ip)
				db.registerGateway(result.name, ip)
				record = db.lookupGateway(ip)
			end
		end
	end
	
	if record == nil then
		return {success = false, errorMsg = "No mnigs at " .. ip}
	end
	
	print("Connecting to gateway '" .. record.name .. "' at " .. record.ip)
	
	local scanner = require("cjdnstools.scanner")
	local mykey, err = scanner.getMyKey()
	if err then
		return {success = false, errorMsg = "Failed to get my own IP: " .. err}
	else
		local result, err = gateway.requestConnection(config.main.name,"cjdns",{key=mykey})
		if err then
			return {success = false, errorMsg = err}
		elseif result.errorMsg then
			return {success = false, errorMsg = result.errorMsg}
		elseif result.success == false then
			return {success = false, errorMsg = "Unknown error"}
		else
			print("Registered with " .. record.ip .. "!")
			if result.timeout then
				print("Timeout is " .. result.timeout .. " seconds")
			end
			return {success = true, info = result}
		end
	end
end

return cjdns
