--[[
@file monitor.lua
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
	
	monitor.onlineCheck()
	
	-- TODO: do other kinds of checks
	
end

function monitor.onlineCheck()
	
	local target = config.daemon.pingTarget
	if not target then target = "8.8.8.8" end
	
	-- TODO: look at network interface traffic instead of pinging
	local ol, err = network.ping(target)
	
	if ol == nil then ol = false end
	
	if ol and (online == nil or online == false) then
		online = true
		threadman.notify({type = "goingOnline"})
		threadman.setShared('online', online)
	end
	if not ol and (online == nil or online == true) then
		online = false
		threadman.notify({type = "goingOffline"})
		threadman.setShared('online', online)
	end
	
	if ol ~= nil then
		threadman.notify({type = "onlineStatusUpdate", ["online"] = ol})
	end
end

function monitor.isOnline()
	
	if online == nil then
		return threadman.getShared('online'), nil;
	else
		return online, nil
	end
	
end

function monitor.run()
	
	local listener = threadman.registerListener("monitor", {"exit","onlineStatusQuery","heartbeat","connected","disconnected"})
	
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
		if msg["type"] == "connected"
		or msg["type"] == "disconnected"
		then lastCheck = 0 end
		if msg["type"] == "heartbeat"
		or msg["type"] == "connected"
		or msg["type"] == "disconnected"
		then
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
