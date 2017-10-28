--[[
@file ipip.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module free
local ipip = {}

local config = require("config")
local db = require("db")
local gateway = require("gateway")
local shell = require("lib.shell")
local shrunner = require("shrunner")
local threadman = require("threadman")
local network = require("network")
local support = require("support")

function ipip.getName()
	return "IPIP"
end

function ipip.checkSupport(net, tun, pay)
	
	local check_support = function()
		local modules, err = io.open("/proc/modules", "r")
		if err then
			return nil, err
		end
		local support = false
		for l in modules:lines() do
			local modname = string.match(string.lower(l), "^%s*(%w+)%s*.*$")
			if modname == "ipip" then return true end
		end
		modules:close()
		return false
	end
	
	local load_support = function()
		local retval = shrunner.execute(shell.escape({"modprobe", "ipip"}))
		if retval ~= 0 then
			threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "checkSupport", error = "Failed to load ipip kernel module"})
			return false
		end
		return true
	end
	
	local support = check_support()
	if not support then
		if load_support() then support = check_support() end
	end
	
	return config.ipip.support == "yes"
		and tun and tun.module == "ipip"
		and support
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
	
	local result, err = ipip.gatewaySubscriberTeardown(session.sid)
	if err then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "requestConnectionCommit", ["request"] = request, ["response"] = response, error = err})
	end
	
	response.success = true
	
	return response
end

function ipip.connect(request, response)
	
	local session, err = db.lookupSession(request.sid)
	if err then
		response.success = false response.errorMsg = err return response
	end
	
	local result, err = ipip.subscriberSetup(session)
	if not result then
		if err then
			response.success = false response.errorMsg = err return response
		else
			response.success = false response.errorMsg = "Unknown error" return response
		end
	end
	
	if result.interface then
		response.interface4 = result.interface.name
		response.interface6 = result.interface.name
	end
	
	response.success = true
	
	return response
end

function ipip.connectAbort(request, response)
	
	local result, err = ipip.subscriberTeardown(request.sid)
	if err then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "connectAbort", ["request"] = request, ["response"] = response, error = err})
	end
	
	return response
end

function ipip.disconnect(request, response)
	
	local setup = tunnelSetup.tunnels[request.sid]
	
	if not setup then
		response.success = false response.errorMsg = err return response
	end
	
	if interface then
		response.interface4 = setup.interface
		response.interface6 = setup.interface
	end
	
	response.success = true
	
	return response
end

function ipip.disconnectCommit(request, response)
	
	local ret, err = ipip.subscriberTeardown(request.sid)
	if err then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "disconnect", ["request"] = request, ["response"] = response, ["error"] = err})
	end
	
	response.success = true
	
	return response
	
end

function ipip.maintainConnection(session)
	
	-- TODO
	
	return true, nil
end

local tunnelSetup = { count = 0, tunnels = {} }

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
	
	local tunnelMode = "ipip"
	if #remoteIp > 4 then tunnelMode = "ipip6" end
	
	local interfaceName = "ipip" .. tostring(tunnelSetup.count+1)
	
	local res, err = network.setupTunnel(interfaceName, tunnelMode, remoteIp, localIp)
	if err then return nil, "Failed to set up "..tunnelMode.." tunnel: "..err end
	if not res then return nil, "Failed to set up "..tunnelMode.." tunnel" end
	
	local setup, interface
	
	interface, err = network.getInterface(interfaceName)
	if err then return nil, "Failed to query "..interfaceName.." interface: "..err end
	if not interface then return nil, "Failed to query "..interfaceName.." interface" end
	
	setup.interface = interface
	
	local res, err = network.upInterface(interfaceName)
	if err then return nil, "Failed to bring up "..interfaceName.." tunnel: "..err end
	if not res then return nil, "Failed to bring up "..interfaceName.." tunnel" end
	
	if session.internetIPv4 then
		
		local subnet4, err = gateway.interfaceSetup4(mode, interface, config.ipip.ipv4subnet, config.ipip.ipv4gateway)
		if err then return nil, "Failed to set up routing:"..err end
		if not subnet4 then return nil, "Failed to set up routing" end
		
		setup.subnet4 = subnet4
		
	end
	
	if config.gateway.ipv6support == "yes" and session.internetIPv6 then
		
		local subnet6, err = gateway.interfaceSetup6(mode, interface, config.ipip.ipv6subnet, config.ipip.ipv6gateway)
		if err then return nil, "Failed to set up routing:"..err end
		if not subnet6 then return nil, "Failed to set up routing" end
		
		setup.subnet6 = subnet6
		
	end
	
	tunnelSetup.count = tunnelSetup.count + 1
	tunnelSetup.tunnels[session.sid] = setup
	
	return setup, nil
