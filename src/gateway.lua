--- @module gateway
local gateway = {}

-- gateway management utility functions

local config = require("config")
local db = require("db")
local bit32 = require("bit32")
local bit128 = require("bit128")

local network = require("network")

function gateway.allocateIpv4()
	
	-- come up with random ipv4 based on settings in config
	local subnet, err = network.parseIpv4Subnet(config.gateway.subscriberIpv4subnet)
	local prefixIp, cidr = unpack(subnet)
	if err then
		return nil, "Failed to parse subscriberIpv4subnet"
	end
	
	local gatewayIp, err = network.parseIpv4(config.gateway.subscriberIpv4gateway)
	if err then
		return nil, "Failed to parse subscriberIpv4gateway"
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
		if session and ip == gatewayIp then
			randomAddr = randomAddr+1
		else
			return {ip, cidr}, nil
		end
	end
	
	return nil, "Failed to allocate IPv4"
end

function gateway.allocateIpv6()
	
	if not config.gateway.subscriberIpv6subnet or not config.gateway.subscriberIpv6gateway then
		return nil, nil
	end
	
	local gatewayIp, err = network.parseIpv6(config.gateway.subscriberIpv6gateway)
	if err then
		return nil, "Failed to parse subscriberIpv6gateway"
	end
	gatewayIp = network.ip2string(gatewayIp)
	
	-- come up with random ipv4 based on settings in config
	local subnet, err = network.parseIpv6Subnet(config.gateway.subscriberIpv6subnet)
	local prefixIp, cidr = unpack(subnet)
	if err then
		return nil, "Failed to parse subscriberIpv6subnet"
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
			return {ip, cidr}, nil
		end
	end
	
	return nil, "Failed to allocate IPv6"
end

function gateway.allocateSid(suggesteredSid)
	
	-- come up with unused session id
	
	-- TODO: fix race condition
	
	if suggesteredSid == nil then
		local sidchars = "1234567890abcdefghijklmnopqrstuvwxyz"
		local sid = ""
		for t=0,5 do
			for i=1,32 do
				local char = math.random(1,string.len(sidchars))
				sid = sid .. string.sub(sidchars,char,char)
			end
			if db.lookupSession(sid) ~= nil then
				sid = ""
			else
				break
			end
		end
		if sid == "" then
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
