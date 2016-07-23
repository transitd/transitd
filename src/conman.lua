
--- @module conman
local conman = {}

local config = require("config")
local db = require("db")
local cjdns = require("rpc-interface.cjdns")
local threadman = require("threadman")
local rpc = require("rpc")

local conManTs = 0

local subscriberManager = function()
	
	local sinceTimestamp = conManTs
	conManTs = os.time()
	
	local subscribers, err = db.getTimingOutSubscribers(sinceTimestamp)
	if err == nil and subscribers == nil then
		err = "Unexpected subscriber list query result"
	end
	if err then
		threadman.notify({type = "error", module = "conman", error = err})
		return
	end
	
	for k,subscriber in pairs(subscribers) do
		local at = ""
		if subscriber.meshIP ~= nil then
			at = at..subscriber.method.."::"..subscriber.meshIP.." "
		end
		local addr = ""
		if subscriber.internetIPv4 ~= nil then
			addr = addr..subscriber.internetIPv4.." "
		end
		if subscriber.internetIPv6 ~= nil then
			addr = addr..subscriber.internetIPv6.." "
		end
		
		print("Subscriber '"..subscriber.name.." at "..at.."-> "..addr.." timed out.")
		
		if subscriber.method == "cjdns" then
			cjdns.releaseConnection(subscriber.sid)
		else
			threadman.notify({type = "error", module = "conman", error = "Unknown method", method = subscriber.method})
		end
	end
end

local gatewayManager = function()
	-- TODO: renew connection to gateway when about to expire
end

function conman.connectToGateway(ip, port, method, sid)
	
	local gateway = rpc.getProxy(ip, port)
	local record = db.lookupGateway(ip)
	
	print("[conman] Checking " .. ip .. "...")
	local info, err = gateway.nodeInfo()
	if err then
		return nil, "Failed to connect to " .. ip .. ": " .. err
	else
		db.registerNode(info.name, ip, port)
	end
	
	if info.methods then
		-- check to make sure method is supported
		local supported = false
		for k, m in pairs(info.methods) do
			if m == method then
				supported = true
			end
			-- register methods
			if m and m.name then
				db.registerGateway(info.name, ip, port, m.name)
			end
		end
	else
		method = nil
	end
	
	if method == nil then
		return nil, "No supported connection methods at " .. ip
	end
	
	print("[conman] Connecting to gateway '" .. info.name .. "' at " .. ip)
	
	local result
	
	if method == "cjdns" then
		print("[conman] Connecting to " .. ip .. " port " .. port)
		db.registerGatewaySession(sid, info.name, method, ip, port)
		result = cjdns.connectTo(ip, port, method, sid)
		if result.success then
			print("Registered with gateway at " .. ip .. " port "..port.."!")
			if result.timeout then
				if result.ipv4        then print("IPv4:" .. result.ipv4)                        end
				if result.ipv4gateway then print("IPv4 gateway:" .. result.ipv4gateway)         end
				if result.ipv6        then print("IPv6:" .. result.ipv6)                        end
				if result.ipv6gateway then print("IPv6 gateway:" .. result.ipv6gateway)         end
				if result.dns         then print("IPv6 DNS:" .. result.dns)                     end
				if result.timeout     then print("Timeout is " .. result.timeout .. " seconds") end
			end
			db.updateGatewaySession(sid, true, result.ipv4, result.ipv6, result.timeout)
		end
		return result, nil
	else
		return nil, "Unsupported method"
	end
	
	if result.success then
		return true
	else
		return nil, result.errorMsg
	end
end

local connectionManager = function()
	subscriberManager()
	gatewayManager()
end

function conman.startConnectionManager()
	local socket = require("socket")
	local listener = threadman.registerListener("conman")
	while true do
		socket.sleep(2)
		connectionManager()
		local msg = {};
		while msg ~= nil do
			msg = listener:listen(true)
			if msg ~= nil then
				if msg["type"] == "exit" then
					threadman.unregisterListener(listener)
					return
				end
			end
		end
	end
	
end

return conman
