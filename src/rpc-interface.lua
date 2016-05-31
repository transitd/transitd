
local config = require("config")
local cjdnsTunnel = require("cjdnstools.tunnel")

local bit32 = require("bit32")
local socket = require("socket")

local db = require("db")

-- need better random numbers
math.randomseed(socket.gettime()*1000)

local interface = {
	echo = function (msg) return msg end,
	
	gatewayInfo = function()
		local methods = {}
		
		if config.cjdns.serverSupport == "yes" then
			methods[#methods+1] = {name = "cjdns"}
		end
		
		return { name = config.server.name, ['methods'] = methods }
	end,
	
	requestConnection = function(name, method, options)
		
		-- check maxclients config to make sure we are not registering more clients than needed
		local activeClients = db.getActiveClients()
		if #activeClients > config.server.maxConnections then
			return { success = false, errorMsg = "Too many users", temporaryError = true }
		end
		
		-- TODO: fix IPv6
		local userip = cgilua.servervariable("REMOTE_ADDR")
		
		-- check to make sure the user isn't already registered
		local activeClient = db.lookupActiveClientByIp(userip)
		if activeClient ~= nil then
			if activeClient.method ~= method then
				return { success = false, errorMsg = "User is already registered with a different method", temporaryError = true }
			else
				local timestamp = os.time()
				return { success = true, timeout = activeClient.timeout_timestamp - timestamp, ['ipv4'] = activeClient.internetIPv4, ['ipv6'] = activeClient.internetIPv6 }
			end
		end
		
		if (method == "cjdns") and (config.cjdns.serverSupport == "yes") then
			if options.key then
				
				-- come up with random ipv4 based on settings in config
				local a1, a2, a3, a4, s = config.cjdns.tunnelIpv4subnet:match("(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)")
				a1 = tonumber(a1)
				a2 = tonumber(a2)
				a3 = tonumber(a3)
				a4 = tonumber(a4)
				s = tonumber(s)
				if 0>a1 or a1>255 or 0>a2 or a2>255 or 0>a3 or a3>255 or 0>a4 or a4>255 or 0>s or s>32 then
					print("Invalid IPv4 subnet in cjdns tunnel configuration!  New client registration failed.")
					return { success = false, errorMsg = "Error in server configuration" }
				end
				local ipv4 = 0;
				ipv4 = bit32.bor(ipv4,a1)
				ipv4 = bit32.lshift(ipv4,8)
				ipv4 = bit32.bor(ipv4,a2)
				ipv4 = bit32.lshift(ipv4,8)
				ipv4 = bit32.bor(ipv4,a3)
				ipv4 = bit32.lshift(ipv4,8)
				ipv4 = bit32.bor(ipv4,a4)
				
				ipv4 = bit32.band(ipv4, bit32.lshift(bit32.bnot(0), 32-s))
				ipv4 = bit32.bor(ipv4, math.random(0, 2^(32-s)-1))
				
				a4 = bit32.band(0xFF,ipv4)
				ipv4 = bit32.rshift(ipv4,8)
				a3 = bit32.band(0xFF,ipv4)
				ipv4 = bit32.rshift(ipv4,8)
				a2 = bit32.band(0xFF,ipv4)
				ipv4 = bit32.rshift(ipv4,8)
				a1 = bit32.band(0xFF,ipv4)
				local ipv4 = a1.."."..a2.."."..a3.."."..a4;
				
				-- TODO: implement ipv6 support, need ipv6 parser to parse config setting
				ipv6 = nil
				
				-- come up with session id
				local sidchars = "1234567890abcdefghijklmnopqrstuvwxyz"
				local sid = ""
				for t=0,5 do
					for i=1,32 do
						local char = math.random(1,string.len(sidchars))
						sid = sid .. string.sub(sidchars,char,char)
					end
					if db.lookupClientBySession(sid) ~= nil then
						sid = ""
					else
						break
					end
				end
				if sid == "" then
					return { success = false, errorMsg = "Failed to come up with an unused session id", temporaryError = true }
				end
				
				local response, err = cjdnsTunnel.addKey(options.key, ipv4, ipv6)
				if err then
					return { success = false, errorMsg = "Error adding cjdns key at gateway: " .. err }
				else
					
					db.registerClient(sid, name, method, userip, nil, ipv4, ipv6)
					db.registerCjdnsClient(sid, options.key)
					
					return { success = true, timeout = config.server.clientTimeout, ['ipv4'] = ivp4, ['ipv6'] = ipv6 }
				end
			else
				return { success = false, errorMsg = "Key option is required" }
			end
		end
		
		return { success = false, errorMsg = "Method not supported" }
  end,
  
  renewConnection = function(sid)
  	return { success = false, errorMsg = "Not implemented yet" }
  end,
  
  releaseConnection = function(method, options)
		if method == "cjdns" and (config.cjdns.serverSupport == "yes") then
			if options.sid then
				local key, error = db.getCjdnsClientKey(options.sid)
				if error then
					return { success = false, errorMsg = "Error releasing connection: " .. err }
				else
					local response, err = cjdnsTunnel.deauthorizeKey(key)
					if err then
						return { success = false, errorMsg = "Error releasing connection: " .. err }
					else
						return { success = true, timeout = config.server.clientTimeout }
					end
				end
			else
				return { success = false, errorMsg = "Sid option is required" }
			end
		end
		
		return { success = false, errorMsg = "Method not supported" }
  end
}

return interface
