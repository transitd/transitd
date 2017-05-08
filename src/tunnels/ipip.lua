--[[
@file ipip.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module free
local ipip = {}

function ipip.getName()
	return "IPIP"
end

function ipip.checkSupport(net, tun, pay)
	
	local support = function()
		local modules, err = io.open("/proc/modules", "r")
		if err then
			return nil, err
		end
		local support = false
		for l in modules:lines() do
			local modname = string.match(string.lower(l), "^%s*(%w+)%s*$")
			if modname == "ipip" then return true end
		end
		modules:close()
		return false
	end
	
	return config.ipip.support == "yes"
		and tun and tun.module == "ipip"
		and support()
end

function ipip.requestConnection(request, response)
	
	-- allocate ips based on settings in config
	
	-- IPv4
	local subnet4, err = gateway.allocateIpv4(config.ipip.ipv4subnet, config.ipip.ipv4gateway);
	if err then
		response.success = false response.errorMsg = err return response
	end
	if not subnet4 then
		response.success = false response.errorMsg = "Failed to allocate IPv4 address" return response
	end
	response.ipv4, response.cidr4 = unpack(subnet4)
	response.ipv4gateway = config.ipip.ipv4gateway
	
	-- IPv6
	if config.gateway.ipv6support == "yes" then
		local subnet6, err = gateway.allocateIpv6(config.ipip.ipv6subnet, config.ipip.ipv6gateway);
		if err then
			response.success = false response.errorMsg = err return response
		end
		if not subnet6 then
			response.success = false response.errorMsg = "Failed to allocate IPv6 address" return response
		end
		response.ipv6, response.cidr6 = unpack(subnet6)
		response.ipv6gateway = config.ipip.ipv6gateway
	end
	
	local session, err = db.lookupSession(request.sid)
	if err then
		response.success = false response.errorMsg = err return response
	end
	
	response.success = true
	
	return response
end

function ipip.requestConnectionCommit(request, response)
	
	local session, err = db.lookupSession(request.sid)
	if not err and session then
		local result, err = ipip.gatewaySubscriberSetup(session)
		if err then
			threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "requestConnectionCommit", ["request"] = request, ["response"] = response, error = err})
		end
	end
	
	response.success = true
	
	return response
end

function ipip.releaseConnection(request, response)
	
	local session, err = db.lookupSession(request.sid)
	if err then
		response.success = false response.errorMsg = err return response
	end
	
	local result, err = ipip.gatewaySubscriberTeardown(session)
	if err then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "requestConnectionCommit", ["request"] = request, ["response"] = response, error = err})
	end
	
	response.success = true
	
	return response
end

function ipip.connect(request, response)
	response.success = false
	response.errorMsg = "Unimplemented"
end

function ipip.disconnect(request, response)
	response.success = false
	response.errorMsg = "Unimplemented"
end


function ipip.maintainConnection(session)
	
	-- TODO
	
	return true, nil
end

local tunnelSetup = { count = 0 }

