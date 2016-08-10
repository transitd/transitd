
local config = require("config")
local conman = require("conman")
local threadman = require("threadman")
local httpd = require("httpd")

print("[mnigs]", "starting up...")

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

-- TODO: switch to using notifications to propagate config variables to threads
-- instead of running config code for each thread
local cjson_safe = require("cjson.safe")
local config_encoded = cjson_safe.encode(config)

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
	local luaproc = require("luaproc")
	
	local cjson_safe = require("cjson.safe")
	_G.config = cjson_safe.decode(config_encoded)
	
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
	local luaproc = require("luaproc")
	
	local cjson_safe = require("cjson.safe")
	_G.config = cjson_safe.decode(config_encoded)
	
	local threadman = require("threadman")
	local monitor = threadman.registerListener("monitor")
	
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
