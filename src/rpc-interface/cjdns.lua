--- @module rpc-interface.cjdns
local cjdns = {}

local config = require("config")
local gateway = require("gateway")
local db = require("db")
local cjdnsTunnel = require("cjdnstools.tunnel")
local threadman = require("threadman")
local rpc = require("rpc")

function cjdns.requestConnection(sid, name, port, method, options)
	
	local port = tonumber(port)
	local subscriberip = tostring(cgilua.servervariable("REMOTE_ADDR"))
	
	if options.key == nil then
		return { success = false, errorMsg = "Key option is required" }
	end
	
	local key = tostring(options.key)
	
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
	
	local sid, error = gateway.allocateSid(sid)
	if error ~= nil then
		return { success = false, errorMsg = error, temporaryError = true }
	end
	
	local response, err = cjdnsTunnel.addKey(key, ipv4, ipv6)
	if err then
		return { success = false, errorMsg = "Error adding cjdns key at gateway: " .. err }
	else
		
		local timeout = config.gateway.subscriberTimeout
		
		db.registerSubscriberSession(sid, name, method, subscriberip, port, ipv4, ipv6, timeout)
		db.registerSubscriberSessionCjdnsKey(sid, key)
		
		threadman.notify({type = "subscriber.auth", ["sid"] = sid, cjdnskey = key})
		
		return { success = true, ['timeout'] = timeout, ['ipv4'] = ipv4, ['ipv6'] = ipv6 }
	end
	
end

function cjdns.renewConnection(sid)
	-- nothing needs to be done
	return true, nil
end

function cjdns.releaseConnection(sid)
	if sid then
		local key, err = db.getCjdnsSubscriberKey(sid)
		if err then
			threadman.notify({type = "subscriber.deauth.fail", ["sid"] = sid, method = "cjdns", cjdnskey = key, error = err})
			return { success = false, errorMsg = "Error releasing connection: " .. err }
		else
			local response, err = cjdnsTunnel.deauthorizeKey(key)
			if err then
				threadman.notify({type = "subscriber.deauth.fail", ["sid"] = sid, method = "cjdns", cjdnskey = key, error = err})
				return { success = false, errorMsg = "Error releasing connection: " .. err }
			else
				db.deactivateSession(subscriber.sid)
				threadman.notify({type = "subscriber.deauth", ["sid"] = sid, method = "cjdns", cjdnskey = key})
				return { success = true }
			end
		end
	else
		local err = "'sid' option is invalid"
		threadman.notify({type = "subscriber.deauth.fail", ["sid"] = sid, method = "cjdns", error = err})
		return { success = false, errorMsg = err }
	end
end

function cjdns.connectTo(ip, port, method, sid)
	
	sid = sid or gateway.allocateSid()
	
	local node = rpc.getProxy(ip, port)
	
	local scanner = require("cjdnstools.scanner")
	local mykey, err = scanner.getMyKey()
	if err then
		return {success = false, errorMsg = "Failed to get my own IP: " .. err}
	else
		local result, err = node.requestConnection(sid, config.main.name, config.daemon.rpcport, "cjdns", {key = mykey})
		if err then
			return {success = false, errorMsg = err}
		elseif result.errorMsg then
			return {success = false, errorMsg = result.errorMsg}
		elseif result.success == false then
			return {success = false, errorMsg = "Unknown error"}
		else
			return result
		end
	end
end

return cjdns
