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

local cjdnsTunnelEnabled = false

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
		
		local tunnel = require("cjdnstools.tunnel")
		local result, err = tunnel.gatewaySetup()
		if err then
			error("Failed to set up cjdns tunnel gateway: "..err)
		end
		
		cjdnsTunnelEnabled = true
	end
	
end

function gateway.teardown()
	
	if cjdnsTunnelEnabled then
		
		local tunnel = require("cjdnstools.tunnel")
		local result, err = tunnel.gatewayTeardown()
		if err then
			error("Failed to set up cjdns tunnel gateway: "..err)
		end
	end
	
end

function gateway.allocateIpv4()
	
	-- come up with random ipv4 based on settings in config
	local subnet, err = network.parseIpv4Subnet(config.gateway.ipv4subnet)
	local prefixIp, cidr = unpack(subnet)
	if err then
		return nil, "Failed to parse ipv4subnet"
	end
	
	local gatewayIp, err = network.parseIpv4(config.gateway.ipv4gateway)
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

function gateway.allocateIpv6()
	
	if not config.gateway.ipv6subnet
	or not config.gateway.ipv6gateway then
		return nil, nil
	end
	
	local gatewayIp, err = network.parseIpv6(config.gateway.ipv6gateway)
	if err then
		return nil, "Failed to parse ipv6gateway"
	end
	gatewayIp = network.ip2string(gatewayIp)
	
	-- come up with random ipv4 based on settings in config
	local subnet, err = network.parseIpv6Subnet(config.gateway.ipv6subnet)
	local prefixIp, cidr = unpack(subnet)
	if err then
		return nil, "Failed to parse ipv6subnet"
	end
	
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
