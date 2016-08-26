--[[
@file conman.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module conman
local conman = {}

local config = require("config")
local db = require("db")
local cjdns = require("rpc-interface.cjdns")
local threadman = require("threadman")
local rpc = require("rpc")
local tunnel = require("cjdnstools.tunnel")

local conManTs = 0

local subscriberManager = function()
	
	local sinceTimestamp = conManTs
	conManTs = os.time()
	
	-- add active sessions keys into cjdroute (if not there because of cjdroute restart)
	local sessions, err = db.getActiveSessions()
	if err then
		threadman.notify({type = "error", module = "conman", error = err})
	else
		local connections, err = tunnel.listConnections()
		if err then
			threadman.notify({type = "error", module = "conman", error = err})
		else
			for k,session in pairs(sessions) do
				if session.active == 1 and session.subscriber == 1 then
					local key, err = db.getCjdnsSubscriberKey(session.sid)
					if err or not key then
						threadman.notify({type = "error", module = "conman", error = err})
					else
						local exists = false
						for k,connIndex in pairs(connections) do
							local connection, err = tunnel.showConnection(connIndex)
							if err then
								threadman.notify({type = "error", module = "conman", error = err})
							else
								if connection.key == key then
									exists = true
									break
								end
							end
						end
						if not exists then
							local response, err = tunnel.addKey(key, session.internetIPv4, session.internetIPv6)
							if err then
								threadman.notify({type = "error", module = "conman", error = err})
							else
								threadman.notify({type = "warning", module = "conman", warning = "Warning: added missing key "..key.." in cjdroute"})
							end
						end
					end
				end
			end
		end
	end
	
	-- remove timed out subscriber keys from cjdroute
	local subscribers, err = db.getTimingOutSubscribers(sinceTimestamp)
	if err == nil and subscribers == nil then
		err = "Unexpected subscriber list query result"
	end
	if err then
		threadman.notify({type = "error", module = "conman", error = err})
		return
	end
	
	for k,subscriber in pairs(subscribers) do
		local at = ""
		if subscriber.meshIP ~= nil then
			at = at..subscriber.method.."::"..subscriber.meshIP.." "
		end
		local addr = ""
		if subscriber.internetIPv4 ~= nil then
			addr = addr..subscriber.internetIPv4.." "
		end
		if subscriber.internetIPv6 ~= nil then
			addr = addr..subscriber.internetIPv6.." "
		end
		
		if subscriber.method == "cjdns" then
			cjdns.releaseConnection(subscriber.sid)
		else
			threadman.notify({type = "error", module = "conman", error = "Unknown method", method = subscriber.method})
		end
		
		threadman.notify({type = "subscriberSessionTimedOut", ["sid"] = subscriber.sid})
	end
end

local gatewayManager = function()
	
	local currentTimestamp = os.time()
	local gracePeriod = 10;
	
	local sessions, err = db.getLastActiveSessions()
	if err == nil and sessions == nil then
		err = "Unexpected session list query result"
	end
	if err then
		threadman.notify({type = "error", module = "conman", error = err})
		return
	end
	
	for k, session in pairs(sessions) do
		if session.subscriber == 0 and session.active == 1 then
			if currentTimestamp > session.timeout_timestamp then
				
				conman.disconnect(session.sid)
				
			elseif currentTimestamp > session.timeout_timestamp-gracePeriod then
				
				local gateway = rpc.getProxy(session.meshIP, session.port)
				
				local result, err = gateway.renewConnection(session.sid)
				if err then
					threadman.notify({type = "error", module = "conman", ["error"] = err})
				elseif not result then
					threadman.notify({type = "error", module = "conman", ["error"] = "Unknown error"})
				elseif result.success == false and result.errorMsg then
					threadman.notify({type = "error", module = "conman", ["error"] = result.errorMsg})
				elseif result.success == false then
					threadman.notify({type = "error", module = "conman", ["error"] = "Unknown error"})
				else
					db.updateSessionTimeout(session.sid, result.timeout)
					threadman.notify({type = "renewedGatewaySession", ["sid"] = session.sid, ["timeout"] = result.timeout})
				end
			end
		end
	end
end

function conman.connectToGateway(ip, port, method, sid)
	
	if config.gateway.enabled == "yes" then
		return nil, "Cannot use connect functionality in gateway mode"
	end
	
	local gateway = rpc.getProxy(ip, port)
	
	local info, err = gateway.nodeInfo()
	if err then
		return nil, "Failed to connect to " .. ip .. ": " .. err
	else
		db.registerNode(info.name, ip, port)
	end
	
	if info.methods then
		-- check to make sure method is supported
		local supported = false
		for k, m in pairs(info.methods) do
			if m == method then
				supported = true
			end
			-- register methods
			if m and m.name then
				db.registerGateway(info.name, ip, port, m.name)
			end
		end
	else
		method = nil
	end
	
	if method == nil then
		return nil, "No supported connection methods at " .. ip
	end
	
	if method == "cjdns" then
		db.registerGatewaySession(sid, info.name, method, ip, port)
		local result, err = cjdns.connectTo(ip, port, method, sid)
		if err then return nil, err end
		if result.success then
			db.updateGatewaySession(sid, true, result.ipv4, result.ipv6, result.timeout)
			
			local interface, err = tunnel.getInterface()
			if interface then interface = interface.name end
			threadman.notify({type = "connected", ["sid"] = sid, ["interface"] = interface})
		end
		return result, nil
	else
		return nil, "Unsupported method"
	end
	
	return nil, "Unknown method"
end

function conman.disconnect(sid)
	
	local session, err = db.lookupSession(sid)
	
	if session == nil then
		return nil, "No such session"
	end
	
	if session.active ~= 1 then
		return nil, "Not a valid session"
	end
	
	if session.method == "cjdns" then
		
		if session.subscriber == 0 then
			local result, err = cjdns.disconnect(sid)
			if err then return nil, err end
			if not result.success then return nil, result.errorMsg end
			return true, nil
		else
			local result, err = cjdns.releaseConnection(sid)
			if err then return nil, err end
			if not result.success then return nil, result.errorMsg end
			return true, nil
		end
	end
	
	return nil, "Unknown method"
end

local connectionManager = function()
	if config.gateway.enabled == "yes" then
		subscriberManager()
	else
		gatewayManager()
	end
end

function conman.run()
	local socket = require("socket")
	local listener = threadman.registerListener("conman",{"exit"})
	while true do
		socket.sleep(2)
		connectionManager()
		local msg = {};
		while msg ~= nil do
			msg = listener:listen(true)
			if msg ~= nil then
				if msg["type"] == "exit" then
					threadman.unregisterListener(listener)
					return
				end
			end
		end
	end
	
end

return conman
