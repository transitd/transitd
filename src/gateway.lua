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
			error("Failed to determine IPv6 transit interface! ("..err..")")
		end
		if not interface then
			-- TODO: set up 6in4
			return nil, "6in4 support unimplemented, no IPv6 transit available"
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
	
	-- set up kernel forwarding option
	local success, err = network.setIpv4Forwading(1)
	if err then return nil, err end
	
	if config.gateway.ipv6support == "yes" then
		
		-- set up kernel forwarding option
		local success, err = network.setIpv6Forwading(1)
		if err then return nil, err end
		
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
	
	response.sid = request.sid
	
	local result, err = db.registerSession(request.sid, true, request.name, request.suite, request.ip, request.port)
	if err then
		threadman.notify({type = "error", module = "gateway", ["function"] = "requestConnection", ["request"] = request, ["response"] = response, ["error"] = err, ["result"] = result})
	end
	
	local timestamp = os.time()
	response.timeoutTimestamp = timestamp + tonumber(config.gateway.subscriberTimeout)
	
	response.success = true
	
	return response
end

function gateway.requestConnectionCommit(request, response)
	
	local result, err = db.updateSession(request.sid, true, response.ipv4, response.cidr4, response.ipv4gateway, response.interface4, response.ipv6, response.cidr6, response.ipv6gateway, response.interface6, response.timeoutTimestamp)
	if err then
		threadman.notify({type = "error", module = "gateway", ["function"] = "requestConnectionCommit", ["request"] = request, ["response"] = response, ["error"] = err, ["result"] = result})
	end
	
	threadman.notify({type = "registered", ["request"] = request, ["response"] = response})
	
	response.success = true
	
	return response
end

function gateway.renewConnection(request, response)
	
	local session, err = db.lookupSession(request.sid)
	if err then
		response.success = false response.errorMsg = err return response
	end
	
	response.sid = session.sid
	
	local timestamp = os.time()
	response.timeoutTimestamp = timestamp + tonumber(config.gateway.subscriberTimeout)
	response.success = true
	return response
	
end

function gateway.renewConnectionAbort(request, response)
	
	response.timeoutTimestamp = nil
	return response
	
end

function gateway.renewConnectionCommit(request, response)
	
	local result, err = db.updateSessionTimeout(request.sid, response.timeoutTimestamp)
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
	
	local err
	request.sid, err = gateway.allocateSid(request.sid)
	if err then
		response.success = false response.errorMsg = err response.temporaryError = true return response
	end
	
	response.sid = request.sid
	
	local result, err = db.registerSession(request.sid, false, request.name, request.suite, request.ip, request.port)
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
	
	if not response.gatewayResponse.ipv4 and not response.gatewayResponse.ipv6 then
		response.success = false response.errorMsg = "Failed to obtain IPv4 and IPv6 addresses from gateway" return response
	end
	if response.gatewayResponse.ipv4 and not response.gatewayResponse.cidr4 then
		response.success = false response.errorMsg = "Failed to obtain IPv4 CIDR from gateway" return response
	end
	if response.gatewayResponse.ipv6 and not response.gatewayResponse.cidr6 then
		response.success = false response.errorMsg = "Failed to obtain IPv6 CIDR from gateway" return response
	end
	
	-- parse addresses
	if response.gatewayResponse.ipv4 then
		local subnet4, ipv4, cidr4, ipv4gateway, err
		subnet4, err = network.parseIpv4Subnet(response.gatewayResponse.ipv4.."/"..response.gatewayResponse.cidr4)
		if err then
			response.success = false response.errorMsg = "Failed to parse IPv4 address" return response
		end
		ipv4, response.cidr4 = unpack(subnet4)
		response.ipv4 = network.ip2string(ipv4)
		
		ipv4gateway, err = network.parseIpv4(response.gatewayResponse.ipv4gateway)
		if err then
			response.success = false response.errorMsg = "Failed to parse gateway IPv4 address" return response
		end
		if not ipv4gateway then
			response.success = false response.errorMsg = "No gateway IPv4 address provided" return response
		end
		response.ipv4gateway = network.ip2string(ipv4gateway)
	end
	if response.gatewayResponse.ipv6 then
		local subnet6, ipv6, cidr6, ipv6gateway, err
		subnet6, err = network.parseIpv6Subnet(response.gatewayResponse.ipv6.."/"..response.gatewayResponse.cidr6)
		if err then
			response.success = false response.errorMsg = "Failed to parse IPv6 address" return response
		end
		ipv6, response.cidr6 = unpack(subnet6)
		response.ipv6 = network.ip2string(ipv6)
		
		ipv6gateway, err = network.parseIpv6(response.gatewayResponse.ipv6gateway)
		if err then
			response.success = false response.errorMsg = "Failed to parse gateway IPv6 address" return response
		end
		if not ipv6gateway then
			response.success = false response.errorMsg = "No gateway IPv6 address provided" return response
		end
		response.ipv6gateway = network.ip2string(ipv6gateway)
	end
	
	db.updateSession(
		response.sid,
		false,
		response.gatewayResponse.ipv4,
		response.gatewayResponse.cidr4,
		response.gatewayResponse.ipv4gateway,
		"",
		response.gatewayResponse.ipv6,
		response.gatewayResponse.cidr6,
		response.gatewayResponse.ipv6gateway,
		"",
		response.gatewayResponse.timeoutTimestamp
	)
	
	response.success = true
	
	return response
end

function gateway.connectAbort(request, response)
	response.sid = nil
	response.cidr4 = nil
	response.ipv4 = nil
	response.ipv4gateway = nil
	response.cidr6 = nil
	response.ipv6 = nil
	response.ipv6gateway = nil
	
	return response
end

