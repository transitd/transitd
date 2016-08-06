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
	local ipv4, cidr4, ipv6, cidr6
	local subnet4, error4 = gateway.allocateIpv4();
	local subnet6, error5 = gateway.allocateIpv6();
	if error4 ~= nil and error6 ~= nil then
		if error4 ~= nil then
			return { success = false, errorMsg = error4 }
		end
		if error6 ~= nil then
			return { success = false, errorMsg = error6 }
		end
	end
	if not subnet4 and not subnet6 then
		return { success = false, errorMsg = "Failed to allocate IP address(s)" }
	end
	if subnet4 then
		ipv4, cidr4 = unpack(subnet4)
	end
	if subnet6 then
		ipv6, cidr6 = unpack(subnet6)
	end
	
	local sid, error = gateway.allocateSid(sid)
	if error ~= nil then
		return { success = false, errorMsg = error, temporaryError = true }
	end
	
	local response, err = tunnel.addKey(key, ipv4, ipv6)
	if err then
		return { success = false, errorMsg = "Error adding cjdns key at gateway: " .. err }
	else
		
		local timeout = config.gateway.subscriberTimeout
		
		db.registerSubscriberSession(sid, name, method, subscriberip, port, ipv4, ipv6, timeout)
		db.registerSubscriberSessionCjdnsKey(sid, key)
		
		threadman.notify({type = "subscriber.auth", ["sid"] = sid, cjdnskey = key})
		
		return {
				success = true,
				['timeout'] = timeout,
				['ipv4'] = ipv4,
				['ipv6'] = ipv6,
				['cidr4'] = cidr4,
				['cidr6'] = cidr6,
				["ipv4gateway"] = config.gateway.subscriberIpv4gateway,
				["ipv6gateway"] = config.gateway.subscriberIpv6gateway,
				["key"] = mykey
			}
	end
	
end

function cjdns.renewConnection(sid)
	-- nothing needs to be done
	return true, nil
end

function cjdns.releaseConnection(sid)
	if sid then
		local key, err = db.getCjdnsSubscriberKey(sid)
		if err then
			threadman.notify({type = "subscriber.deauth.fail", ["sid"] = sid, method = "cjdns", cjdnskey = key, error = err})
			return { success = false, errorMsg = "Error releasing connection: " .. err }
		else
			local response, err = tunnel.deauthorizeKey(key)
			if err then
				threadman.notify({type = "subscriber.deauth.fail", ["sid"] = sid, method = "cjdns", cjdnskey = key, error = err})
				return { success = false, errorMsg = "Error releasing connection: " .. err }
			else
				db.deactivateSession(sid)
				threadman.notify({type = "subscriber.deauth", ["sid"] = sid, method = "cjdns", cjdnskey = key})
				return { success = true }
			end
		end
	else
		local err = "'sid' option is invalid"
		threadman.notify({type = "subscriber.deauth.fail", ["sid"] = sid, method = "cjdns", error = err})
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

return cjdns