function ipip.gatewaySubscriberSetup(session)
	
	local mode = config.ipip.routing
	
	local suite = session.suite
	
	local suites = support.getSuites()
	if not suites[suite]
	or not suites[suite].network
	or not suites[suite].network.module
	then
		return nil, "Suite not supported"
	end
	
	local networkModule = require("networks."..suites[suite].network.module)
	
	local remoteIp, err = network.parseIp(session.meshIP)
	local localIp, err = networkModule.getMyIp()
	
	local addrType = "4"
	if #remoteIp > 4 then addrType = "6" end
	
	local interfaceName4 = "ipip" .. tostring(tunnelSetup.count+1) .. "v4"
	local interfaceName6 = "ipip" .. tostring(tunnelSetup.count+1) .. "v6"
	
	local setup, interface4, interface6
	
	if session.internetIPv4 then
		
		local res, err = network.setupTunnel(interfaceName4, "ip4ip"..addrType, remoteIp, localIp)
		if err then return nil, "Failed to set up ip4ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to set up ip4ip"..addrType.." tunnel" end
		
		interface4, err = network.getInterface(interfaceName4)
		if err then return nil, "Failed to query ip4ip"..addrType.." interface: "..err end
		if not interface4 then return nil, "Failed to query ip4ip"..addrType.." interface" end
		
		setup.interface4 = interface4
		
		local res, err = network.upInterface(interface4)
		if err then return nil, "Failed to bring up ip4ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to bring up ip4ip"..addrType.." tunnel" end
		
		local subnet4, err = gateway.interfaceSetup4(mode, interface4, config.ipip.ipv4subnet, config.ipip.ipv4gateway)
		if err then return nil, "Failed to set up routing:"..err end
		if not subnet4 then return nil, "Failed to set up routing" end
		
		setup.subnet4 = subnet4
		
	end
	
	if config.gateway.ipv6support == "yes" and session.internetIPv6 then
		
		local res, err = network.setupTunnel(interfaceName6, "ip6ip"..addrType, remoteIp, localIp)
		if err then return nil, "Failed to set up ip6ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to set up ip6ip"..addrType.." tunnel" end
		
		interface6, err = network.getInterface(interfaceName6)
		if err then return nil, "Failed to query ip6ip"..addrType.." interface: "..err end
		if not interface6 then return nil, "Failed to query ip6ip"..addrType.." interface" end
		
		setup.interface6 = interface6
		
		local res, err = network.upInterface(interface6)
		if err then return nil, "Failed to bring up ip6ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to bring up ip6ip"..addrType.." tunnel" end
		
		local subnet6, err = gateway.interfaceSetup6(mode, interface6, config.ipip.ipv6subnet, config.ipip.ipv6gateway)
		if err then return nil, "Failed to set up routing:"..err end
		if not subnet6 then return nil, "Failed to set up routing" end
		
		setup.subnet6 = subnet6
		
	end
	
	tunnelSetup.count = tunnelSetup.count + 1
	tunnelSetup.tunnels[session.sid] = setup
	
	return setup, nil
end

function ipip.gatewaySubscriberTeardown(session)
	
	local setup = tunnelSetup.tunnels[session.sid]
	
	if setup and setup.subnet4 then
		
		local result, err = gateway.interfaceTeardown4(setup.interface4)
		if err then return nil, "Failed to tear down gateway subscriber:"..err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
	end
	
	if setup and setup.interface4 then
		
		local res, err = network.teardownTunnel(setup.interface4.name)
		if err then return nil, "Failed to tear down ipip tunnel:"..err end
		if not res then return nil, "Failed to tear down ipip tunnel" end
		
	end
	
	if setup and setup.subnet6 then
		
		local result, err = gateway.interfaceTeardown6(setup.interface, setup.subnet6)
		if err then return nil, err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
		
	end
	
	if setup and setup.interface6 then
		
		local res, err = network.teardownTunnel(setup.interface6.name)
		if err then return nil, "Failed to tear down ipip tunnel:"..err end
		if not res then return nil, "Failed to tear down ipip tunnel" end
		
	end
	
	return true, nil
end

