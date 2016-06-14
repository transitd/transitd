
--- @module conman
local conman = {}

local config = require("config")
local db = require("db")
local cjdnsTunnel = require("cjdnstools.tunnel")

local conManTs = 0

local subscriberManager = function()
	
	local sinceTimestamp = conManTs
	conManTs = os.time()
	
	local clients, error = db.getTimingOutClients(sinceTimestamp)
	if clients == nil then
		print(error)
		return
	end
	
	for k,client in pairs(clients) do
		local at = ""
		if client.meshIPv4 ~= nil then
			at = at..client.method.."::"..client.meshIPv4.." "
		end
		if client.meshIPv6 ~= nil then
			at = at..client.method.."::"..client.meshIPv6.." "
		end
		local addr = ""
		if client.meshIPv4 ~= nil then
			addr = addr..client.internetIPv4.." "
		end
		if client.meshIPv6 ~= nil then
			addr = addr..client.internetIPv6.." "
		end
		
		print("Client '"..client.name.." at "..at.."-> "..addr.." timed out.")
		
		if client.method == "cjdns" then
			-- we will need to remove the key from running cjdroute
			local key, error = db.getCjdnsClientKey(client.sid)
			if error then
				print("Failed to deauthroize cjdns tunnel key: "..error)
			else
				local success, error = cjdnsTunnel.deauthorizeKey(key)
				if error then
					print("Failed to deauthroize cjdns tunnel key: "..error)
				else
					print("Deauthorized cjdns key "..key)
					db.deactivateClientBySession(client.sid)
				end
			end
		end
	end
end

local gatewayManager = function()
	-- TODO: renew connection to gateway when about to expire
end

local connectionManager = function()
	subscriberManager()
	gatewayManager()
end

function conman.startConnectionManager()
	local socket = require("socket")
	while true do
		connectionManager()
		socket.sleep(10)
	end
end

return conman
