--[[
@file shrunner.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module shrunner
local shrunner = {}

local config = require("config")
local shell = require("lib.shell")
local threadman = require("threadman")

function shrunner.run()
	
	local listener = threadman.registerListener("shrunner",{"exit", "registered", "released", "connected", "disconnected", "goingOnline", "goingOffline"})
	
	while true do
		local msg = listener:listen()
		if msg ~= nil then
			if msg["type"] == "exit" then
				break
			end
			local exe = nil
			local cmd = nil
			if (config.gateway.enabled == "yes" and msg.type=="registered" and config.gateway.onRegister)
			or (config.gateway.enabled == "yes" and msg.type=="released" and config.gateway.onRelease)
			or (config.gateway.enabled ~= "yes" and msg.type=="connected" and config.subscriber.onConnect)
			or (config.gateway.enabled ~= "yes" and msg.type=="disconnected" and config.subscriber.onDisconnect)
			then
				if msg.type=="registered" then exe = config.gateway.onRegister end
				if msg.type=="released" then exe = config.gateway.onRelease end
				if msg.type=="connected" then exe = config.subscriber.onConnect end
				if msg.type=="disconnected" then exe = config.subscriber.onDisconnect end
				if exe and msg.response.sid then
					local db = require("db")
					local session = db.lookupSession(msg.response.sid)
					if session and exe then
						local sid = session.sid or "0"
						local meshIp = session.meshIP or "0"
						local ipv4 = session.internetIPv4 or "0"
						local cidr4 = session.internetIPv4cidr or "0"
						local ipv4gateway = session.internetIPv4gateway or "0"
						local ipv6 = session.internetIPv6 or "0"
						local cidr6 = session.internetIPv6cidr or "0"
						local ipv6gateway = session.internetIPv6gateway or "0"
						local interface4 = msg.response.interface4 or "0"
						local interface6 = msg.response.interface6 or "0"
						cmd = shell.escape({exe, sid, meshIp, ipv4, ipv4gateway, cidr4, ipv6, ipv6gateway, cidr6, interface4, interface6})
					end
				end
			end
			if (msg.type=="goingOnline" and config.subscriber.onGoingOnline)
			or (msg.type=="goingOffline" and config.subscriber.onGoingOffline)
			then
				if msg.type=="goingOnline" then exe = config.subscriber.onGoingOnline end
				if msg.type=="goingOffline" then exe = config.subscriber.onGoingOffline end
				if exe then cmd = shell.escape({exe}) end
			end
			if cmd then
				local result = shrunner.execute(cmd)
				if result then
					threadman.notify({type = "info", module = "daemon", info = "Command `"..cmd.."` successfully executed"})
				else
					threadman.notify({type = "error", module = "daemon", error = "Command `"..cmd.."` failed"})
				end
			end
		end
	end
	
	threadman.unregisterListener(listener)
end

function shrunner.execute(cmd)
	local retval = os.execute(cmd)
	threadman.notify({type = "shell", ["cmd"] = cmd, ["retval"] = retval})
	return retval
end

function shrunner.popen(...)
	local retval = {io.popen(...)}
	local retvalnotify
	if not retval[1] then retvalnotify = retval end
	threadman.notify({type = "shell", ["popen"] = {...}, ["retval"] = retvalnotify})
	return unpack(retval)
end

return shrunner
