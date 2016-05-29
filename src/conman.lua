
--- @module conman
local conman = {}

local config = require("config")
local db = require("db")
local cjdnsTunnel = require("cjdnstools.tunnel")

local conManTs = 0

local connectionManager = function()
	
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
		
		local cjdnsConnections, err = cjdnsTunnel.getConnections()
		if err ~= nil then
			-- TODO: unregister key
			-- cjdnsTunnel.removeKey(connIndex)
		end
	end
end

function conman.startConnectionManager()
	local socket = require("socket")
	while true do
		connectionManager()
		socket.sleep(10)
	end
end

return conman
