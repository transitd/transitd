--[[
@file gateway.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module gateway
local gateway = {}

-- gateway management utility functions

local config = require("config")
local db = require("db")
local bit32 = require("bit32")
local bit128 = require("bit128")
local network = require("network")
local random = require("random")
local support = require("support")
local rpc = require("rpc")
local threadman = require("threadman")

local tunnelsEnabled = false

function gateway.setup()
	
	if config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
		
		local interface, err = network.getIpv4TransitInterface()
		if err then
			error("Failed to determine IPv4 transit interface! Cannot start in gateway mode. ("..err..")")
		end
		if not interface then
			error("Failed to determine IPv4 transit interface! Cannot start in gateway mode.")
		end
		
		if config.gateway.ipv6support == "yes" then
			
			local interface, err = network.getIpv6TransitInterface()
			if err then
				error("Failed to determine IPv6 transit interface! Please disable ipv6support in the configuration file. ("..err..")")
			end
			if not interface then
				error("Failed to determine IPv6 transit interface! Please disable ipv6support in the configuration file.")
			end
		end
		
		for tunmod,tun in pairs(support.getTunnels()) do
			
			local module = require("tunnels."..tun.module)
			
			if module.gatewaySetup then
				local result, err = module.gatewaySetup()
				if err then
					error("Failed to set up tunnel module: "..err)
				end
			end
			
		end
		
		tunnelsEnabled = true
	end
	
end

function gateway.teardown()
	
	if tunnelsEnabled then
		
		for netmod,net in pairs(support.getTunnels()) do
			
			local module = require("tunnels."..net.module)
			
			if module['gatewayTeardown'] then
				local result, err = module.gatewayTeardown()
				if err then
					error("Failed to tear down tunnel module: "..err)
				end
			end
			
		end
		
	end
	
end

function gateway.requestConnection(request, response)
	
	-- check to make sure the user isn't already registered
	local activeSubscriber, err = db.lookupActiveSubscriberSessionByIp(request.ip, request.port)
	if err then
		response.success = false response.errorMsg = err return response
	end
	if activeSubscriber ~= nil then
		response.success = false response.errorMsg = "Already registered" response.temporaryError = true return response
	end
	
	-- check maxclients config to make sure we are not registering more clients than needed
	local activeSessions = db.getActiveSessions()
	if #activeSessions >= config.gateway.maxConnections then
		response.success = false response.errorMsg = "Too many sessions" response.temporaryError = true return response
	end
	
	-- TODO: check ip reachability
	
	request.sid, err = gateway.allocateSid(request.sid)
	if err ~= nil then
		response.success = false response.errorMsg = err response.temporaryError = true return response
	end
	
	response.timeout = tonumber(config.gateway.subscriberTimeout)
	
	response.success = true
	
	return response
end

function gateway.requestConnectionCommit(request, response)
	
	local result, err = db.registerSubscriberSession(request.sid, request.name, request.suite, request.ip, request.port, response.ipv4, response.ipv4gateway, response.ipv6, response.ipv6gateway, response.timeout)
	if err then
		threadman.notify({type = "error", module = "gateway", ["function"] = "renewConnectionCommit", ["request"] = request, ["response"] = response, ["error"] = err, ["result"] = result})
	end
	
	threadman.notify({type = "registered", ["request"] = request, ["response"] = response})
	
	response.success = true
	
	return response
end

function gateway.renewConnection(request, response)
	response.timeout = config.gateway.subscriberTimeout
	response.success = true
	return response
end

function gateway.renewConnectionAbort(request, response)
	response.timeout = nil
	return response
end

function gateway.renewConnectionCommit(request, response)
	
	local result, err = db.updateSessionTimeout(request.sid, response.timeout)
	if err then
		threadman.notify({type = "error", module = "gateway", ["function"] = "renewConnectionCommit", ["request"] = request, ["response"] = response, ["error"] = err, ["result"] = result})
	end
	
	threadman.notify({type = "renewed", ["request"] = request, ["response"] = response})
	
	response.success = true
	
	return response
end

function gateway.releaseConnectionCommit(request, response)
	
	local result, err = db.deactivateSession(request.sid)
	if err then
		threadman.notify({type = "error", module = "gateway", ["function"] = "releaseConnectionCommit", ["request"] = request, ["response"] = response, ["error"] = err, ["result"] = result})
	end
	
	threadman.notify({type = "released", ["request"] = request, ["response"] = response})
	
	response.success = true
	
	return response
end

function gateway.connect(request, response)
	
	local sid, err = gateway.allocateSid(request.sid)
	if err then
		response.success = false response.errorMsg = err response.temporaryError = true return response
	end
	
	response.sid = sid
	
	if request.sid == nil then
		request.sid = sid
	elseif request.sid ~= response.sid then
		response.success = false response.errorMsg = "Session ID mismatch" return response
	end
	
	local result, err = db.registerGatewaySession(request.sid, request.name, request.suite, request.ip, request.port)
	if err then
		response.success = false response.errorMsg = err response.temporaryError = true return response
	end
	
	local proxy = rpc.getProxy(request.ip, request.port)
	
	local result, err = proxy.requestConnection(request.sid, config.main.name, config.daemon.rpcport, request.gatewaySuite, request.options)
	if err then
		response.success = false response.errorMsg = err return response
	elseif result.errorMsg then
		response.success = false response.errorMsg = result.errorMsg return response
	elseif result.success == false then
		response.success = false response.errorMsg = "Unknown error" return response
	end
	
	response.gatewayResponse = result
	
	response.success = true
	
	return response
end

function gateway.connectAbort(request, response)
	response.sid = nil
	return response
end

function gateway.connectCommit(request, response)
	
	db.updateGatewaySession(response.sid, true, response.gatewayResponse.ipv4, response.gatewayResponse.ipv4gateway, response.gatewayResponse.ipv6, response.gatewayResponse.ipv6gateway, response.gatewayResponse.timeout)
	threadman.notify({type = "connected", ["request"] = request, ["response"] = response})
	
	return response
end

function gateway.disconnect(request, response)
	
	local session, err = db.lookupSession(request.sid)
	if err then
		response.success = false response.errorMsg = err return response
	end
	
	-- notify the gateway
	local ip = session.meshIP
	local port = session.port
	local proxy = rpc.getProxy(ip, port)
	local result = proxy.releaseConnection(request.sid)
	if type(result) ~= "table" or not result.success then
		threadman.notify({type = "error", module = "gateway", ["function"] = "disconnect", ["request"] = request, ["response"] = response, ["error"] = "Release call unsuccessful", ["result"] = result})
	end
	
	response.success = true
	
	return response
end


function gateway.disconnectCommit(request, response)
	
	local result, err = db.deactivateSession(request.sid)
	if err then
		threadman.notify({type = "error", module = "gateway", ["function"] = "disconnectCommit", ["request"] = request, ["response"] = response, ["error"] = err, ["result"] = result})
	end
	
	threadman.notify({type = "disconnected", ["request"] = request, ["response"] = response})
	
	return response
end

-- come up with an ipv4 addr within a subnet
function gateway.allocateIpv4(subnetStr, gatewayIpStr)
	
	local subnet, err = network.parseIpv4Subnet(subnetStr)
	local prefixIp, cidr = unpack(subnet)
	if err then
		return nil, "Failed to parse ipv4subnet"
	end
	
	local gatewayIp, err = network.parseIpv4(gatewayIpStr)
	if err then
		return nil, "Failed to parse ipv4gateway"
	end
	gatewayIp = network.ip2string(gatewayIp)
	
	local prefixMask = network.Ipv4cidrToBinaryMask(cidr)
	local prefixAddr = bit32.band(network.ip2binary(prefixIp), prefixMask)
	local subnetMask = bit32.bnot(prefixMask)
	local randomAddr = math.random(2^30)
	
	for i=1,2^(32-cidr) do
		local subnetAddr = bit32.band(randomAddr, subnetMask)
		local combinedAddr = bit32.bor(prefixAddr, subnetAddr)
		local ip = network.ip2string(network.binaryToIp(combinedAddr));
		
		-- check in database to make sure ipv4 hasn't already been allocated to another subscriber
		-- TODO: fix race conditions
		local session, err = db.lookupActiveSubscriberSessionByInternetIp(ip)
		if err then return nil, err end
		
		if session or ip == gatewayIp then
			randomAddr = randomAddr+1
		else
			-- check to make sure this ip is really not allocated already on the network
			local pings, err = network.ping4(ip)
			if err then return nil, err end
			
			if pings then
				randomAddr = randomAddr+1
			else
				return {ip, cidr}, nil
			end
		end
	end
	
	return nil, "Failed to allocate IPv4"
end

-- come up with an ipv6 addr within a subnet
function gateway.allocateIpv6(subnetStr, gatewayIpStr)
	
	local subnet, err = network.parseIpv6Subnet(subnetStr)
	local prefixIp, cidr = unpack(subnet)
	if err then
		return nil, "Failed to parse ipv6subnet"
	end
	
	local gatewayIp, err = network.parseIpv6(gatewayIpStr)
	if err then
		return nil, "Failed to parse ipv6gateway"
	end
	gatewayIp = network.ip2string(gatewayIp)
	
	local prefixMask = network.Ipv6cidrToBinaryMask(cidr)
	local prefixAddr = bit128.band(network.ip2binary(prefixIp), prefixMask)
	local subnetMask = bit128.bnot(prefixMask)
	local randomAddr = {math.random(2^30),math.random(2^30),math.random(2^30),math.random(2^30)}
	
	for i=1,2^(128-cidr) do
		local subnetAddr = bit128.band(randomAddr, subnetMask)
		local combinedAddr = bit128.bor(prefixAddr, subnetAddr)
		local ip = network.ip2string(network.binaryToIp(combinedAddr));
		
		-- check in database to make sure ipv4 hasn't already been allocated to another subscriber
		-- TODO: fix race conditions
		local session, err = db.lookupActiveSubscriberSessionByInternetIp(ip)
		if err then return nil, err end
		
		if session or ip == gatewayIp then
			randomAddr = randomAddr+1
		else
			-- check to make sure this ip is really not allocated already on the network
			local pings, err = network.ping6(ip)
			if err then return nil, err end
			
			if pings then
				randomAddr = randomAddr+1
			else
				return {ip, cidr}, nil
			end
		end
	end
	
	return nil, "Failed to allocate IPv6"
end

function gateway.allocateSid(suggesteredSid)
	
	-- come up with unused session id
	
	-- TODO: fix race condition
	
	if suggesteredSid == nil then
		local sid = ""
		for t=0,5 do
			sid = random.mktoken(32)
			if db.lookupSession(sid) ~= nil then
				sid = ""
			else
				break
			end
		end
		if not sid or sid == "" then
			return nil, "Failed to come up with an unused session id"
		end
		return sid, nil
	else
		if db.lookupSession(suggesteredSid) ~= nil then
			return nil, "Duplicate session id"
		end
		return suggesteredSid, nil
	end
end

return gateway
