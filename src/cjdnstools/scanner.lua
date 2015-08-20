
--- @module cjdnstools.scanner
local scanner = {}

local config = require("config")

package.path = package.path .. ";cjdns/contrib/lua/?.lua"

local cjdns = require "cjdns.init"
local addrcalc = require "cjdnstools.addrcalc"

local conf = cjdns.ConfigFile.new(config.cjdns.config)
local ai = conf:makeInterface()

local socket = require("socket")

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
			if not err and response and response.result and response.result.child and response.result.isOneHop == 1 then
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
					print("Error: " .. newip)
				end
			end
		end
	end
end

function scanner.scan(callback)
	
	visitNode()
	
	local ip = next(newNodes)
	while ip ~= nil do
		
		callback(ip)
		
		-- wait 3 seconds
		socket.select(nil, nil, 3)
		
		visitNode(ip)
		
		ip = next(newNodes)
		
		print("Visited nodes " .. visitedNodesCount .. ", new nodes " .. newNodesCount)
	end
	
	print "Done scanning."
end

return scanner
