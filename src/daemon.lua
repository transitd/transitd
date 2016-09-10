--[[

transitd daemon main file

@file daemon.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author William Fleurant <william@netblazr.com>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 William Fleurant
@copyright 2016 Serg

--]]

local config = require("config")
local db = require("db")
local threadman = require("threadman")
local scanner = require("scanner")
local socket = require("socket")

local gateway = require("gateway")
local gatewayEnabled = config.gateway.enabled == "yes";

local start = true
while start do
	
	print("[transitd]", "starting up...")
	
	db.prepareDatabase()
	db.purge()
	
	-- configure gateway functionality
	if gatewayEnabled then gateway.setup() end
	
	threadman.setup()
	
	-- start conneciton manager
	threadman.startThreadInFunction('conman', 'run')
	
	-- start shell script runner
	if (config.gateway.enabled == "yes" and (config.gateway.onRegister ~= "" or config.gateway.onRelease ~= ""))
	or (config.gateway.enabled ~= "yes" and (config.subscriber.onConnect ~= "" or config.subscriber.onDisconnect ~= "")) then
		threadman.startThreadInFunction('shrunner', 'run')
	end
	
	-- start network scan if one hasn't already been started
	scanner.startScan()
	
	-- TODO: set up SIGTERM callback
	-- send shutdown message
	-- threadman.notify({type="exit"})
	
	-- start http server
	threadman.startThreadInFunction('httpd', 'run')
	
	-- start monitor thread
	threadman.startThreadInFunction('monitor', 'run')
	
	-- wait until exit message is issued, send heartbeats
	local retval = 0
	local listener = threadman.registerListener("main",{"exit","error","info","config"})
	while true do
		
		local msg = "";
		while msg ~= nil do
			msg = listener:listen(true)
			if msg ~= nil then
				if msg["type"] == "exit" then
					if msg["retval"] then retval = msg["retval"] end
					break
				end
				if msg["type"] == "error" or msg["type"] == "info" then
					print("[transitd]", msg["type"])
					for k,v in pairs(msg) do
						if k ~= "type" then
							print("["..msg["type"].."]", k, v)
						end
					end
				end
				if msg["type"] == "config" then
					set_config(msg.setting, msg.value)
				end
			end
		end
		
		if msg ~= nil and msg["type"] == "exit" then
			start = msg["restart"]
			break
		end
		
		socket.sleep(1)
		
		threadman.notify({type = "heartbeat", ["time"] = os.time()})
	end
	
	if gatewayEnabled then gateway.teardown() end
	
	threadman.unregisterListener(listener)
	
	print("[transitd]", "shutting down...")
	
	threadman.teardown()
	
end

print("[transitd]", "exiting.")

os.exit(retval)