function gateway.connectCommit(request, response)
	
	db.updateSession(
		response.sid,
		true,
		response.gatewayResponse.ipv4,
		response.gatewayResponse.cidr4,
		response.gatewayResponse.ipv4gateway,
		response.interface4,
		response.gatewayResponse.ipv6,
		response.gatewayResponse.cidr6,
		response.gatewayResponse.ipv6gateway,
		response.interface6,
		response.gatewayResponse.timeoutTimestamp
	)
	
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
function gateway.allocateIpv4(subnet, gatewayIp)
	
	local prefixIp, cidr = unpack(subnet)
	local gatewayIpStr = network.ip2string(gatewayIp)
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
		
		if session or ip == gatewayIpStr then
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
function gateway.allocateIpv6(subnet, gatewayIp)
	
	local prefixIp, cidr = unpack(subnet)
	local gatewayIpStr = network.ip2string(gatewayIp)
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
		
		if session or ip == gatewayIpStr then
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

-- sets up interface on gateway side to get it ready to forward packets
-- returns gateway ip that should be supplied to subscribers
function gateway.interfaceSetup4(mode, interface, subnet, gatewayIp)
	
	mode = mode or "none"
	
	if mode == "none" then
		return true, nil
	end
	
	if mode ~= "nat" and mode ~= "route" then
		return nil, "Unknown gateway routing mode "..mode
	end
	
	-- determine ip that will be used on gateway interface
	local cidr
	if mode == "nat" then
		local prefix
		prefix, cidr = unpack(subnet)
	end
	if mode == "route" then
		subnet, err = gateway.allocateIpv4(subnet, gatewayIp);
		if err then
			return nil, "Failed to allocate IPv4: "..err
		end
		if not subnet4 then
			return nil, "Failed to allocate IPv4 for interface "..interface.name
		end
		gatewayIp, cidr = unpack(subnet)
	end
	
	-- remove interface address if it is already set
	network.unsetInterfaceIp(interface, {gatewayIp, cidr})
	
	-- set up interface ip address
	local result, err = network.setInterfaceIp(interface, {gatewayIp, cidr})
	if err then
		return nil, "Failed to set local IPv4 address: "..err
	end
	
	if mode == "nat" then
		
		-- determine transit interface
		local transitInterface, err = network.getIpv4TransitInterface()
		if err then
			return nil, "Failed to determine IPv4 transit interface: "..err
		end
		if not transitInterface then
			return nil, "Failed to determine IPv4 transit interface"
		end
		
		local result, err = network.setupNat4(interface, transitInterface)
		if err then
			return nil, "Failed to set up NAT: "..err
		end
		
	end
	
	if mode == "route" then
		
		local prefixMask = network.Ipv4cidrToBinaryMask(cidr)
		local prefixAddr = bit32.band(network.ip2binary(gatewayIp), prefixMask)
		
		local result, err = network.setRoute(interface, {prefixAddr, cidr})
		if err then
			return nil, "Failed to set up route: "..err
		end
		
	end
	
	return {gatewayIp, cidr}, nil
end

function gateway.interfaceTeardown4(interface, subnet)
	
	-- tear down interface ip address
	-- TODO: fix
	--local result, err = network.unsetInterfaceIp(interface, subnet)
	--if err then
	--	return nil, "Failed to unset local IPv4 address: "..err
	--end
	
	-- TODO: remove nat / route
	
	return true, nil
end

-- sets up interface on gateway side to get it ready to forward packets
-- returns gateway ip that should be supplied to subscribers
function gateway.interfaceSetup6(mode, interface, subnet, gatewayIp)
	
	mode = mode or "none"
	
	if mode == "none" then
		return true, nil
	end
	
	if mode ~= "nat" and mode ~= "route" then
		return nil, "Unknown gateway routing mode "..mode
	end
	
	local cidr
	if mode == "nat" then
		local prefix
		prefix, cidr = unpack(subnet)
	end
	if mode == "route" then
		subnet, err = gateway.allocateIpv6(subnet, gatewayIp);
		if err then
			return nil, "Failed to allocate IPv6: "..err
		end
		if not subnet then
			return nil, "Failed to allocate IPv6 for interface "..interface.name
		end
		gatewayIp, cidr = unpack(subnet)
	end
	
	-- remove interface address if it is already set
	network.unsetInterfaceIp(interface, {gatewayIp, cidr})
	
	-- set up interface ip address
	local result, err = network.setInterfaceIp(interface, {gatewayIp, cidr})
	if err then
		return nil, "Failed to set local IPv6 address: "..err
	end
	
	if mode == "nat" then
		
		-- determine transit interface
		local transitInterface, err = network.getIpv6TransitInterface()
		if err then
			return nil, "Failed to determine IPv6 transit interface: "..err
		end
		if not transitInterface then
			return nil, "Failed to determine IPv6 transit interface"
		end
		
		local result, err = network.setupNat6(interface, transitInterface)
		if err then
			return nil, "Failed to set up NAT: "..err
		end
		
	end
	
	if mode == "route" then
		
		local prefixMask = network.Ipv6cidrToBinaryMask(cidr)
		local prefixAddr = bit128.band(network.ip2binary(gatewayIp), prefixMask)
		
		local result, err = network.setRoute(interface, {prefixAddr, cidr})
		if err then
			return nil, "Failed to set up route: "..err
		end
		
	end
	
	return {gatewayIp, cidr}, nil
end

function gateway.interfaceTeardown6(interface, subnet)
	
	-- tear down interface ip address
	-- TODO: fix
	--local result, err = network.unsetInterfaceIp(interface, subnet)
	--if err then
	--	return nil, "Failed to unset local IPv6 address: "..err
	--end
	
	-- TODO: remove nat / route
	
	return true, nil
end


return gateway
