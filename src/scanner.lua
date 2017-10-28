--[[
@file scanner.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module scanner
local scanner = {}

local config = require("config")
local rpc = require("rpc")
local threadman = require("threadman")
local db = require("db")
local network = require("network")
local support = require("support")

local socket = require("socket")

function scanner.processPorts(ip, net, scanId)
	
	local module = require("networks."..net.module)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then
		threadman.notify({type = "error", module = "scanner", error = err})
		return
	end
	
	local myip, err = module.getMyIp()
	if err then
		threadman.notify({type = "error", module = "scanner", error = "Failed to get own IP: "..err})
		return
	end
	local myip, err = network.canonicalizeIp(myip)
	if err then
		threadman.notify({type = "error", module = "scanner", error = err})
		return
	end
	
	-- ignore self
	if ip == myip then
		return
	end
	
	ports = {}
	for port in string.gmatch(config.daemon.scanports, "%d+") do 
		local port = tonumber(port)
		local proxy = rpc.getProxy(ip, port)
		local info, err = proxy.nodeInfo()
		if err then
			threadman.notify({type = "nodeInfoFailed", ["ip"] = ip, ["port"] = port, ["network"] = net, ["scanId"] = scanId, ["error"] = err})
		else
			if info.name then
				db.registerNode(info.name, ip, port)
				threadman.notify({type = "nodeFound", ["ip"] = ip, ["port"] = port, ["network"] = net, ["scanId"] = scanId})
				if info.suites then
					for id, suite in pairs(info.suites) do
						-- register suites
						if suite.id then
							db.registerGateway(info.name, ip, port, suite.id)
							threadman.notify({type = "gatewayFound", ["ip"] = ip, ["port"] = port, ["suite"] = suite.id, ["network"] = net, ["scanId"] = scanId})
						end
					end
				end
			end
		end
	end
end

function scanner.processLinks(ip, net, scanId)
	
	local module = require("networks."..net.module)
	
	local links, err = module.getLinks(ip)
	if err then
		threadman.notify({type = "error", module = "scanner", error = "Failed to links for host: "..err})
		return
	end
	for k,newIp in pairs(links) do
		if newIp ~= ip then
			local result, err = db.addNetworkHost(net.module, newIp, scanId)
			if err then
				threadman.notify({type = "error", module = "scanner", error = "Failed to add network host: "..err})
			end
			local result, err = db.addNetworkLink(net.module, ip, newIp, scanId)
			if err then
				threadman.notify({type = "error", module = "scanner", error = "Failed to add network link: "..err})
			end
		end
	end
	
end

function scanner.processHost(ip, net, scanId)
	
	threadman.notify({type = "info", ["module"] = "scanner", info = "Processing "..ip})
	
	scanner.processLinks(ip, net, scanId)
	scanner.processPorts(ip, net, scanId)
	
	local result, err = db.visitNetworkHost(net.module, ip, scanId)
	if err then
		threadman.notify({type = "error", ["module"] = "scanner", error = "Failed to mark host visited: "..err})
	end
	
	socket.sleep(tonumber(config.daemon.scanDelay))
end

function scanner.run()
	
	local listener = threadman.registerListener("scanner", {"exit"})
	
	local exit = false;
	while not exit do
		
		local numhosts = 0
		
		local networks = support.getNetworks()
		for netmod,net in pairs(networks) do
			
			local msg = "";
			while msg ~= nil do
				msg = listener:listen(true)
				if msg ~= nil then
					if msg["type"] == "exit" then
						exit = true;
					end
				end
			end
			if exit then break end
			
			local scanId, err = db.getLastScanId(netmod)
			if err then
				threadman.notify({type = "error", ["module"] = "scanner", error = "Failed to get scan id: "..err})
			end
			
			if scanId then
				
				local host, err = db.getNextNetworkHost(netmod, scanId)
				if err then
					threadman.notify({type = "error", ["module"] = "scanner", error = "Failed to get next host: "..err})
					break
				end
				
				if host then
					scanner.processHost(host.ip, net, scanId)
					numhosts = numhosts + 1
				end
			else
				
				-- start scan if none were done
				scanner.startScan()
				
			end
			
		end
		
		-- sleep if there are no more hosts to scan
		if numhosts == 0 then
			socket.sleep(1)
		end
	end
	
	threadman.unregisterListener(listener)
end

function scanner.startScan()
	
	for netmod,net in pairs(support.getNetworks()) do
		
		local module = require("networks."..net.module)
		
		local scanId = 1
		
		local lastScanId, err = db.getLastScanId(netmod)
		if err then
			threadman.notify({type = "error", ["module"] = "scanner", ["netmod"] = netmod, error = err})
			break
		end
		
		local isComplete = true
		
		if lastScanId then
			isComplete, err = db.isScanComplete(netmod, lastScanId)
			if err then
				threadman.notify({type = "error", ["module"] = "scanner", ["netmod"] = netmod, error = err})
				break
			end
		end
		
		if isComplete then
			
			if lastScanId then
				scanId = lastScanId + 1
			end
			
			local myip, err = module.getMyIp()
			if err then
				threadman.notify({type = "error", ["module"] = "scanner", ["netmod"] = netmod, ["error"] = "Failed to get own IP: "..err})
				break
			end
			
			local result, err = db.addNetworkHost(netmod, myip, scanId)
			if err then
				threadman.notify({type = "error", ["module"] = "scanner", ["netmod"] = netmod, ["error"] = "Failed to add host: "..err})
				break
			end
			
		end
		
	end
	
	return true, nil
end

function scanner.stopScan()
	
	for netmod,net in pairs(support.getNetworks()) do
		
		local lastScanId, err = db.getLastScanId(netmod)
		if err then
			return nil, err
		end
		
		if lastScanId then
			local isComplete, err = db.isScanComplete(netmod, lastScanId)
			if err then
				return nil, err
			end
			
			if not isComplete then
				-- start another fake scan and complete it so the current scan will be abandoned
				local result, err = db.addNetworkHost(netmod, "0.0.0.0", lastScanId+1)
				if err then
					return nil, err
				end
				local result, err = db.visitNetworkHost(netmod, "0.0.0.0", lastScanId+1)
				if err then
					return nil, err
				end
				
				local result, err = db.visitAllNetworkHosts(netmod, lastScanId)
				if err then
					return nil, err
				end
			end
		end
		
	end
	
	return true, nil
end


return scanner
