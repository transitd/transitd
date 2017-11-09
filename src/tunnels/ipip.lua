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
	local subnet4, err = network.parseIpv4Subnet(config.ipip.ipv4subnet)
	if err then
		response.success = false response.errorMsg = "Failed to parse config.ipip.ipv4subnet: "..err return response
	end
	local gatewayIp4, err = network.parseIpv4(config.ipip.ipv4gateway)
	if err then
		response.success = false response.errorMsg = "Failed to parse config.ipip.ipv4subnet" return response
	end
	subnet4, err = gateway.allocateIpv4(subnet4, gatewayIp4)
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
		local subnet6, err = network.parseIpv6Subnet(config.ipip.ipv6subnet)
		if err then
			response.success = false response.errorMsg = "Failed to parse config.ipip.ipv6subnet: "..err return response
		end
		local gatewayIp6, err = network.parseIpv6(config.ipip.ipv6gateway)
		if err then
			response.success = false response.errorMsg = "Failed to parse config.ipip.ipv6subnet" return response
		end
		subnet6, err = gateway.allocateIpv6(subnet6, gatewayIp6)
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
	
	local result, err = ipip.gatewaySubscriberSetup(session)
	if err or not result then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "requestConnectionCommit", ["request"] = request, ["response"] = response, error = err})
	end
	
	if result then
		if result.interface4 and result.interface4.name then response.interface4 = result.interface4.name end
		if result.interface6 and result.interface6.name then response.interface6 = result.interface6.name end
	end
	
	response.success = true
	
	return response
end

function ipip.requestConnectionAbort(request, response)
	
	if response.interface4 or response.interface6 then
		
		local session, err = db.lookupSession(request.sid)
		if err then
			threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "requestConnectionAbort", ["request"] = request, ["response"] = response, error = err})
		end
		
		local result, err = ipip.gatewaySubscriberTeardown(session)
		if err then
			threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "requestConnectionAbort", ["request"] = request, ["response"] = response, error = err})
		end
		
	end
	
	response.ipv4 = nil
	response.cidr4 = nil
	response.ipv4gateway = nil
	response.ipv6 = nil
	response.cidr6 = nil
	response.ipv6gateway = nil
	response.interface4 = nil
	response.interface6 = nil
	
	return response
end

function ipip.releaseConnection(request, response)
	
	local session, err = db.lookupSession(request.sid)
	if err then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "releaseConnection", ["request"] = request, ["response"] = response, error = err})
	end
	
	local result, err = ipip.gatewaySubscriberTeardown(session)
	if err or not result then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "releaseConnection", ["request"] = request, ["response"] = response, error = err})
	end
	
	if result then
		if result.interface4 and result.interface4.name then response.interface4 = result.interface4.name end
		if result.interface6 and result.interface6.name then response.interface6 = result.interface6.name end
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
	
	if result then
		if result.interface4 and result.interface4.name then response.interface4 = result.interface4.name end
		if result.interface6 and result.interface6.name then response.interface6 = result.interface6.name end
	end
	
	response.success = true
	
	return response
end

