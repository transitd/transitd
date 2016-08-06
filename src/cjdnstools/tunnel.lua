
--- @module cjdnstools.tunnel
local tunnel = {}

local config = require("config")
local network = require("network")

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
	print("Connecting to " .. key)
	
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
		return true, nil
	end
end

function tunnel.addKey(key, ip4, ip6)
	ip4 = ip4 or nil
	ip6 = ip6 or nil
	
	if ip4 == nil and ip6 == nil then
		return nil, "At least IPv4 or IPv6 address is required"
	end
	
	print("Adding key " .. key)
	
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
		return true, nil
	end
	
end

function tunnel.removeConnection(connIndex)
	print("Removing connection " .. connIndex) 
	
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
	
	local interface, err = tunnel.getInterface()
	if err then return nil, err end
	
	--	local cmd = "ip addr add "..gatewayData.ipv4.."/"..gatewayData.cidr4.." dev "..interface.name
	--	local retval = os.execute(cmd)
	--	if retval ~= 0 then
	--		return nil, "Failed to set local IPv4 address"
	--	end
	
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
	os.execute("ip -6 route del default")
	
	local retval = os.execute("ip route add dev "..interface.name)
	if retval ~= 0 then
		return nil, "Failed to configure default IPv4 route"
	end
	local retval = os.execute("ip -6 route add dev "..interface.name)
	if retval ~= 0 then
		return nil, "Failed to configure default IPv6 route"
	end
	
	return true
end

function tunnel.subscriberTeardown()
	
	local retval = os.execute("ip route del default")
	if retval ~= 0 then
		return nil, "Failed to remove default IPv4 route"
	end
	
	local retval = os.execute("ip -6 route del default")
	if retval ~= 0 then
		return nil, "Failed to remove default IPv6 route"
	end
	
	return true
end

return tunnel
