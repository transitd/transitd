--[[
@file jsonrpc.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module monitor
local monitor = {}

local threadman = require("threadman")
local network = require("network")

local online = nil

function monitor.check()
	
	local target = config.daemon.pingTarget
	if not target then target = "8.8.8.8" end
	
	-- TODO: look at network interface traffic instead of pinging
	local ol, err = network.ping(target)
	
	if ol and not online then
		online = true
		threadman.notify({type = "goingOnline"})
	end
	if not ol and online then
		online = false
		threadman.notify({type = "goingOffline"})
	end
	
	if ol ~= nil then
		threadman.notify({type = "onlineStatusUpdate", ["online"] = ol})
	end
end

function monitor.isOnline()
	
	if online == nil then
		
		local result, err = threadman.waitForMessage("onlineStatus", {type = "onlineStatusQuery"})
		if err then return nil, err end
		return result["online"], nil
		
	else
		return online, nil
	end
	
end

function monitor.run()
	
	local listener = threadman.registerListener("monitor", {"exit","onlineStatusQuery","heartbeat"})
	
	local lastCheck = 0
	
	while true do
		
		local msg = listener:listen()
		if msg ~= nil then
			if msg["type"] == "exit" then
				break
			end
		end
		if msg["type"] == "onlineStatusQuery" then
			threadman.notify({type = "onlineStatus", ["online"] = online})
		end
		if msg["type"] == "heartbeat" then
			local time = os.time()
			if time > lastCheck + 10 then
				monitor.check()
				lastCheck = time
			end
		end
		
	end
	
	threadman.unregisterListener(listener)
end

return monitor
