
--- @module cjdnstools.tunnel
local tunnel = {}

local config = require("config")

package.path = package.path .. ";cjdnstools/contrib/lua/?.lua"

local cjdns = require "cjdns.init"
local addrcalc = require "cjdnstools.addrcalc"

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

return tunnel
