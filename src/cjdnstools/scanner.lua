
--- @module cjdnstools.scanner
local scanner = {}

local config = require("config")

package.path = package.path .. ";cjdnstools/contrib/lua/?.lua"

local cjdns = require "cjdns.init"
local addrcalc = require "cjdnstools.addrcalc"

require "cjdns.config" -- ConfigFile null in certain cases?
local conf = cjdns.ConfigFile.new(get_path_from_path_relative_to_config(config.cjdns.config))
local ai = conf:makeInterface()

local visitedNodes = {}
local visitedNodesCount = 0
local newNodes = {}
local newNodesCount = 0

local function visitNode(ip)
	ip = ip or 0
	
	print("Visiting node " .. ip)
	
	if ip ~= 0 then
		newNodes[ip] = nil
		newNodesCount = newNodesCount - 1
		visitedNodes[ip] = ip
		visitedNodesCount = visitedNodesCount + 1
	end
	
	local response, err = ai:auth({
			q = "NodeStore_nodeForAddr",
			ip = ip,
		})
	if err then
		print("Error getting data for " .. ip .. ": " .. err)
	elseif (response.result ~= nil) and (response.result.linkCount ~= nil) then
		print("Node " .. ip .. " has " .. response.result.linkCount .. " links")
		for i=0,response.result.linkCount-1 do
			local response, err = ai:auth({
					q = "NodeStore_getLink",
					parent = ip,
					linkNum = i
				})
			if not err and response and response.result and response.result.child then
				local pubkey = string.gmatch(response.result.child, ".*[^%w%d]([%w%d]+\.k).*")()
				local status, newip = pcall(addrcalc.pkey2ipv6,pubkey);
				if status then
					if (visitedNodes[newip] ~= nil) or (newNodes[newip] ~= nil) then
						print("Found already visited peer " .. newip)
					else
						print("Found a new peer " .. newip)
						newNodes[newip] = newip
						newNodesCount = newNodesCount + 1
					end
				else
					print("Error converting public key to IPv6 address: " .. newip)
				end
			end
		end
	end
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

function scanner.scan(callback)
	
	for k in next, newNodes do rawset(newNodes, k, nil) end
	for k in next, visitedNodes do rawset(visitedNodes, k, nil) end
	
	local myip, err = scanner.getMyIp()
	if err then
		print("Error getting node ip: " .. err)
	else
		newNodes[myip] = myip
	end
	
	local ip = next(newNodes)
	while ip ~= nil do
		
		callback(ip)
		
		visitNode(ip)
		
		ip = next(newNodes)
		
		print("Visited nodes " .. visitedNodesCount .. ", new nodes " .. newNodesCount)
	end
	
	print "Done scanning."
end

return scanner