function ipip.subscriberSetup(session)
	
	local mode = config.subscriber.routing
	
	if mode ~= "route" and mode ~= "none" then
		return nil, "Unknown subscriber routing mode"
	end
	
	local suite = session.suite
	
	local suites = support.getSuites()
	if not suites[suite]
	or not suites[suite].network
	or not suites[suite].network.module
	then
		return nil, "Suite not supported"
	end
	
	local networkModule = require("networks."..suites[suite].network.module)
	
	local remoteIp, err = network.parseIp(session.meshIP)
	local localIp, err = networkModule.getMyIp()
	
	local addrType = "4"
	if #remoteIp > 4 then addrType = "6" end
	
	local interfaceName4 = "ipip" .. tostring(tunnelSetup.count+1) .. "v4"
	local interfaceName6 = "ipip" .. tostring(tunnelSetup.count+1) .. "v6"
	
	local setup, interface4, interface6
	
	if session.internetIPv4 then
		
		local res, err = network.setupTunnel(interfaceName4, "ip4ip"..addrType, remoteIp, localIp)
		if err then return nil, "Failed to set up ip4ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to set up ip4ip"..addrType.." tunnel" end
		
		setup.interface4 = interface4
		
		interface4, err = network.getInterface(interfaceName4)
		if err then return nil, "Failed to query ip4ip"..addrType.." interface: "..err end
		if not interface4 then return nil, "Failed to query ip4ip"..addrType.." interface" end
		
		local res, err = network.upInterface(interface4)
		if err then return nil, "Failed to bring up ip4ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to bring up ip4ip"..addrType.." tunnel" end
		
		ipv4, err = network.parseIpv4(session.internetIPv4);
		if err then
			return nil, "Failed to parse IPv4 gateway: "..err
		end
		
		-- set up interface ip address
		local result, err = network.setInterfaceIp(interface4, {ipv4, cidr4})
		if err then
			return nil, "Failed to set local IPv4 address: "..err
		end
		
		if mode == "route" then
			
			-- configure default route
			
			local result, err = network.setDefaultRoute(interface, false)
			if err then return nil, err end
			
			if session.internetIPv6gateway then
				local result, err = network.setDefaultRoute(interface, true)
				if err then return nil, err end
			end
			
			setup.subnet4 = subnet4
			
		end
		
	end
	
	if config.gateway.ipv6support == "yes" and session.internetIPv6 then
		
		local res, err = network.setupTunnel(interfaceName6, "ip6ip"..addrType, remoteIp, localIp)
		if err then return nil, "Failed to set up ip6ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to set up ip6ip"..addrType.." tunnel" end
		
		setup.interface6 = interface6
		
		interface6, err = network.getInterface(interfaceName6)
		if err then return nil, "Failed to query ip6ip"..addrType.." interface: "..err end
		if not interface6 then return nil, "Failed to query ip6ip"..addrType.." interface" end
		
		local res, err = network.upInterface(interface6)
		if err then return nil, "Failed to bring up ip6ip"..addrType.." tunnel: "..err end
		if not res then return nil, "Failed to bring up ip6ip"..addrType.." tunnel" end
		
		local subnet6, err = gateway.interfaceSetup6(mode, interface6, config.ipip.ipv6subnet, config.ipip.ipv6gateway)
		if err then return nil, "Failed to set up routing:"..err end
		if not subnet6 then return nil, "Failed to set up routing" end
		
		setup.subnet6 = subnet6
		
	end
	
	tunnelSetup.count = tunnelSetup.count + 1
	tunnelSetup.tunnels[session.sid] = setup
	
	return setup, nil
end

function ipip.gatewaySubscriberTeardown(session)
	
	local setup = tunnelSetup.tunnels[session.sid]
	
	if setup and setup.subnet4 then
		
		local result, err = gateway.interfaceTeardown4(setup.interface4)
		if err then return nil, "Failed to tear down gateway subscriber:"..err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
	end
	
	if setup and setup.interface4 then
		
		local res, err = network.teardownTunnel(setup.interface4.name)
		if err then return nil, "Failed to tear down ipip tunnel:"..err end
		if not res then return nil, "Failed to tear down ipip tunnel" end
		
	end
	
	if setup and setup.subnet6 then
		
		local result, err = gateway.interfaceTeardown6(setup.interface, setup.subnet6)
		if err then return nil, err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
		
	end
	
	if setup and setup.interface6 then
		
		local res, err = network.teardownTunnel(setup.interface6.name)
		if err then return nil, "Failed to tear down ipip tunnel:"..err end
		if not res then return nil, "Failed to tear down ipip tunnel" end
		
	end
	
	return true, nil
end


return ipip
