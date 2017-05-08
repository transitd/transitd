--[[
@file cjdns.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module cjdns
local cjdns = {}

local config = require("config")
local network = require("network")

function cjdns.getName()
	return "cjdns"
end

function cjdns.checkSupport(network, tunnel, payment)
	local interface, err = cjdns.getInterface()
	local myip, err = cjdns.getMyIp()
	return not err and interface and myip
	and config.cjdns.gatewaySupport == "yes"
end

function cjdns.getInterface()
	-- figure out what the cjdns network interface is
	local cjdnsPrefix, err = network.parseIpv6Subnet(config.cjdns.network)
	if err then
		return nil, "Failed to determine cjdns network prefix: "..err
	end
	local interface, err = network.getInterfaceBySubnet(cjdnsPrefix)
	if err then
		return nil, "Failed to determine cjdns network interface: "..err
	end
	if not interface then
		return nil, "Failed to determine cjdns network interface"
	end
	
	return interface
end

package.path = package.path .. ";cjdnstools/contrib/lua/?.lua"

local cjdnstools = require("cjdns.init")
local addrcalc = require("cjdns.addrcalc")

local cjdnsaiobj = nil
local cjdnsconfobj = nil
function cjdns.getAI()
	if not cjdnsaiobj then
		require "cjdns.config" -- ConfigFile null in certain cases?
		local cjdnsconfobj = cjdnstools.ConfigFile.new(get_path_from_path_relative_to_config(config.cjdns.config))
		cjdnsaiobj = cjdnsconfobj:makeInterface()
	end
	return cjdnsaiobj
end

function cjdns.getLinks(ip)
	
	local ai = cjdns.getAI()
	local response, err = ai:auth({
			q = "NodeStore_nodeForAddr",
			ip = ip,
		})
	if err then
		return nil, err
	end
	
	if response.result == nil or response.result.linkCount == nil then
		return nil, "Unexpected response from cjdns"
	end
	
	local list = {}
	for i=0,response.result.linkCount-1 do
		local response, err = ai:auth({
				q = "NodeStore_getLink",
				parent = ip,
				linkNum = i
			})
		if not err and response and response.result and response.result.child then
			local pubkey = string.gmatch(response.result.child, ".*[^%w%d]([%w%d]+\.k).*")()
			local status, ip = pcall(addrcalc.pkey2ipv6,pubkey);
			if status then
				local ip, err = network.canonicalizeIp(ip)
				if not err and ip then
					table.insert(list, ip)
				end
			end
		end
	end
	
	return list, nil
end

function cjdns.getMyKey()
	
	local ai = cjdns.getAI()
	local response, err = ai:auth({
			q = "NodeStore_nodeForAddr",
		})
	if err then
		return nil, "Error getting node data: " .. err
	elseif response and response.result and response.result.key then
		return response.result.key, nil
	else
		return nil, "Unknown error"
	end
end

function cjdns.getKeyForIp(ip)
	
	local ai = cjdns.getAI()
	local response, err = ai:auth({
			q = "NodeStore_nodeForAddr",
			["ip"] = ip
		})
	if err then
		return nil, "Error getting node data: " .. err
	elseif response and response.result and response.result.key then
		return response.result.key, nil
	else
		return nil, "Unknown error"
	end
end

function cjdns.getMyIp()
	local key, err = cjdns.getMyKey()
	if err then
		return nil, "Error getting key: " .. err
	else
		local status, ip = pcall(addrcalc.pkey2ipv6,key);
		if status then
			return ip, nil
		else
			print("Error converting public key to IPv6 address: " .. ip)
		end
	end
end

function cjdns.connectInit(request, response)
	
	response.networkLocalIp = cjdns.getMyIp()
	response.networkRemoteIp = request.ip
	
	response.success = true
	
	return response
end

return cjdns
