
--- @module scanner
local scanner = {}

local config = require("config")
local rpc = require("rpc")
local cjdns_scanner = require("cjdnstools.scanner")
local tunnel = require("cjdnstools.tunnel")
local threadman = require("threadman")
local db = require("db")
local network = require("network")

local socket = require("socket")

function scanner.processPorts(ip, net, scanId)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then
		threadman.notify({type = "error", module = "scanner", error = err})
		return
	end
	
	local myip, err = cjdns_scanner.getMyIp()
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
		local gateway = rpc.getProxy(ip, port)
		local info, err = gateway.nodeInfo()
		if err then
			threadman.notify({type = "nodeInfoFailed", ["ip"] = ip, ["port"] = port, ["network"] = net, ["scanId"] = scanId, ["error"] = err})
		else
			if info.name then
				db.registerNode(info.name, ip, port)
				threadman.notify({type = "nodeFound", ["ip"] = ip, ["port"] = port, ["network"] = net, ["scanId"] = scanId})
				if info.methods then
					for k, m in pairs(info.methods) do
						-- register methods
						if m and m.name then
							db.registerGateway(info.name, ip, port, m.name)
							threadman.notify({type = "gatewayFound", ["ip"] = ip, ["port"] = port, ["method"] = m.name, ["network"] = net, ["scanId"] = scanId})
						end
					end
				end
			end
		end
	end
end

function scanner.processLinks(ip, net, scanId)
	if net == "cjdns" then
		local links, err = cjdns_scanner.getLinks(ip)
		if err then
			threadman.notify({type = "error", module = "scanner", error = "Failed to links for host: "..err})
			return
		end
		for k,newIp in pairs(links) do
			if newIp ~= ip then
				local result, err = db.addNetworkHost(net, newIp, scanId)
				if err then
					threadman.notify({type = "error", module = "scanner", error = "Failed to add network host: "..err})
				end
				local result, err = db.addNetworkLink(net, ip, newIp, scanId)
				if err then
					threadman.notify({type = "error", module = "scanner", error = "Failed to add network link: "..err})
				end
			end
		end
	end
end

function scanner.processHost(ip, net, scanId)
	threadman.notify({type = "info", module = "scanner", info = "Processing "..ip})
	scanner.processLinks(ip, net, scanId)
	scanner.processPorts(ip, net, scanId)
	local result, err = db.visitNetworkHost(net, ip, scanId)
	if err then
		threadman.notify({type = "error", module = "scanner", error = "Failed to mark host visited: "..err})
	end
	socket.sleep(tonumber(config.daemon.scanDelay))
end

function scanner.scan(net, scanId)
	
	if net == "cjdns" then
		local myip, err = cjdns_scanner.getMyIp()
		if err then
			threadman.notify({type = "error", module = "scanner", error = "Failed to get own IP: "..err})
			return
		end
		
		local myip, err = network.canonicalizeIp(myip)
		if err then
			threadman.notify({type = "error", module = "scanner", error = err})
			return
		end
		
		local result, err = db.addNetworkHost(net, myip, scanId)
		if err then
			threadman.notify({type = "error", module = "scanner", error = "Failed to add host: "..err})
			return
		end
		
		local host, err = db.getNextNetworkHost(net, scanId)
		while host do
			scanner.processHost(host.ip, net, scanId)
			host, err = db.getNextNetworkHost(net, scanId)
			if err then
				threadman.notify({type = "error", module = "scanner", error = "Failed to get next host: "..err})
				break
			end
			-- stop the scan if another scan has started
			local lastScanId, err = db.getLastScanId(net)
			if err then
				threadman.notify({type = "error", module = "scanner", error = "Failed to get scan id: "..err})
			end
			if lastScanId > scanId then break end
		end
	end
	
end

function scanner.startScan()
	
	local net = "cjdns"
	
	local lastScanId, err = db.getLastScanId(net)
	if err then
		return nil, err
	end
	
	if lastScanId == nil then
		lastScanId = 0
	else
		local isComplete, err = db.isScanComplete(net, lastScanId)
		if err then
			return nil, err
		end
		
		if not isComplete then
			scanner.stopScan()
			lastScanId = lastScanId + 1
		end
	end
	
	local scanId = lastScanId + 1
	
	threadman.startThreadInFunction('scanner', 'scan', net, scanId)
	
	return scanId, nil
end

function scanner.stopScan()
	
	local net = "cjdns"
	
	local lastScanId, err = db.getLastScanId(net)
	if err then
		return nil, err
	end
	
	local isComplete, err = db.isScanComplete(net, lastScanId)
	if err then
		return nil, err
	end
	
	if not isComplete then
		-- start another fake scan
		local result, err = db.addNetworkHost(net, "0.0.0.0", lastScanId+1)
		if err then
			return nil, err
		end
		
		local result, err = db.visitNetworkHost(net, "0.0.0.0", lastScanId+1)
		if err then
			return nil, err
		end
		
		local result, err = db.visitAllNetworkHosts(net, lastScanId)
		if err then
			return nil, err
		end
	end
	
	return true, nil
end

return scanner
