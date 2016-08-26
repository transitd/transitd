--[[
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module rpc-interface.cjdns
local cjdns = {}

local config = require("config")
local gateway = require("gateway")
local db = require("db")
local scanner = require("cjdnstools.scanner")
local tunnel = require("cjdnstools.tunnel")
local threadman = require("threadman")
local rpc = require("rpc")
local network = require("network")

function cjdns.requestConnection(sid, name, port, method, options)
	
	local port = tonumber(port)
	local subscriberip = tostring(cgilua.servervariable("REMOTE_ADDR"))
	
	if options.key == nil then
		return { success = false, errorMsg = "Key option is required" }
	end
	
	local key = tostring(options.key)
	
	local mykey, err = scanner.getMyKey()
	if err then
		return {success = false, errorMsg = "Failed to get my own key: " .. err}
	elseif mykey == nil then
		return {success = false, errorMsg = "Failed to get my own key: Unknown error"}
	end
	
	-- allocate ips based on settings in config
	
	-- IPv4
	local ipv4, cidr4, ipv6, cidr6
	local subnet4, err = gateway.allocateIpv4();
	if err then
		return { success = false, errorMsg = err }
	end
	if not subnet4 then
		return { success = false, errorMsg = "Failed to allocate IPv4 address" }
	end
	ipv4, cidr4 = unpack(subnet4)
	
	-- IPv6
	if config.gateway.ipv6support == "yes" then
		local subnet6, err = gateway.allocateIpv6();
		if err then
			return { success = false, errorMsg = err }
		end
		if not subnet6 then
			return { success = false, errorMsg = "Failed to allocate IPv6 address" }
		end
		ipv6, cidr6 = unpack(subnet6)
	end
	
	local sid, error = gateway.allocateSid(sid)
	if error ~= nil then
		return { success = false, errorMsg = error, temporaryError = true }
	end
	
	local response, err = tunnel.addKey(key, ipv4, ipv6)
	if err then
		return { success = false, errorMsg = "Error adding cjdns key at gateway: " .. err }
	end
	
	local timeout = config.gateway.subscriberTimeout
	
	db.registerSubscriberSession(sid, name, method, subscriberip, port, ipv4, ipv6, timeout)
	db.registerSubscriberSessionCjdnsKey(sid, key)
	
	local interface, err = tunnel.getInterface()
	if interface then interface = interface.name end
	threadman.notify({type = "registered", ["sid"] = sid, ["interface"] = interface})
	
	return {
			success = true,
			['timeout'] = timeout,
			['ipv4'] = ipv4,
			['ipv6'] = ipv6,
			['cidr4'] = cidr4,
			['cidr6'] = cidr6,
			["ipv4gateway"] = config.gateway.ipv4gateway,
			["ipv6gateway"] = config.gateway.ipv6gateway,
			["key"] = mykey
		}
end

function cjdns.renewConnection(sid)
	-- nothing needs to be done
	return true, nil
end

function cjdns.releaseConnection(sid)
	if sid then
		local key, err = db.getCjdnsSubscriberKey(sid)
		if err then
			threadman.notify({type = "error", module = "cjdns", ["function"] = "releaseConnection", ["sid"] = sid, error = err})
			return { success = false, errorMsg = "Error releasing connection: " .. err }
		else
			db.deactivateSession(sid)
			
			local interface, err = tunnel.getInterface()
			if interface then interface = interface.name end
			threadman.notify({type = "released", ["sid"] = sid, ["interface"] = interface})
			
			local response, err = tunnel.deauthorizeKey(key)
			if err then
				threadman.notify({type = "subscriber.deauth.fail", ["sid"] = sid, method = "cjdns", cjdnskey = key, error = err})
				return { success = false, errorMsg = "Error releasing connection: " .. err }
			else
				return { success = true }
			end
		end
	else
		local err = "'sid' option is invalid"
		threadman.notify({type = "error", module = "cjdns", ["function"] = "releaseConnection", ["sid"] = sid, error = err})
		return { success = false, errorMsg = err }
	end
end

function cjdns.connectTo(ip, port, method, sid)
	
	sid = sid or gateway.allocateSid()
	
	local node = rpc.getProxy(ip, port)
	
	local mykey, err = scanner.getMyKey()
	if err then
		return {success = false, errorMsg = "Failed to get my own key: " .. err}
	elseif mykey == nil then
		return {success = false, errorMsg = "Failed to get my own key: Unknown error"}
	else
		local result, err = node.requestConnection(sid, config.main.name, config.daemon.rpcport, "cjdns", {key = mykey})
		if err then
			return {success = false, errorMsg = err}
		elseif result.errorMsg then
			return {success = false, errorMsg = result.errorMsg}
		elseif result.success == false then
			return {success = false, errorMsg = "Unknown error"}
		else
			if result.key == nil then
				return {success = false, errorMsg = "Gateway did not send its key"}
			end
			
			local success, err = tunnel.connect(result.key)
			if not success then
				if err then
					return {success = false, errorMsg = "Failed to get local cjdroute to connect to gateway: "..err}
				else
					return {success = false, errorMsg = "Failed to get local cjdroute to connect to gateway: Unknown error"}
				end
			end
			
			local subnet4, ipv4, cidr4, subnet6, ipv6, cidr6, ipv4gateway, ipv6gateway, err
			
			if not result.ipv4 and not result.ipv6 then
				return {success = false, errorMsg = "Failed to obtain IPv4 and IPv6 addresses from gateway"}
			end
			if result.ipv4 and not result.cidr4 then
				return {success = false, errorMsg = "Failed to obtain IPv4 CIDR from gateway"}
			end
			if result.ipv6 and not result.cidr6 then
				return {success = false, errorMsg = "Failed to obtain IPv6 CIDR from gateway"}
			end
			
			-- make sure addresses are valid
			if result.ipv4 then
				subnet4, err = network.parseIpv4Subnet(result.ipv4.."/"..result.cidr4)
				if err then
					return {success = false, errorMsg = "Failed to parse IPv4 address"}
				end
				ipv4, cidr4 = unpack(subnet4)
				ipv4 = network.ip2string(ipv4)
				
				ipv4gateway, err = network.parseIpv4(result.ipv4gateway)
				if err then
					return {success = false, errorMsg = "Failed to parse gateway IPv4 address"}
				end
				if not ipv4gateway then
					return {success = false, errorMsg = "No gateway IPv4 address provided"}
				end
				ipv4gateway = network.ip2string(ipv4gateway)
			end
			if result.ipv6 then
				subnet6, err = network.parseIpv6Subnet(result.ipv6.."/"..result.cidr6)
				if err then
					return {success = false, errorMsg = "Failed to parse IPv6 address"}
				end
				ipv6, cidr6 = unpack(subnet6)
				ipv6 = network.ip2string(ipv6)
				
				ipv6gateway, err = network.parseIpv6(result.ipv6gateway)
				if err then
					return {success = false, errorMsg = "Failed to parse gateway IPv6 address"}
				end
				if not ipv6gateway then
					return {success = false, errorMsg = "No gateway IPv6 address provided"}
				end
				ipv6gateway = network.ip2string(ipv6gateway)
			end
			
			-- overwrite values with parsed data
			result.ipv4 = ipv4
			result.ipv6 = ipv6
			result.cidr4 = cidr4
			result.cidr6 = cidr6
			result.ipv4gateway = ipv4gateway
			result.ipv6gateway = ipv6gateway
			
			local ret, err = tunnel.subscriberSetup(result)
			if err then
				return {success = false, errorMsg = err}
			end
			
			return result
		end
	end
end

function cjdns.disconnect(sid)
	
	local session, err = db.lookupSession(sid)
	
	local ip = session.meshIP
	local port = session.port
	
	local node = rpc.getProxy(ip, port)
	
	if session.method == "cjdns" then
		tunnel.subscriberTeardown(session)
	end
	
	return node.releaseConnection(sid)
end

return cjdns
