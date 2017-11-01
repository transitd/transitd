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
local threadman = require("threadman")
local rpc = require("rpc")
local gateway = require("gateway")
local scanner = require("scanner")
local network = require("network")
local support = require("support")

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
		
		if authorized then
			info.config = config
		end
		
		info.gateway = config.gateway.enabled == "yes"
		if info.gateway then
			info.suites = support.getSuites()
			info.ipv6support = config.gateway.ipv6support == "yes"
		end
		
		info.success = true
		
		return info
	end,
	
	requestConnection = function(sid, name, port, suite, options)
		
		if not name then
			return { success = false, errorMsg = "Name argument is invalid" }
		end
		
		if not port then
			return { success = false, errorMsg = "Port argument is invalid" }
		end
		
		if not suite then
			return { success = false, errorMsg = "Suite argument is invalid" }
		end
		
		-- enforce types
		sid = tostring(sid)
		name = tostring(name)
		port = tonumber(port)
		suite = tostring(suite)
		
		if options and type(options) ~= "table" then
			return { success = false, errorMsg = "Options type is invalid" }
		end
		
		local ip = cgilua.servervariable("REMOTE_ADDR")
		db.registerNode(name, ip, port)
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'requestConnection', sid, name, ip, port, suite, options)
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
	end,
	
	renewConnection = function(sid)
		
		if not sid then
			return { success = false, errorMsg = "SID argument is invalid" }
		end
		
		sid = tostring(sid)
		
		local ip = cgilua.servervariable("REMOTE_ADDR")
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'renewConnection', sid, ip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
	end,
	
	releaseConnection = function(sid)
		
		if not sid then
			return { success = false, errorMsg = "SID argument is invalid" }
		end
		
		sid = tostring(sid)
		
		local ip = cgilua.servervariable("REMOTE_ADDR")
		
		if config.gateway.enabled ~= "yes" then
			return { success = false, errorMsg = "No gateway here" }
		end
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'releaseConnection', sid, ip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
	end,
	
	connect = function(ip, port, suite, sid)
		
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
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'connect', ip, port, suite, sid)
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
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
		
		local scanId, err = scanner.stopScan()
		if err then
			return { success = false, errorMsg = err }
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
	
	listGateways = function(ip, port, suite, sid)
		
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
		
		local callId, err = rpc.wrapBlockingCall('rpc-interface', 'status', authorized)
		if err then
			return { success = false, errorMsg = err }
		end
		
		return { success = true, ["callId"] = callId }
		
	end,
	
	configure = function(settings)
		
		local requestip = cgilua.servervariable("REMOTE_ADDR")
		
		local authorized, err = network.isAuthorizedIp(requestip)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if not authorized then
			return { success = false, errorMsg = "Permission denied" }
		end
		
		for setting, value in pairs(settings) do
			local result, err = set_config(setting, value)
			if err then
				return { success = false, errorMsg = err }
			end
			threadman.notify({type = "config", ["setting"] = setting, ["value"] = value})
		end
		
		save_config()
		
		threadman.notify({type = "exit", ["restart"] = true})
		
		return { success = true }
		
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

function rpcInterface.transaction(suite, method, request, response)
	
	local suites = support.getSuites()
	if not suites[suite]
	or not suites[suite].network
	or not suites[suite].network.module
	or not suites[suite].tunnel
	or not suites[suite].tunnel.module
	or not suites[suite].payment
	or not suites[suite].payment.module
	then
		return { success = false, errorMsg = "Suite not supported" }
	end
	
	request.suite = suite
	
	local networkModule = require("networks."..suites[suite].network.module)
	local tunnelModule = require("tunnels."..suites[suite].tunnel.module)
	local paymentModule = require("payments."..suites[suite].payment.module)
	
	local abort = false
	for k,stage in pairs({"Init","","Commit"}) do
		local stageMethod = method..stage
		for i,module in pairs({gateway,networkModule,tunnelModule,paymentModule}) do
			if module[stageMethod] then
				response = module[stageMethod](request, response)
				if response.success == false then abort = true break end
			end
		end
		if abort then break end
	end
	if abort then
		local stageMethod = method.."Abort"
		for i,module in pairs({gateway,networkModule,tunnelModule,paymentModule}) do
			if module[stageMethod] then
				response = module[stageMethod](request, response)
			end
		end
	end
	
	if response.success == nil then
		response.success = false
		response.errorMsg = "Unknown error"
	end
	
	return response
	
end

function rpcInterface.requestConnection(sid, name, ip, port, suite, options)
	
	local request = {
		["sid"] = sid,
		["name"] = name,
		["ip"] = ip,
		["port"] = port,
		["options"] = options
	}
	
	return rpcInterface.transaction(suite, "requestConnection", request, {})
end

function rpcInterface.renewConnection(sid)
	
	local session, err = db.lookupSession(sid)
	
	if session == nil then
		return { success = false, errorMsg = "No such session" }
	end
	
	if session.subscriber ~= 1 or session.active ~= 1 then
		return { success = false, errorMsg = "Not a valid session" }
	end
	
	local suite = session.suite
	
	local request = {
		["sid"] = sid,
	}
	
	return rpcInterface.transaction(suite, "renewConnection", request, {})
