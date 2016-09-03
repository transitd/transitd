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
local threadman = require("threadman")
local httpd = require("httpd")
local scanner = require("scanner")
local socket = require("socket")

print("[transitd]", "starting up...")

-- configure gateway functionality
if config.gateway.enabled == "yes" then
	
	if config.cjdns.gatewaySupport == "yes" and config.cjdns.tunnelSupport == "yes" then
		
		local network = require("network")
		
		local interface, err = network.getIpv4TransitInterface()
		if err then
			error("Failed to determine IPv4 transit interface! Cannot start in gateway mode. ("..err..")")
		end
		if not interface then
			error("Failed to determine IPv4 transit interface! Cannot start in gateway mode.")
		end
		
		if config.gateway.ipv6support == "yes" then
			
			local interface, err = network.getIpv6TransitInterface()
			if err then
				error("Failed to determine IPv6 transit interface! Please disable ipv6support in the configuration file. ("..err..")")
			end
			if not interface then
				error("Failed to determine IPv6 transit interface! Please disable ipv6support in the configuration file.")
			end
		end
		
		local tunnel = require("cjdnstools.tunnel")
		local result, err = tunnel.gatewaySetup()
		if err then
			error("Failed to set up cjdns tunnel gateway: "..err)
		end
	end
	
end

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
local listener = threadman.registerListener("main",{"exit","error","info"})
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
		end
	end
	
	if msg ~= nil and msg["type"] == "exit" then break end
	
	socket.sleep(1)
	
	threadman.notify({type = "heartbeat", ["time"] = os.time()})
end
threadman.unregisterListener(listener)

print("[transitd]", "shutting down...")

threadman.teardown()

print("[transitd]", "exiting.")

os.exit(retval)
