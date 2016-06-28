
local config = require("config")
local socket = require("socket")
local db = require("db")
local cjdns = require("rpc-interface.cjdns")

-- need better random numbers
math.randomseed(socket.gettime()*1000)

local interface = {
	echo = function (msg) return msg end,
	
	gatewayInfo = function()
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		local methods = {}
		
		if config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			methods[#methods+1] = {name = "cjdns"}
		end
		
		return { name = config.main.name, ['methods'] = methods }
	end,
	
	requestConnection = function(name, method, options)
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		-- TODO: check to make sure they are connecting over allowed network
		
		-- check maxclients config to make sure we are not registering more clients than needed
		local activeSubscribers = db.getActiveSubscribers()
		if #activeSubscribers > config.gateway.maxConnections then
			return { success = false, errorMsg = "Too many subscribers", temporaryError = true }
		end
		
		local subscriberip = cgilua.servervariable("REMOTE_ADDR")
		
		-- check to make sure the user isn't already registered
		local activeClient = db.lookupActiveClientByIp(subscriberip)
		if activeClient ~= nil then
			if activeClient.method ~= method then
				return { success = false, errorMsg = "User is already registered with a different method", temporaryError = true }
			else
				local timestamp = os.time()
				return { success = true, timeout = activeClient.timeout_timestamp - timestamp, ['ipv4'] = activeClient.internetIPv4, ['ipv6'] = activeClient.internetIPv6 }
			end
		end
		
		if method == "cjdns" and config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			return cjdns.requestConnection(name, method, options)
		end
		
		return { success = false, errorMsg = "Method not supported" }
	end,

	renewConnection = function(sid)
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		if method == "cjdns" and config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			return cjdns.renewConnection(sid)
		end
		
		return { success = false, errorMsg = "Not implemented yet" }
	end,

	releaseConnection = function(sid)
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		if method == "cjdns" and config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			return cjdns.releaseConnection(sid)
		end
		
		return { success = false, errorMsg = "Method not supported" }
	end,
	
	connectTo = function(ip, method)
		local methods = {}
		
		local requiestip = cgilua.servervariable("REMOTE_ADDR")
		
		if requiestip ~= "127.0.0.1" then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		-- TODO: check network == cjdns
		if method == "cjdns" and config.cjdns.subscriberSupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			return cjdns.connectTo(ip, method)
		end
		
		return { success = false, errorMsg = "Method not supported" }
	end
}

return interface
