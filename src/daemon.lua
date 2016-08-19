
local config = require("config")
local threadman = require("threadman")
local httpd = require("httpd")
local scanner = require("scanner")

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

-- start interthread message queue monitor (for debugging purposes only)
threadman.startThreadInFunction('monitor', 'run')

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


httpd.run()


threadman.teardown()

print("[mnigs]", "shutting down...")
