
local config = require("config")
local db = require("db")
local cjdns = require("rpc-interface.cjdns")
local threadman = require("threadman")
local rpc = require("rpc")
local gateway = require("gateway")
local scanner = require("scanner")

local interface = {
	echo = function (msg) return msg end,
	
	nodeInfo = function()
		
		local info = { name = config.main.name }
		
		info['gateway'] = config.gateway.enabled == "yes"
		if info['gateway'] then
			info['ipv6support'] = config.gateway.ipv6support == "yes"
		end
		
		if config.gateway.enabled == "yes" then
			local methods = {}
			if config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
				methods[#methods+1] = {name = "cjdns"}
			end
			info['methods'] = methods
		end
		
		return info
	end,
	
	requestConnection = function(sid, name, port, method, options)
		
		local subscriberip = cgilua.servervariable("REMOTE_ADDR")
		
		db.registerNode(name, subscriberip, port)
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		-- TODO: check to make sure they are connecting over allowed network
		
		-- check to make sure the user isn't already registered
		local activeSubscriber, err = db.lookupActiveSubscriberSessionByIp(subscriberip, port)
		if err then
			return { success = false, errorMsg = err }
		end
		if activeSubscriber ~= nil then
			return { success = false, errorMsg = "Already registered", temporaryError = true }
		end
		
		-- check maxclients config to make sure we are not registering more clients than needed
		local activeSessions = db.getActiveSessions()
		if #activeSessions >= config.gateway.maxConnections then
			return { success = false, errorMsg = "Too many sessions", temporaryError = true }
		end
		
		if method == "cjdns" and config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			return cjdns.requestConnection(sid, name, port, method, options)
		end
		
		return { success = false, errorMsg = "Method not supported" }
	end,
	
	renewConnection = function(sid)
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		if method == "cjdns" and config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			cjdns.renewConnection(sid)
		end
		
		local timeout = config.gateway.subscriberTimeout
		db.updateSessionTimeout(sid, timeout)
		
		threadman.notify({type = "renewedSubscriberSession", ["sid"] = sid, ["timeout"] = timeout})
		
		return { success = true, ["timeout"] = timeout }
	end,
	
	releaseConnection = function(sid)
		
		sid = tostring(sid)
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		local session, err = db.lookupSession(sid)
		
		if session == nil then
			return { success = false, errorMsg = "No such session" }
		end
		
		if session.subscriber ~= 1 or session.active ~= 1 then
			return { success = false, errorMsg = "Not a valid session" }
		end
		
		if session.method == "cjdns" and config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			return cjdns.releaseConnection(sid)
		end
		
		return { success = false, errorMsg = "Method not supported" }
	end,
	
	connectTo = function(ip, port, method, sid)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		if requestip ~= "127.0.0.1" and requestip ~= "::1" then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		if config.gateway.enabled == "yes" then
			return { success = false, errorMsg = "Cannot use connect functionality in gateway mode" }
		end
		
		-- TODO: check network == cjdns
		if method == "cjdns" and config.cjdns.subscriberSupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			
			local cid, err = rpc.allocateCallId()
			if err ~= nil then
				return { success = false, errorMsg = err }
			end
			
			local err = nil
			if sid == nil then
				sid, err = gateway.allocateSid()
			end
			if err ~= nil then
				return { success = false, errorMsg = err }
			end
			
			-- TODO: switch to using notifications to propagate config variables to threads
			-- instead of running config code for each thread
			local cjson_safe = require("cjson.safe")
			local config_encoded = cjson_safe.encode(config)
			
			threadman.startThread(function()
				-- luaproc doesn't load everything by default
				io = require("io")
				os = require("os")
				table = require("table")
				string = require("string")
				math = require("math")
				debug = require("debug")
				coroutine = require("coroutine")
				local luaproc = require("luaproc")
				
				local cjson_safe = require("cjson.safe")
				_G.config = cjson_safe.decode(config_encoded)
				
				local conman = require("conman")
				local result, err = conman.connectToGateway(ip, port, method, sid)
				
				local threadman = require("threadman")
				threadman.notify({type="nonblockingcall.complete", callId=cid, ["result"]=result, ["err"]=err})
			end)
			
			return { success = true, callId = cid }
		end
		
		return { success = false, errorMsg = "Method not supported" }
	end,
	
	disconnect = function(sid)
		
		sid = tostring(sid)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		if requestip ~= "127.0.0.1" and requestip ~= "::1" then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		if config.gateway.enabled == "yes" then
			return { success = false, errorMsg = "Cannot use connect functionality in gateway mode" }
		end
		
		local cid, err = rpc.allocateCallId()
		if err ~= nil then
			return { success = false, errorMsg = err }
		end
		
		-- TODO: switch to using notifications to propagate config variables to threads
		-- instead of running config code for each thread
		local cjson_safe = require("cjson.safe")
		local config_encoded = cjson_safe.encode(config)
		
		threadman.startThread(function()
			-- luaproc doesn't load everything by default
			io = require("io")
			os = require("os")
			table = require("table")
			string = require("string")
			math = require("math")
			debug = require("debug")
			coroutine = require("coroutine")
			local luaproc = require("luaproc")
			
			local cjson_safe = require("cjson.safe")
			_G.config = cjson_safe.decode(config_encoded)
			
			local conman = require("conman")
			local result, err = conman.disconnectFromGateway(sid)
			
			local threadman = require("threadman")
			threadman.notify({type="nonblockingcall.complete", callId=cid, ["result"]=result, ["err"]=err})
		end)
		
		return { success = true, callId = cid }
		
	end,
	
	startScan = function()
		
		sid = tostring(sid)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		if requestip ~= "127.0.0.1" and requestip ~= "::1" then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		local scanId, err = scanner.startScan()
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["scanId"] = scanId }
	end,
	
	listGateways = function(ip, port, method, sid)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		if requestip ~= "127.0.0.1" and requestip ~= "::1" then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		local gateways, err = db.getRecentGateways()
		
		if err then
			return { success = false, errorMsg = err }
		else
			return { success = true, ["gateways"] = gateways }
		end
		
	end,
	
	listSessions = function()
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		if requestip ~= "127.0.0.1" and requestip ~= "::1" then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		local sessions, err = db.getActiveSessions()
		
		if err then
			return { success = false, errorMsg = err }
		else
			return { success = true, ["sessions"] = sessions }
		end
	end,
	
	pollCallStatus = function(callId)
		if rpc.isBlockingCallDone(callId) then
			local result, err = rpc.returnBlockingCallResult(callId)
			if err ~= nil then
				return { success = false, errorMsg = err }
			else
				return result
			end
		else
			return { success = true, ["callId"] = callId }
		end
	end,
	
}

return interface
