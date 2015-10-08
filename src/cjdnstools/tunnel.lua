
--- @module cjdnstools.tunnel
local tunnel = {}

local config = require("config")

package.path = package.path .. ";cjdns/contrib/lua/?.lua"

local cjdns = require "cjdns.init"
local addrcalc = require "cjdnstools.addrcalc"

require "cjdns.config" -- ConfigFile null in certain cases?
local conf = cjdns.ConfigFile.new(get_path_from_path_relative_to_config(config.cjdns.config))
local ai = conf:makeInterface()

function tunnel.getConnections()
	local response, err = ai:auth({
			q = "IpTunnel_listConnections",
			publicKeyOfNodeToConnectTo = key,
		})
	if err then
		return nil, "Error adding key " .. key .. ": " .. err
	else
		return true, nil
	end
end

function tunnel.connect(key)
	print("Connecting to " .. key)
	
	local response, err = ai:auth({
			q = "IpTunnel_connectTo",
			publicKeyOfNodeToConnectTo = key,
		})
	if err then
		return nil, "Error adding key " .. key .. ": " .. err
	else
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
		return nil, "Error adding key " .. key .. ": " .. err
	else
		return true, nil
	end
	
end

function tunnel.removeKey(connIndex)
	print("Removing connection " .. connIndex) 
	
	local response, err = ai:auth({
			q = "IpTunnel_removeConnection",
			connection = connIndex,
		})
	if err then
		return nil, "Error removing connection " .. connIndex .. ": " .. err
	else
		return true, nil
	end
	
end

return tunnel
