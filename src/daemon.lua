
local config = require("config")
local conman = require("conman")
local threadman = require("threadman")
local httpd = require("httpd")
local scanner = require("scanner")
local db = require("db")

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
	local config = require("config")
	
	local threadman = require("threadman")
	local listener = threadman.registerListener("monitor")
	
	while true do
		local msg = listener:listen()
		if msg ~= nil then
			print("[monitor]", "msg = "..cjson_safe.encode(msg))
			if msg["type"] == "exit" then
				threadman.unregisterListener(listener)
				return
			end
		end
	end
end)

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
	local config = require("config")
	
	local conman = require("conman")
	conman.startConnectionManager()
end)


-- start shell script runner
if (config.gateway.enabled == "yes" and (config.gateway.onRegister ~= "" or config.gateway.onRelease ~= ""))
or (config.gateway.enabled ~= "yes" and (config.subscriber.onConnect ~= "" or config.subscriber.onDisconnect ~= "")) then
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
		local config = require("config")
		
		local shell = require("lib.shell")
		local db = require("db")
		local threadman = require("threadman")
		
		local listener = threadman.registerListener("monitor")
		
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
		return
	end)
end

-- start network scan if one hasn't already been started
scanner.startScan()



-- TODO: set up SIGTERM callback
-- send shutdown message
-- threadman.notify({type="exit"})


httpd.run()


threadman.teardown()

print("[mnigs]", "shutting down...")
