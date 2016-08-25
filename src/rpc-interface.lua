--[[
@file rpc-interface.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 Serg
--]]

--- @module rpc-interface
local rpcInterface = {}

local config = require("config")
local db = require("db")
local cjdns = require("rpc-interface.cjdns")
local threadman = require("threadman")
local rpc = require("rpc")
local gateway = require("gateway")
local scanner = require("scanner")
local network = require("network")

function rpcInterface.getInterface()
	return {
	
	nodeInfo = function()
		
		local info = { name = config.main.name }
		
		info.version = 'prototype'
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		info.authorized = authorized
		
		info.gateway = config.gateway.enabled == "yes"
		if info.gateway then
			info.ipv6support = config.gateway.ipv6support == "yes"
		end
		
		if config.gateway.enabled == "yes" then
			local methods = {}
			if config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
				methods[#methods+1] = {name = "cjdns"}
			end
			info.methods = methods
		end
		
		info.success = true
		
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
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if not authorized then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		if config.gateway.enabled == "yes" then
			return { success = false, errorMsg = "Cannot use connect functionality in gateway mode" }
		end
		
		-- TODO: check network == cjdns
		if method == "cjdns" and config.cjdns.subscriberSupport == "yes" and config.cjdns.tunnelSupport == "yes" then
			
			local err = nil
			if sid == nil then
				sid, err = gateway.allocateSid()
			end
			if err ~= nil then
				return { success = false, errorMsg = err }
			end
			
			local callId, err = rpc.wrapBlockingCall('rpc-interface', 'connectTo', ip, port, method, sid)
			if err then
				return { success = false, errorMsg = err }
			end
			
			return { success = true, ["callId"] = callId }
		end
		
		return { success = false, errorMsg = "Method not supported" }
	end,
	
	disconnect = function(sid)
		
		sid = tostring(sid)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if not authorized then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		if config.gateway.enabled == "yes" then
			return { success = false, errorMsg = "Cannot use connect functionality in gateway mode" }
		end
		
		local cid, err = rpc.allocateCallId()
		if err ~= nil then
			return { success = false, errorMsg = err }
		end
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'disconnect', sid)
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
	end,
	
	startScan = function()
		
		sid = tostring(sid)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if not authorized then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		local scanId, err = scanner.startScan()
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["scanId"] = scanId }
	end,
	
	getGraphSince = function(timestamp)
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'getGraphSince', timestamp)
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
	end,
	
	listGateways = function(ip, port, method, sid)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if not authorized then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'listGateways')
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
	end,
	
	listSessions = function()
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if not authorized then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'listSessions')
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
	end,
	
	status = function()
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if not authorized then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'status')
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
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
end

function rpcInterface.getGraphSince(timestamp)
	local net = 'cjdns'
	
	local lastScanId, err = db.getLastScanId(net)
	if err then
		return { success = false, errorMsg = err }
	end
	
	local hosts, err = db.getNetworkHostsSince(net, timestamp, lastScanId)
	if err then
		return { success = false, errorMsg = err }
	end
	
	local links, err = db.getLinksSince(net, timestamp, lastScanId)
	if err then
		return { success = false, errorMsg = err }
	end
	
	local interfaces, err = network.getInterfaces();
	if err then
		return { success = false, errorMsg = err }
	end
	
	for k,host in pairs(hosts) do
		host.type = 'none'
		
		local ip, err = network.parseIp(host.ip)
		if ip then
			local v6 = #ip > 4
			local ifsubnets
			for ik,interface in pairs(interfaces) do
				if v6 then
					ifsubnets = interface.ipv6subnets
				else
					ifsubnets = interface.ipv4subnets
				end
				for k,ifsubnet in pairs(ifsubnets) do
					local addr, cidr = unpack(ifsubnet)
					if host.ip == network.ip2string(addr) then
						host.type = 'self'
						break
					end
				end
			end
		end
		
		if host.type == 'none' then
			local gateway, err = db.lookupGatewayByIp(host.ip)
			if gateway then
				host.type = 'gateway'
			end
		end
		
		if host.type == 'none' then
			local gateway, err = db.lookupNodeByIp(host.ip)
			if gateway then
				host.type = 'node'
			end
		end
	end
	
	return { success = true, scanId = lastScanId, sinceTimestamp = timestamp, ["hosts"] = hosts, ["links"] = links }
end

function rpcInterface.connectTo(ip, port, method, sid)
	local conman = require("conman")
	return conman.connectToGateway(ip, port, method, sid)
end

function rpcInterface.disconnect(sid)
	local conman = require("conman")
	return conman.disconnectFromGateway(sid)
end

function rpcInterface.listGateways()
	
	local gateways, err = db.getRecentGateways()
	
	if err then
		return { success = false, errorMsg = err }
	else
		return { success = true, ["gateways"] = gateways }
	end
	
end

function rpcInterface.listSessions()
	
	local sessions, err = db.getActiveSessions()
	
	if err then
		return { success = false, errorMsg = err }
	else
		return { success = true, ["sessions"] = sessions }
	end
	
end

function rpcInterface.status()
	
	local result = { success = true }
	
	local online, err = network.ping4('8.8.8.8')
	if err then
		return { success = true, ["online"] = false }
	end
	result.online = online
	
	local if4, err = network.getIpv4TransitInterface()
	if not err and if4 and #(if4.ipv4subnets) > 0 then
		local subnet = if4.ipv4subnets[1]
		result.ipv4 = {ip = network.ip2string(subnet[1]), cidr = subnet[2]}
	end
	
	local if6, err = network.getIpv6TransitInterface()
	if not err and if6 and #(if6.ipv6subnets) > 0 then
		local subnet = if6.ipv4subnets[1]
		result.ipv6 = {ip = network.ip2string(subnet[1]), cidr = subnet[2]}
	end
	
	return result, nil
end

return rpcInterface
