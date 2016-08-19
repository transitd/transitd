
--- @module monitor
local monitor = {}

local threadman = require("threadman")
local cjson_safe = require("cjson.safe")

function monitor.run()
	
	local listener = threadman.registerListener("monitor")
	
	while true do
		local msg = listener:listen()
		if msg ~= nil then
			print("[monitor]", "msg = "..cjson_safe.encode(msg))
			if msg["type"] == "exit" then
				break
			end
		end
	end
	
	threadman.unregisterListener(listener)
end

return monitor
