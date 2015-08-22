
local config = require("config")
local cjdnsTunnel = require("cjdnstools.tunnel")

local bit32 = require("bit32")
local socket = require("socket")

-- need better random numbers
math.randomseed(socket.gettime()*1000)

local interface = {
	echo = function (msg) return msg end,
	
	gatewayInfo = function()
		return { name = config.server.name, methods = {{name = "cjdns"}} }
	end,
	
	requestConnection = function(method, options)
		if (method == "cjdns") and (config.cjdns.serverSupport == "yes") then
			if options.key then
				
				-- come up with random ipv4
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
				
				local response, err = cjdnsTunnel.addKey(options.key, ipv4)
				if err then
					return { success = false, errorMsg = "Error adding cjdns key at gateway: " .. err }
				else
					return { success = true, timeout = config.cjdns.tunnelTimeout }
				end
			else
				return { success = false, errorMsg = "Key option is required" }
			end
		end
		
		return { success = false, errorMsg = "Method not supported" }
  end,
  
  releaseConnection = function(method, options)
		if method == "cjdns" and (config.cjdns.serverSupport == "yes") then
			if options.key then
				local response, err = cjdnsTunnel.removeKey(options.key)
				if err then
					return { success = false, errorMsg = "Error adding cjdns key at gateway: " .. err }
				else
					return { success = true, timeout = config.cjdns.tunnelTimeout }
				end
			else
				return { success = false, errorMsg = "Key option is required" }
			end
		end
		
		return { success = false, errorMsg = "Method not supported" }
  end
}

return interface
