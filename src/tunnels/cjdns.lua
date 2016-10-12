--[[
@file cjdns.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module cjdns
local cjdns = {}

local config = require("config")
local db = require("db")
local cjdnsNet = require("networks.cjdns")
local gateway = require("gateway")
local shell = require("lib.shell")

function cjdns.getName()
	return "cjdns tunnel"
end

function cjdns.checkSupport(network, tunnel, payment)
	local interface, err = cjdnsNet.getInterface()
	return
		not err and interface
		and config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes"
		and network and network.module == "cjdns"
end

local threadman = require("threadman")
local rpc = require("rpc")
local network = require("network")

function cjdns.requestConnection(request, response)
	
	if not request.options or not request.options.key then
		response.success = false response.errorMsg = "Key option is required" return response
	end
	
	local key = tostring(request.options.key)
	-- TODO: check to make sure key is a valid cjdns key (for example, by converting it to cjdns ip addr)
	if not key then
		response.success = false response.errorMsg = "Key option is required" return response
	end
	
	local mykey, err = cjdnsNet.getMyKey()
	if err then
		response.success = false response.errorMsg = "Failed to get my own key: " .. err return response
	elseif mykey == nil then
		response.success = false response.errorMsg = "Failed to get my own key: Unknown error" return response
	end
	
	response.key = mykey
	
	-- allocate ips based on settings in config
	
	-- IPv4
	local subnet4, err = gateway.allocateIpv4(config.cjdns.ipv4subnet, config.cjdns.ipv4gateway);
	if err then
		response.success = false response.errorMsg = err return response
	end
	if not subnet4 then
		response.success = false response.errorMsg = "Failed to allocate IPv4 address" return response
	end
	response.ipv4, response.cidr4 = unpack(subnet4)
	response.ipv4gateway = config.cjdns.ipv4gateway
	
	-- IPv6
	if config.gateway.ipv6support == "yes" then
		local subnet6, err = gateway.allocateIpv6(config.cjdns.ipv6subnet, config.cjdns.ipv6gateway);
		if err then
			response.success = false response.errorMsg = err return response
		end
		if not subnet6 then
			response.success = false response.errorMsg = "Failed to allocate IPv6 address" return response
		end
		response.ipv6, response.cidr6 = unpack(subnet6)
		response.ipv6gateway = config.cjdns.ipv6gateway
	end
	
	local interface, err = cjdnsNet.getInterface()
	if interface then response.interface = interface.name end
	
	response.success = true
	
	return response
end

function cjdns.requestConnectionAbort(request, response)
	response.key = nil
	response.ipv4 = nil
	response.cidr4 = nil
	response.ipv4gateway = nil
	response.ipv6 = nil
	response.cidr6 = nil
	response.ipv6gateway = nil
	response.interface = nil
	return response
end

function cjdns.requestConnectionCommit(request, response)
	
	db.registerSubscriberSessionCjdnsKey(request.sid, request.options.key)
	
	local result, err = cjdns.addKey(response.key, response.ipv4, response.ipv6)
	if err then
		threadman.notify({type = "error", module = "tunnels.cjdns", ["function"] = "requestConnectionCommit", ["request"] = request, ["response"] = response, error = err})
	end
	
	response.success = true
	
	return response
end

function cjdns.releaseConnection(request, response)
	
	local key, err = db.getCjdnsSubscriberKey(request.sid)
	if err then
		threadman.notify({type = "error", module = "tunnels.cjdns", ["function"] = "releaseConnection", ["request"] = request, ["response"] = response, error = err})
		response.success = false response.errorMsg = "Error releasing connection: " .. err return response
	end
	
	local interface, err = cjdnsNet.getInterface()
	if interface then response.interface = interface.name end
	
	local mykey, err = cjdnsNet.getMyKey()
	if err then
		response.success = false response.errorMsg = "Failed to get my own key: " .. err return response
	elseif mykey == nil then
		response.success = false response.errorMsg = "Failed to get my own key: Unknown error" return response
	end
	
	response.key = mykey
	
	response.success = true
	
	return response
end

function cjdns.releaseConnectionCommit(request, response)
	
	local result, err = cjdns.deauthorizeKey(key)
	if err then
		threadman.notify({type = "error", module = "tunnels.cjdns", ["function"] = "releaseConnectionCommit", ["request"] = request, ["response"] = response, error = err})
	end
	
	response.success = true
	
	return response
end

function cjdns.connectInit(request, response)
	
	local mykey, err = cjdnsNet.getMyKey()
	if err then
		response.success = false response.errorMsg = "Failed to get my own key: " .. err return response
	elseif mykey == nil then
		response.success = false response.errorMsg = "Failed to get my own key: Unknown error" return response
	end
	
	
	local key, err = cjdnsNet.getKeyForIp(request.ip)
	if err then
		response.success = false response.errorMsg = "Failed to get key for IP: " .. err return response
	elseif mykey == nil then
		response.success = false response.errorMsg = "Failed to get key for IP: Unknown error" return response
	end
	
	if not request.options then request.options = {} end
	request.options.key = mykey
	response.gatewayKey = key
	
	response.success = true
	
	return response
end

function cjdns.connect(request, response)
	
	if response.gatewayResponse.key == nil then
		response.success = false response.errorMsg = "Gateway did not send its key" return response
	end
	
	response.gatewayResponse.key = tostring(response.gatewayResponse.key)
	
	local success, err = cjdns.connectTo(response.gatewayResponse.key)
	if not success then
		if err then
			response.success = false response.errorMsg = "Failed to get local cjdroute to connect to gateway: "..err return response
		else
			response.success = false response.errorMsg = "Failed to get local cjdroute to connect to gateway: Unknown error" return response
		end
	end
	
	if not response.gatewayResponse.ipv4 and not response.gatewayResponse.ipv6 then
		response.success = false response.errorMsg = "Failed to obtain IPv4 and IPv6 addresses from gateway" return response
	end
	if response.gatewayResponse.ipv4 and not response.gatewayResponse.cidr4 then
		response.success = false response.errorMsg = "Failed to obtain IPv4 CIDR from gateway" return response
	end
	if response.gatewayResponse.ipv6 and not response.gatewayResponse.cidr6 then
		response.success = false response.errorMsg = "Failed to obtain IPv6 CIDR from gateway" return response
	end
	
	-- parse addresses
	if response.gatewayResponse.ipv4 then
		local subnet4, ipv4, cidr4, ipv4gateway, err
		subnet4, err = network.parseIpv4Subnet(response.gatewayResponse.ipv4.."/"..response.gatewayResponse.cidr4)
		if err then
			response.success = false response.errorMsg = "Failed to parse IPv4 address" return response
		end
		ipv4, response.cidr4 = unpack(subnet4)
		response.ipv4 = network.ip2string(ipv4)
		
		ipv4gateway, err = network.parseIpv4(response.gatewayResponse.ipv4gateway)
		if err then
			response.success = false response.errorMsg = "Failed to parse gateway IPv4 address" return response
		end
		if not ipv4gateway then
			response.success = false response.errorMsg = "No gateway IPv4 address provided" return response
		end
		response.ipv4gateway = network.ip2string(ipv4gateway)
	end
	if response.gatewayResponse.ipv6 then
		local subnet6, ipv6, cidr6, ipv6gateway, err
		subnet6, err = network.parseIpv6Subnet(response.gatewayResponse.ipv6.."/"..response.gatewayResponse.cidr6)
		if err then
			response.success = false response.errorMsg = "Failed to parse IPv6 address" return response
		end
		ipv6, response.cidr6 = unpack(subnet6)
		response.ipv6 = network.ip2string(ipv6)
		
		ipv6gateway, err = network.parseIpv6(response.gatewayResponse.ipv6gateway)
		if err then
			response.success = false response.errorMsg = "Failed to parse gateway IPv6 address" return response
		end
		if not ipv6gateway then
			response.success = false response.errorMsg = "No gateway IPv6 address provided" return response
		end
		response.ipv6gateway = network.ip2string(ipv6gateway)
	end
	
	local interface, err = cjdnsNet.getInterface()
	if interface then response.interface = interface.name end
	
	response.success = true
	
	return response
end

function cjdns.connectCommit(request, response)
	
	db.registerSubscriberSessionCjdnsKey(request.sid, response.gatewayKey)
	
	local ret, err = cjdns.subscriberSetup(response.gatewayResponse)
	if err then
		threadman.notify({type = "error", module = "tunnels.cjdns", ["function"] = "connectCommit", ["request"] = request, ["response"] = response, ["error"] = err})
	end
	
	response.success = true
	
	return response
end

function cjdns.disconnect(request, response)
	
	local interface, err = cjdnsNet.getInterface()
	if interface then response.interface = interface.name end
	
	response.success = true
	
	return response
	
end

function cjdns.disconnectCommit(request, response)
	
	local session, err = db.lookupSession(request.sid)
	if err then
		threadman.notify({type = "error", module = "tunnels.cjdns", ["function"] = "disconnect", ["request"] = request, ["response"] = response, ["error"] = err})
	end
	
	local ret, err = cjdns.subscriberTeardown(session)
	if err then
		threadman.notify({type = "error", module = "tunnels.cjdns", ["function"] = "disconnect", ["request"] = request, ["response"] = response, ["error"] = err})
	end
	
	response.success = true
	
	return response
	
end

function cjdns.maintainConnection(session)
	
	local connections, err = cjdns.listConnections()
	if err then
		threadman.notify({type = "error", module = "cjdns", ["function"] = 'maintainConnection', error = err})
	else
		if session.active == 1 then
			local key, err = db.getCjdnsSubscriberKey(session.sid)
			if err or not key then
				threadman.notify({type = "error", module = "cjdns", ["function"] = 'maintainConnection', error = err})
			else
				local exists = false
				for k,connIndex in pairs(connections) do
					local connection, err = cjdns.showConnection(connIndex)
					if err then
						threadman.notify({type = "error", module = "cjdns", ["function"] = 'maintainConnection', error = err})
					else
						if connection.key == key then
							exists = true
							break
						end
					end
				end
				if not exists then
					local success, err
					if session.subscriber == 1 then
						success, err = cjdns.addKey(key, session.internetIPv4, session.internetIPv6)
					else
						success, err = cjdns.connectTo(key)
					end
					if not success then
						if err then
							threadman.notify({type = "error", module = "cjdns", ["function"] = 'maintainConnection', error = "Failed to add key to cjdns: "..err})
						else
							threadman.notify({type = "error", module = "cjdns", ["function"] = 'maintainConnection', error = "Failed to add key to cjdns: Unknown error"})
						end
					else
						threadman.notify({type = "warning", module = "cjdns", ["function"] = 'maintainConnection', warning = "Warning: added missing key "..key.." in cjdroute"})
					end
				end
			end
		end
	end
	
	return true, nil
end

function cjdns.listConnections()
	local response, err = cjdnsNet.getAI():auth({
			q = "IpTunnel_listConnections"
		})
	if err then
		return nil, "Error getting connections: " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error getting connections: " .. response.error
		end
		return response.connections, nil
	end
end

function cjdns.showConnection(connIndex)
	local response, err = cjdnsNet.getAI():auth({
			q = "IpTunnel_showConnection",
			connection = connIndex,
		})
	if err then
		return nil, "Error getting connections: " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error getting connection " .. connIndex .. " info: " .. response.error
		end
		return response, nil
	end
end

function cjdns.connectTo(key)
	local response, err = cjdnsNet.getAI():auth({
			q = "IpTunnel_connectTo",
			publicKeyOfNodeToConnectTo = key,
		})
	if err then
		return nil, "Error connecting to " .. key .. ": " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error connecting to " .. key .. ": " .. response.error
		end
		threadman.notify({type = "info", module = "tunnels.cjdns", info = "Connected to "..key})
		return true, nil
	end
end

function cjdns.addKey(key, ip4, ip6)
	ip4 = ip4 or nil
	ip6 = ip6 or nil
	
	if ip4 == nil and ip6 == nil then
		return nil, "At least IPv4 or IPv6 address is required"
	end
	
	local req = {
			q = "IpTunnel_allowConnection",
			publicKeyOfAuthorizedNode = key,
		}
	
	if ip4 ~= nil then
		req['ip4Address'] = ip4
	end
	if ip6 ~= nil then
		req['ip6Address'] = ip6
	end
	
	local response, err = cjdnsNet.getAI():auth(req)
	if err then
		return nil, "Error adding tunnel key " .. key .. ": " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error adding tunnel key " .. key .. ": " .. response.error
		end
		threadman.notify({type = "info", module = "tunnels.cjdns", info = "Added key "..key})
		return true, nil
	end
end

function cjdns.removeConnection(connIndex)
	local response, err = cjdnsNet.getAI():auth({
			q = "IpTunnel_removeConnection",
			connection = connIndex,
		})
	if err then
		return nil, "Error removing tunnel key " .. connIndex .. ": " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error removing tunnel key " .. connIndex .. ": " .. response.error
		end
		threadman.notify({type = "info", module = "tunnels.cjdns", info = "Removed connection "..connIndex})
		return true, nil
	end
	
end

function cjdns.deauthorizeKey(key)
	-- TODO: fix race condition
	local connections, err = cjdns.listConnections()
	if err ~= nil then
		return false, err
	else
		for k,connIndex in pairs(connections) do
			local connection, err = cjdns.showConnection(connIndex)
			if err ~= nil then
				return false, err
			else
				if connection.key == key then
					local success, err = cjdns.removeConnection(connIndex)
					if err then
						return false, err
					else
						return true, nil
					end
				end
			end
		end
	end
end

local tunnelSetup = {}

function cjdns.gatewaySetup()
	
	local mode = config.cjdns.routing
	
	if mode == "none" then
		return true, nil
	end
	
	if mode ~= "nat" and mode ~= "route" then
		return nil, "Unknown gateway routing mode "..mode
	end
	
	-- IPv4
	
	-- determine cjdns interface
	local interface, err = cjdnsNet.getInterface()
	if err then return nil, err end
	
	-- determine ip that will be used on cjdns interface
	local ipv4, cidr4, subnet4
	if mode == "nat" then
		subnet4, err = network.parseIpv4Subnet(config.cjdns.ipv4subnet);
		if err then
			return nil, "Failed to parse IPv4 subnet: "..err
		end
		ipv4, err = network.parseIpv4(config.cjdns.ipv4gateway);
		if err then
			return nil, "Failed to parse IPv4 gateway: "..err
		end
		
		local ipv4prefix
		ipv4prefix, cidr4 = unpack(subnet4)
	end
	if mode == "route" then
		subnet4, err = gateway.allocateIpv4();
		if err then
			return nil, "Failed to allocate IPv4: "..err
		end
		if not subnet4 then
			return nil, "Failed to allocate IPv4 for interface "..interface
		end
		ipv4, cidr4 = unpack(subnet4)
	end
	
	-- remove interface address if it is already set
	network.unsetInterfaceIp(interface, subnet4)
	
	-- set up cjdns interface ip address
	local result, err = network.setInterfaceIp(interface, subnet4)
	if err then
		return nil, "Failed to set local IPv4 address: "..err
	end
	
	tunnelSetup.subnet4 = subnet4
	tunnelSetup.interface = interface
	
	-- determine transit interface
	local transitIf4, err = network.getIpv4TransitInterface()
	if err then
		return nil, "Failed to determine IPv4 transit interface: "..err
	end
	if not transitIf4 then
		return nil, "Failed to determine IPv4 transit interface"
	end
	
	if mode == "nat" then
		
		local result, err = network.setupNat4(interface, transitIf4)
		if err then
			return nil, "Failed to set up NAT: "..err
		end
	end
	
	if mode == "route" then
		
		local prefixMask4 = network.Ipv4cidrToBinaryMask(cidr4)
		local prefixAddr4 = bit32.band(network.ip2binary(ipv4), prefixMask4)
		
		local result, err = network.setRoute(interface, {prefixAddr4, cidr4})
		if err then
			return nil, "Failed to set up route: "..err
		end
		
	end
	
	-- IPv6
	
	if config.gateway.ipv6support == "yes" then
		
		local ipv6, cidr6, subnet6
		if mode == "nat" then
			subnet6, err = network.parseIpv6Subnet(config.cjdns.ipv6subnet);
			if err then
				return nil, "Failed to parse IPv6 subnet: "..err
			end
			ipv6, err = network.parseIpv6(config.cjdns.ipv6gateway);
			if err then
				return nil, "Failed to parse IPv6 gateway: "..err
			end
			
			local ipv6prefix
			ipv6prefix, cidr6 = unpack(subnet6)
		end
		if mode == "route" then
			subnet6, err = gateway.allocateIpv6();
			if err then
				return nil, "Failed to allocate IPv6: "..err
			end
			if not subnet6 then
				return nil, "Failed to allocate IPv6 for interface "..interface
			end
			ipv6, cidr6 = unpack(subnet6)
		end
		
		-- remove interface address if it is already set
		network.unsetInterfaceIp(interface, subnet6)
		
		-- set up cjdns interface ip address
		local result, err = network.setInterfaceIp(interface, subnet6)
		if err then
			return nil, "Failed to set local IPv4 address: "..err
		end
		
		tunnelSetup.subnet6 = subnet6
		tunnelSetup.interface = interface
		
		-- determine if we have ipv6 support at all
		local transitIf6, err = network.getIpv6TransitInterface()
		if err or not transitIf6 then
			
			-- TODO: set up 6in4
			
		else
			
			if mode == "nat" then
				
				local result, err = network.setupNat6(interface, transitIf6)
				if err then
					return nil, "Failed to set up NAT: "..err
				end
				
			end
			
			if mode == "route" then
				
				local prefixMask6 = network.Ipv6cidrToBinaryMask(cidr6)
				local prefixAddr6 = bit128.band(network.ip2binary(ipv6), prefixMask6)
				
				local result, err = network.setRoute(interface, {prefixAddr6, cidr6})
				if err then
					return nil, "Failed to set up route: "..err
				end
				
			end
			
		end
	end
	
	return true, nil
end

function cjdns.gatewayTeardown()
	
	if tunnelSetup and tunnelSetup.subnet4 then
		
		-- set up cjdns interface ip address
		local result, err = network.unsetInterfaceIp(tunnelSetup.interface, tunnelSetup.subnet4)
		if err then
			return nil, "Failed to unset local IPv4 address: "..err
		end
		
	end
	
	if tunnelSetup and tunnelSetup.subnet6 then
		
		-- set up cjdns interface ip address
		local result, err = network.unsetInterfaceIp(tunnelSetup.interface, tunnelSetup.subnet6)
		if err then
			return nil, "Failed to unset local IPv6 address: "..err
		end
		
	end
	
	-- TODO: remove iptables rules
	
	return true, nil
end

function cjdns.subscriberSetup(gatewayData)
	
	local mode = config.subscriber.routing
	
	if mode ~= "route" and mode ~= "none" then
		return nil, "Unknown subscriber routing mode"
	end
	
	local interface, err = cjdnsNet.getInterface()
	if err then return nil, err end
	
	if mode == "route" then
		
		-- configure default route
		
		local ipv4gateway, err = network.parseIpv4(gatewayData.ipv4gateway)
		if err then return nil, err end
		local result, err = network.setDefaultRoute(interface, ipv4gateway)
		if err then return nil, err end
		
		if gatewayData.ipv6gateway then
			local ipv6gateway, err = network.parseIpv6(gatewayData.ipv6gateway)
			if err then return nil, err end
			local result, err = network.setDefaultRoute(interface, ipv6gateway)
			if err then return nil, err end
		end
		
	end
	
	return true
end

function cjdns.subscriberTeardown(session)
	
	local interface, err = cjdnsNet.getInterface()
	if err then return nil, err end
	
	local result, err = network.unsetDefaultRoute(false)
	if err then return nil, err end
	if session.ipv6gateway then
		local result, err = network.unsetDefaultRoute(true)
		if err then return nil, err end
	end
	
	return true
end

return cjdns
