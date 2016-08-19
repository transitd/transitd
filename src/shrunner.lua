
--- @module shrunner
local shrunner = {}

local config = require("config")

local shell = require("lib.shell")
local db = require("db")
local threadman = require("threadman")

function shrunner.run()
	
	local listener = threadman.registerListener("shrunner")
	
	while true do
		local msg = listener:listen()
		if msg ~= nil then
			if msg["type"] == "exit" then
				break
			end
			if (config.gateway.enabled == "yes" and msg.type=="registered" and config.gateway.onRegister ~= "")
			or (config.gateway.enabled == "yes" and msg.type=="released" and config.gateway.onRelease ~= "")
			or (config.gateway.enabled ~= "yes" and msg.type=="connected" and config.subscriber.onConnect ~= "")
			or (config.gateway.enabled ~= "yes" and msg.type=="disconnected" and config.subscriber.onDisconnect ~= "")
			then
				local exe = nil
				if msg.type=="registered" then exe = config.gateway.onRegister end
				if msg.type=="released" then exe = config.gateway.onRelease end
				if msg.type=="connected" then exe = config.subscriber.onConnect end
				if msg.type=="disconnected" then exe = config.subscriber.onDisconnect end
				local session = db.lookupSession(msg.sid)
				if session and exe then
					cmd = shell.escape({exe, session.sid, session.meshIP, session.internetIPv4, internetIPv6})
					local result = os.execute(cmd)
					if result then
						threadman.notify({type = "info", module = "daemon", info = "Command `"..cmd.."` successfully executed"})
					else
						threadman.notify({type = "error", module = "daemon", error = "Command `"..cmd.."` failed"})
					end
				end
			end
		end
	end
	
	threadman.unregisterListener(listener)
end

return shrunner