end

function rpcInterface.releaseConnection(sid)
	
	local session, err = db.lookupSession(sid)
	
	if session == nil then
		return { success = false, errorMsg = "No such session" }
	end
	
	if session.subscriber ~= 1 or session.active ~= 1 then
		return { success = false, errorMsg = "Not a valid session" }
	end
	
	local suite = session.suite
	
	local request = {
		["sid"] = sid,
	}
	
	return rpcInterface.transaction(suite, "releaseConnection", request, {})
end

function rpcInterface.connect(ip, port, gatewaySuiteId, sid)
	
	local proxy = rpc.getProxy(ip, port)
	
	local info, err = proxy.nodeInfo()
	if err then
		return { success = false, errorMsg = "Failed to connect to " .. ip .. ": " .. err}
	else
		db.registerNode(info.name, ip, port)
	end
	
	local gatewaySuite = nil
	
	if info.suites then
		
		local suites = support.getSuites()
		
		-- check to make sure suite is supported
		for id, suite in pairs(info.suites) do
			if suite.id then
				if suite.id == gatewaySuiteId then
					gatewaySuite = suite
				end
				-- register suites
				db.registerGateway(info.name, ip, port, suite.id)
			end
		end
	end
	
	if not gatewaySuite then
		return { success = false, errorMsg = "Suite not supported at " .. ip}
	end
	
	local mySuite, err = support.matchSuite(gatewaySuite)
	if err then 
		return { success = false, errorMsg = "Failed to match suite: " .. err}
	end
	
	if not mySuite then
		return { success = false, errorMsg = "Suite not supported locally"}
	end
	
	local request = {
		["sid"] = sid,
		["name"] = info.name,
		["ip"] = ip,
		["port"] = port,
		["gatewaySuite"] = gatewaySuiteId,
	}
	
	return rpcInterface.transaction(mySuite.id, "connect", request, {})
	
end

function rpcInterface.disconnect(sid)
	
	local session, err = db.lookupSession(sid)
	
	if session == nil then
		return { success = false, errorMsg = "No such session" }
	end
	
	if session.active ~= 1 then
		return { success = false, errorMsg = "Not an active session" }
	end
	
	local suite = session.suite
	
	local request = {
		["sid"] = sid,
	}
	
	return rpcInterface.transaction(suite, "disconnect", request, {})
	
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

function rpcInterface.getGraphSince(timestamp)
	
	local hosts = {}
	local links = {}
	
	for netmod,net in pairs(support.getNetworks()) do
		
		local lastScanId, err = db.getLastScanId(netmod)
		if err then
			return { success = false, errorMsg = err }
		end
		
		if lastScanId then
			
			local hs, err = db.getNetworkHostsSince(netmod, timestamp, lastScanId)
			if err then
				return { success = false, errorMsg = err }
			else
				for k,v in pairs(hs) do hosts[k] = v end
			end
			
			local ls, err = db.getLinksSince(netmod, timestamp, lastScanId)
			if err then
				return { success = false, errorMsg = err }
			else
				for k,v in pairs(ls) do links[k] = v end
			end
			
		end
	end
	
	local interfaces, err = network.getInterfaces();
	if err then
		return { success = false, errorMsg = err }
	end
	
	for k,host in pairs(hosts) do
		host.type = 'none'
		host.label = host.ip
		
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
						host.label = 'This Node'
						break
					end
				end
			end
		end
		
		if host.type == 'none' then
			local gateway, err = db.lookupGatewayByIp(host.ip)
			if gateway then
				host.type = 'gateway'
				host.label = gateway.name
			end
		end
		
		if host.type == 'none' then
			local node, err = db.lookupNodeByIp(host.ip)
			if node then
				host.type = 'node'
				host.label = node.name
			end
		end
	end
	
	return { success = true, scanId = lastScanId, sinceTimestamp = timestamp, ["hosts"] = hosts, ["links"] = links }
end

function rpcInterface.status(authorized)
	
	local result = { success = true }
	
	local monitor = require('monitor')
	
	result.online = monitor.isOnline()
	
	if authorized then
		
		-- TODO: return all ips, not just one
		
		local if4, err = network.getIpv4TransitInterface()
		if not err and if4 and #(if4.ipv4subnets) > 0 then
			local subnet = if4.ipv4subnets[1]
			if subnet then
				result.ipv4 = {ip = network.ip2string(subnet[1]), cidr = subnet[2]}
			end
		end
		
		local if6, err = network.getIpv6TransitInterface()
		if not err and if6 and #(if6.ipv6subnets) > 0 then
			local subnet = if6.ipv6subnets[1]
			if subnet then
				result.ipv6 = {ip = network.ip2string(subnet[1]), cidr = subnet[2]}
			end
		end
	end
	
	return result, nil
end

return rpcInterface
