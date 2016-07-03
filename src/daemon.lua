
local config = require("config")
local conman = require("conman")
local threadman = require("threadman")
local httpd = require("httpd")


print("[mnigs]", "starting up...")

threadman.setup()

-- start conneciton manager
threadman.startThread(function()
	-- luaproc doesn't load everything by default
	io = require("io")
	os = require("os")
	table = require("table")
	string = require("string")
	math = require("math")
	debug = require("debug")
	coroutine = require("coroutine")
	
	local conman = require("conman")
	conman.startConnectionManager()
end)

-- start interthread message queue monitor (for debugging purposes only)
threadman.startThread(function()
	-- luaproc doesn't load everything by default
	io = require("io")
	os = require("os")
	table = require("table")
	string = require("string")
	math = require("math")
	debug = require("debug")
	coroutine = require("coroutine")
	
	local threadman = require("threadman")
	local monitor = threadman.registerListener("monitor")
	local cjson_safe = require("cjson.safe")
	
	while true do
		msg = monitor:listen()
		if msg ~= nil then
			print("[monitor]", "msg = "..cjson_safe.encode(msg))
			if msg["type"] == "exit" then
				monitor.unregisterListener(listener)
				return
			end
		end
	end
end)

-- TODO: set up SIGTERM callback
-- send shutdown message
-- threadman.notify({type="exit"})


httpd.run()


threadman.teardown()

print("[mnigs]", "shutting down...")