function ipip.connectAbort(request, response)
	
	local result, err = ipip.subscriberTeardown(request.sid)
	if err or not result then
		threadman.notify({type = "error", module = "tunnels.ipip", ["function"] = "connectAbort", ["request"] = request, ["response"] = response, error = err})
	end
	
	if result then
		if result.interface4 and result.interface4.name then response.interface4 = result.interface4.name end
		if result.interface6 and result.interface6.name then response.interface6 = result.interface6.name end
	end
	
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
	
	local result = {}
	
	local remoteIp, err = network.parseIp(session.meshIP)
	local localIp, err = networkModule.getMyIp()
	if err then return nil, err end
	if not localIp then return nil, "Failed to get IP from network module" end
	localIp, err = network.parseIp(localIp)
	if err then return nil, err end
	if not localIp then return nil, "Failed to parse IP from network module" end
	
	local tunnelMode = "ipip"
	if #remoteIp > 4 then tunnelMode = "ipip6" end
	
	local interfaceName = "ipip" .. string.sub(session.sid,1,6)
	
	local res, err = network.setupTunnel(interfaceName, tunnelMode, remoteIp, localIp)
	if err then return nil, "Failed to set up "..tunnelMode.." tunnel: "..err end
	if not res then return nil, "Failed to set up "..tunnelMode.." tunnel" end
	
	local interface, err = network.getInterface(interfaceName)
	if err then return nil, "Failed to query "..interfaceName.." interface: "..err end
	if not interface then return nil, "Failed to query "..interfaceName.." interface" end
	
	local res, err = db.registerSessionIpipInterface(session.sid, interfaceName)
	if err then return nil, "Failed to save session ipip interface name '"..interfaceName.."' in database: "..err end
	if not res then return nil, "Failed to save session ipip interface name '"..interfaceName.."' in database" end
	
	local res, err = network.upInterface(interfaceName)
	if err then return nil, "Failed to bring up "..interfaceName.." tunnel: "..err end
	if not res then return nil, "Failed to bring up "..interfaceName.." tunnel" end
	
	if config.ipip.ipv4subnet and config.ipip.ipv4gateway then
		
		local subnet4, err = network.parseIpv4Subnet(config.ipip.ipv4subnet)
		if err then
			return nil, "Failed to parse config.ipip.ipv4subnet: "..err
		end
		local gatewayIp4, err = network.parseIpv4(config.ipip.ipv4gateway)
		if err then
			return nil, "Failed to parse config.ipip.ipv4subnet"
		end
		subnet4, err = gateway.interfaceSetup4(mode, interface, subnet4, gatewayIp4)
		if err then return nil, "Failed to set up routing:"..err end
		if not subnet4 then return nil, "Failed to set up routing" end
		
		result.interface4 = interface
		
	end
	
	if config.gateway.ipv6support == "yes" and config.ipip.ipv6subnet and config.ipip.ipv6gateway then
		
		local subnet6, err = network.parseIpv6Subnet(config.ipip.ipv6subnet)
		if err then
			return nil, "Failed to parse config.ipip.ipv6subnet: "..err
		end
		local gatewayIp6, err = network.parseIpv6(config.ipip.ipv6gateway)
		if err then
			return nil, "Failed to parse config.ipip.ipv6subnet"
		end
		subnet6, err = gateway.interfaceSetup6(mode, interface, subnet6, gatewayIp6)
		if err then return nil, "Failed to set up routing:"..err end
		if not subnet6 then return nil, "Failed to set up routing" end
		
		result.interface6 = interface
		
	end
	
	return result, nil
end