end

function ipip.gatewaySubscriberTeardown(sid)
	
	local setup = tunnelSetup.tunnels[sid]
	
	if setup and setup.subnet4 then
		
		local res, err = gateway.interfaceTeardown4(setup.interface)
		if err then return nil, "Failed to tear down gateway subscriber:"..err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
	end
	
	if setup and setup.subnet6 then
		
		local res, err = gateway.interfaceTeardown6(setup.interface, setup.subnet6)
		if err then return nil, err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
		
	end
	
	if setup and setup.interface then
		
		local res, err = network.downInterface(setup.interface.name)
		if err then return nil, "Failed to bring down interface "..setup.interface.name..":"..err end
		if not res then return nil, "Failed to bring down interface "..setup.interface.name end
		
		local res, err = network.teardownTunnel(setup.interface.name)
		if err then return nil, "Failed to tear down ipip tunnel:"..err end
		if not res then return nil, "Failed to tear down ipip tunnel" end
		
	end
	
	-- TODO: remove element from tunnelSetup
	
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
	
	local tunnelMode = "ipip"
	if #remoteIp > 4 then tunnelMode = "ipip6" end
	
	local interfaceName = "ipip" .. tostring(tunnelSetup.count+1)
	
	local res, err = network.setupTunnel(interfaceName, tunnelMode, remoteIp, localIp)
	if err then return nil, "Failed to set up "..tunnelMode.." tunnel: "..err end
	if not res then return nil, "Failed to set up "..tunnelMode.." tunnel" end
	
	local setup, interface
	
	interface, err = network.getInterface(interfaceName)
	if err then return nil, "Failed to query "..interfaceName.." interface: "..err end
	if not interface then return nil, "Failed to query "..interfaceName.." interface" end
	
	setup.interface = interface
	
	local res, err = network.upInterface(interfaceName)
	if err then return nil, "Failed to bring up "..interfaceName.." tunnel: "..err end
	if not res then return nil, "Failed to bring up "..interfaceName.." tunnel" end
	
	if session.internetIPv4 then
		
		subnet4, err = network.parseIpv4Subnet(session.internetIPv4.."/"..session.internetIPv4cidr)
		if err then
			return nil, "Failed to parse IPv4 subnet: "..err
		end
		
		-- set up interface ip address
		local res, err = network.setInterfaceIp(interface, subnet4)
		if err then
			return nil, "Failed to set local IPv4 address: "..err
		end
		
		setup.subnet4 = subnet4
		
		if mode == "route" then
			
			-- configure default route
			
			local res, err = network.setDefaultRoute(interface, false)
			if err then return nil, err end
			
		end
		
	end
	
	if session.internetIPv6 then
		
		subnet6, err = network.parseIpv6Subnet(session.internetIPv6.."/"..session.internetIPv6cidr)
		if err then
			return nil, "Failed to parse IPv6 subnet: "..err
		end
		
		-- set up interface ip address
		local res, err = network.setInterfaceIp(interface, subnet6)
		if err then
			return nil, "Failed to set local IPv6 address: "..err
		end
		
		setup.subnet6 = subnet6
		
		if mode == "route" then
			
			-- configure default route
			
			local res, err = network.setDefaultRoute(interface, true)
			if err then return nil, err end
			
		end
		
	end
	
	tunnelSetup.count = tunnelSetup.count + 1
	tunnelSetup.tunnels[session.sid] = setup
	
	return setup, nil
end

function ipip.subscriberTeardown(sid)
	
	local setup = tunnelSetup.tunnels[sid]
	
	if setup and setup.subnet4 then
		network.unsetDefaultRoute(false)
	end
	
	if setup and setup.subnet6 then
		network.unsetDefaultRoute(false)
	end
	
	if setup and setup.interface then
		
		local res, err = network.downInterface(setup.interface.name)
		if err then return nil, "Failed to bring down interface "..setup.interface.name..":"..err end
		if not res then return nil, "Failed to bring down interface "..setup.interface.name end
		
		local res, err = network.teardownTunnel(setup.interface.name)
		if err then return nil, "Failed to tear down ipip tunnel:"..err end
		if not res then return nil, "Failed to tear down ipip tunnel" end
		
	end
	
	-- TODO: remove element from tunnelSetup
	
	return true, nil
end


return ipip
