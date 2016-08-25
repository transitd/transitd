--[[
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module cjdnstools.tunnel
local tunnel = {}

local config = require("config")
local network = require("network")
local gateway = require("gateway")
local shell = require("lib.shell")
local threadman = require("threadman")

package.path = package.path .. ";cjdnstools/contrib/lua/?.lua"

local cjdns = require "cjdns.init"

require "cjdns.config" -- ConfigFile null in certain cases?
local conf = cjdns.ConfigFile.new(get_path_from_path_relative_to_config(config.cjdns.config))
local ai = conf:makeInterface()

function tunnel.listConnections()
	local response, err = ai:auth({
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

function tunnel.showConnection(connIndex)
	local response, err = ai:auth({
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

function tunnel.connect(key)
	local response, err = ai:auth({
			q = "IpTunnel_connectTo",
			publicKeyOfNodeToConnectTo = key,
		})
	if err then
		return nil, "Error connecting to " .. key .. ": " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error connecting to " .. key .. ": " .. response.error
		end
		threadman.notify({type = "info", module = "cjdnstools.tunnel", info = "Connected to "..key})
		return true, nil
	end
end

function tunnel.addKey(key, ip4, ip6)
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
	
	local response, err = ai:auth(req)
	if err then
		return nil, "Error adding tunnel key " .. key .. ": " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error adding tunnel key " .. key .. ": " .. response.error
		end
		threadman.notify({type = "info", module = "cjdnstools.tunnel", info = "Added key "..key})
		return true, nil
	end
end

function tunnel.removeConnection(connIndex)
	local response, err = ai:auth({
			q = "IpTunnel_removeConnection",
			connection = connIndex,
		})
	if err then
		return nil, "Error removing tunnel key " .. connIndex .. ": " .. err
	else
		if response.error and response.error ~= "none" then
			return nil, "Error removing tunnel key " .. connIndex .. ": " .. response.error
		end
		threadman.notify({type = "info", module = "cjdnstools.tunnel", info = "Removed connection "..connIndex})
		return true, nil
	end
	
end

function tunnel.deauthorizeKey(key)
	-- TODO: fix race condition
	local connections, err = tunnel.listConnections()
	if err ~= nil then
		return false, err
	else
		for k,connIndex in pairs(connections) do
			local connection, err = tunnel.showConnection(connIndex)
			if err ~= nil then
				return false, err
			else
				if connection.key == key then
					local success, err = tunnel.removeConnection(connIndex)
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

function tunnel.getInterface()
	-- figure out what the cjdns network interface is
	local cjdnsPrefix, err = network.parseIpv6Subnet(config.cjdns.network)
	if err then
		return nil, "Failed to determine cjdns network prefix: "..err
	end
	local cjdnsPrefixIp, cjdnsPrefixCidr = unpack(cjdnsPrefix)
	local interface, err = network.getInterfaceBySubnet({cjdnsPrefixIp, cjdnsPrefixCidr})
	if err then
		return nil, "Failed to determine cjdns network interface: "..err
	end
	if not interface then
		return nil, "Failed to determine cjdns network interface"
	end
	
	return interface
end

function tunnel.gatewaySetup()
	
	local mode = config.gateway.routing
	
	if mode == "none" then
		return true, nil
	end
	
	if mode ~= "nat" and mode ~= "route" then
		return nil, "Unknown gateway routing mode "..mode
	end
	
	-- IPv4
	
	-- set up kernel forwarding option
	local success, err = network.setIpv4Forwading(1)
	if err then return nil, err end
	
	-- determine cjdns interface
	local interface, err = tunnel.getInterface()
	if err then return nil, err end
	
	-- determine ip that will be used on cjdns interface
	local ipv4, cidr4
	if mode == "nat" then
		local subnet4, err = network.parseIpv4Subnet(config.gateway.ipv4subnet);
		if err then
			return nil, "Failed to parse IPv4 subnet: "..err
		end
		ipv4, err = network.parseIpv4(config.gateway.ipv4gateway);
		if err then
			return nil, "Failed to parse IPv4 gateway: "..err
		end
		
		local ipv4prefix
		ipv4prefix, cidr4 = unpack(subnet4)
	else
		local subnet4, err = gateway.allocateIpv4();
		if err then
			return nil, "Failed to allocate IPv4: "..err
		end
		if not subnet4 then
			return nil, "Failed to allocate IPv4 for interface "..interface
		end
		ipv4, cidr4 = unpack(subnet4)
	end
	
	-- set up cjdns interface ip address
	local cmd = shell.escape({"ip","addr","add",network.ip2string(ipv4).."/"..cidr4,"dev",interface.name})
	local retval = os.execute(cmd)
	if retval ~= 0 then
		return nil, "Failed to set local IPv4 address"
	end
	
	-- determine transit interface
	local transitIf4, err = network.getIpv4TransitInterface()
	if err then
		return nil, "Failed to determine IPv4 transit interface: "..err
	end
	if not transitIf4 then
		return nil, "Failed to determine IPv4 transit interface"
	end
	
	if mode == "nat" then
		
		-- set up nat
		local cmd = shell.escape({"iptables","--table","nat","--append","POSTROUTING","--out-interface",transitIf4.name,"-j","MASQUERADE"})
		local retval = os.execute(cmd)
		if retval ~= 0 then
			return nil, "iptables failed"
		end
		
		local cmd = shell.escape({"iptables","--append","FORWARD","--in-interface",interface.name,"-j","ACCEPT"})
		local retval = os.execute(cmd)
		if retval ~= 0 then
			return nil, "iptables failed"
		end
		
	else
		
		local cmd = "ip route add "..config.gateway.ipv4gateway.." dev "..transitIf4.name
		local retval = os.execute(cmd)
		if retval ~= 0 then
			return nil, "Failed to execute "..cmd
		end
		
		local prefixMask4 = network.Ipv4cidrToBinaryMask(cidr4)
		local prefixAddr4 = bit32.band(network.ip2binary(ipv4), prefixMask4)
		
		local cmd = "ip route add "..ip2string(prefixAddr4).."/"..cidr4.." dev "..interface.name
		local retval = os.execute(cmd)
		if retval ~= 0 then
			return nil, "Failed to execute "..cmd
		end
		
	end
	
	-- IPv6
	
	if config.gateway.ipv6support == "yes" then
		
		local ipv6, cidr6
		if mode == "nat" then
			local subnet6, err = network.parseIpv6Subnet(config.gateway.ipv6subnet);
			if err then
				return nil, "Failed to parse IPv6 subnet: "..err
			end
			ipv6, err = network.parseIpv6(config.gateway.ipv6gateway);
			if err then
				return nil, "Failed to parse IPv6 gateway: "..err
			end
			
			local ipv6prefix
			ipv6prefix, cidr6 = unpack(subnet6)
		else
			local subnet6, err = gateway.allocateIpv6();
			if err then
				return nil, "Failed to allocate IPv6: "..err
			end
			if not subnet6 then
				return nil, "Failed to allocate IPv6 for interface "..interface
			end
			ipv6, cidr6 = unpack(subnet6)
		end
		
		-- determine if we have ipv6 support at all
		local transitIf6, err = network.getIpv6TransitInterface()
		if err or not transitIf6 then
			-- TODO: set up 6in4
		else
			
			-- set up kernel forwarding option
			local success, err = network.setIpv6Forwading(1)
			if err then return nil, err end
			
			if mode == "route" then
				
				local cmd = "ip -6 route add "..config.gateway.ipv6gateway.." dev "..transitIf6.name
				local retval = os.execute(cmd)
				if retval ~= 0 then
					return nil, "Failed to execute "..cmd
				end
				
				local prefixMask6 = network.Ipv6cidrToBinaryMask(cidr6)
				local prefixAddr6 = bit128.band(network.ip2binary(ipv6), prefixMask6)
				
				local cmd = "ip -6 route add "..ip2string(prefixAddr6).."/"..cidr6.." dev "..interface.name
				local retval = os.execute(cmd)
				if retval ~= 0 then
					return nil, "Failed to execute "..cmd
				end
				
			end
			
		end
	end
	
	return true, nil
end

function tunnel.subscriberSetup(gatewayData)
	
	local interface, err = tunnel.getInterface()
	if err then return nil, err end
	
	-- this is already done by cjdns
	--if ipv4 then
	--	local cmd = "ip addr add "..gatewayData.ipv4.."/"..gatewayData.cidr4.." dev "..interface.name
	--	local retval = os.execute(cmd)
	--	if retval ~= 0 then
	--		return nil, "Failed to set local IPv4 address"
	--	end
	--end
	--if ipv6 then
	--	local cmd = "ip addr add "..gatewayData.ipv6.."/"..gatewayData.cidr6.." dev "..interface.name
	--	local retval = os.execute(cmd)
	--	if retval ~= 0 then
	--		return nil, "Failed to set local IPv6 address"
	--	end
	--end
	
	-- configure default route
	
	os.execute("ip route del default")
	
	if gatewayData.ipv6 then
		os.execute("ip -6 route del default")
	end
	
	local retval = os.execute("ip route add dev "..interface.name)
	if retval ~= 0 then
		return nil, "Failed to configure default IPv4 route"
	end
	
	if gatewayData.ipv6 then
		local retval = os.execute("ip -6 route add dev "..interface.name)
		if retval ~= 0 then
			return nil, "Failed to configure default IPv6 route"
		end
	end
	
	return true
end

function tunnel.subscriberTeardown(session)
	
	local retval = os.execute("ip route del default")
	if retval ~= 0 then
		return nil, "Failed to remove default IPv4 route"
	end
	
	if session.internetIPv6 then
		local retval = os.execute("ip -6 route del default")
		if retval ~= 0 then
			return nil, "Failed to remove default IPv6 route"
		end
	end
	
	return true
end

return tunnel