function ipip.gatewaySubscriberTeardown(session)
	
	local result = {}
	
	local interfaceName, err = db.getSessionIpipInterface(session.sid)
	if err then return nil, "Failed to get session ipip interface name: "..err end
	if not interfaceName then return nil, "Failed to get session ipip interface name" end
	
	local interface, err = network.getInterface(interfaceName)
	if err then return nil, "Failed to query "..interfaceName.." interface: "..err end
	if not interface then return nil, "Failed to query "..interfaceName.." interface" end
	
	subnet4, err = network.parseIpv4Subnet(config.ipip.ipv4subnet)
	if err then
		return nil, "Failed to parse IPv4 subnet: "..err
	end
	
	if subnet4 then
		
		local res, err = gateway.interfaceTeardown4(interface, subnet4)
		if err then return nil, "Failed to tear down gateway subscriber:"..err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
		
		result.interface4 = interface
		
	end
	
	if subnet6 then
		
		local res, err = gateway.interfaceTeardown6(interface, subnet6)
		if err then return nil, err end
		if not res then return nil, "Failed to tear down gateway subscriber" end
		
		result.interface6 = interface
		
	end
	
	if interface then
		
		local res, err = network.downInterface(interface.name)
		if err then return nil, "Failed to bring down interface "..interface.name..":"..err end
		if not res then return nil, "Failed to bring down interface "..interface.name end
		
		local res, err = network.teardownTunnel(interface.name)
		if err then return nil, "Failed to tear down ipip tunnel:"..err end
		if not res then return nil, "Failed to tear down ipip tunnel" end
		
	end
	
	return result, nil
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
	
	local result = {}
	
	local remoteIp, err = network.parseIp(session.meshIP)
	local localIp, err = networkModule.getMyIp()
	if err then return nil, err end
	if not localIp then return nil, "Failed to get IP from network module" end
	localIp, err = network.parseIp(localIp)
	if err then return nil, err end
	if not localIp then return nil, "Failed to parse IP from network module" end
	
	local tunnelMode = "ipip"
	if #remoteIp > 4 then tunnelMode = "ipip6" end
	
	local interfaceName = "ipip" .. string.sub(session.sid,1,6)
	
	local res, err = network.setupTunnel(interfaceName, tunnelMode, remoteIp, localIp)
	if err then return nil, "Failed to set up "..tunnelMode.." tunnel: "..err end
	if not res then return nil, "Failed to set up "..tunnelMode.." tunnel" end
	
	local interface, err = network.getInterface(interfaceName)
	if err then return nil, "Failed to query "..interfaceName.." interface: "..err end
	if not interface then return nil, "Failed to query "..interfaceName.." interface" end
	
	local res, err = db.registerSessionIpipInterface(session.sid, interfaceName)
	if err then return nil, "Failed to save session ipip interface name '"..interfaceName.."' in database: "..err end
	if not res then return nil, "Failed to save session ipip interface name '"..interfaceName.."' in database" end
	
	local res, err = network.upInterface(interfaceName)
	if err then return nil, "Failed to bring up "..interfaceName.." tunnel: "..err end
	if not res then return nil, "Failed to bring up "..interfaceName.." tunnel" end
	
	if session.internetIPv4 and session.internetIPv4cidr then
		
		subnet4, err = network.parseIpv4Subnet(session.internetIPv4.."/"..session.internetIPv4cidr)
		if err then
			return nil, "Failed to parse IPv4 subnet: "..err
		end
		
		-- set up interface ip address
		local res, err = network.setInterfaceIp(interface, subnet4)
		if err then
			return nil, "Failed to set local IPv4 address: "..err
		end
		
		result.interface4 = interface
		
		if mode == "route" then
			
			-- interface data changed, update it
			interface, err = network.getInterface(interfaceName)
			
			local gatewayIp4 = nil
			
			if session.internetIPv4gateway then
				gatewayIp4, err = network.parseIpv4(session.internetIPv4gateway)
				if err then
					return nil, "Failed to parse gateway IP"
				end
			end
			
			-- configure default route
			local res, err = network.setDefaultRoute(interface, false, gatewayIp4)
			if err then return nil, err end
			
		end
		
	end
	
	if session.internetIPv6 and session.internetIPv6cidr then
		
		subnet6, err = network.parseIpv6Subnet(session.internetIPv6.."/"..session.internetIPv6cidr)
		if err then
			return nil, "Failed to parse IPv6 subnet: "..err
		end
		
		-- set up interface ip address
		local res, err = network.setInterfaceIp(interface, subnet6)
		if err then
			return nil, "Failed to set local IPv6 address: "..err
		end
		
		result.interface6 = interface
		
		if mode == "route" then
			
			-- interface data changed, update it
			interface, err = network.getInterface(interfaceName)
			
			local gatewayIp6 = nil
			
			if session.internetIPv6gateway then
				gatewayIp6, err = network.parseIpv6(session.internetIPv6gateway)
				if err then
					return nil, "Failed to parse gateway IPv6"
				end
			end
			
			-- configure default route
			local res, err = network.setDefaultRoute(interface, true, gatewayIp6)
			if err then return nil, err end
			
		end
		
	end
	
	return result, nil
end

function ipip.subscriberTeardown(sid)
	
	local result = {}
	
	local interfaceName, err = db.getSessionIpipInterface(sid)
	if err then return nil, "Failed to get session ipip interface name: "..err end
	if not interfaceName then return nil, "Failed to get session ipip interface name" end
	
	local interface, err = network.getInterface(interfaceName)
	if err then return nil, "Failed to query "..interfaceName.." interface: "..err end
	if not interface then return nil, "Failed to query "..interfaceName.." interface" end
	
	local res, err = network.downInterface(interface.name)
	if err then return nil, "Failed to bring down interface "..interfaceName..":"..err end
	if not res then return nil, "Failed to bring down interface "..interfaceName end
	
	local res, err = network.teardownTunnel(interface.name)
	if err then return nil, "Failed to tear down ipip tunnel:"..err end
	if not res then return nil, "Failed to tear down ipip tunnel" end
	
	-- TODO: fix
	result.interface4 = interface;
	result.interface6 = interface;
	
	return result, nil
end


return ipip
