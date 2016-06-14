--- @module rpc-interface.cjdns
local cjdns = {}

local config = require("config")
local gateway = require("gateway")
local db = require("db")
local cjdnsTunnel = require("cjdnstools.tunnel")

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
		
		db.registerClient(sid, name, method, subscriberip, nil, ipv4, ipv6)
		db.registerCjdnsClient(sid, options.key)
		
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

function cjdns.connectTo(ip)
	
	return nil, "unimplemented"
end

return cjdns
