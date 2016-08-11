
--- @module cjdnstools.scanner
local scanner = {}

local config = require("config")
local network = require("network")

package.path = package.path .. ";cjdnstools/contrib/lua/?.lua"

local cjdns = require "cjdns.init"
local addrcalc = require "cjdns.addrcalc"

require "cjdns.config" -- ConfigFile null in certain cases?
local conf = cjdns.ConfigFile.new(get_path_from_path_relative_to_config(config.cjdns.config))
local ai = conf:makeInterface()

function scanner.getLinks(ip)
	
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

function scanner.getMyKey()
	local response, err = ai:auth({
			q = "NodeStore_nodeForAddr",
			ip = ip,
		})
	if err then
		return nil, "Error getting node data: " .. err
	elseif response and response.result and response.result.key then
		return response.result.key, nil
	else
		return nil, "Unknown error"
	end
end

function scanner.getMyIp()
	local key, err = scanner.getMyKey()
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

return scanner
