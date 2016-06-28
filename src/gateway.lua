--- @module gateway
local gateway = {}

-- gateway management utility functions

local config = require("config")
local db = require("db")
local bit32 = require("bit32")

function gateway.allocateIpv4()
	
	-- come up with random ipv4 based on settings in config
	local a1, a2, a3, a4, s = config.gateway.subscriberIpv4subnet:match("(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)")
	a1 = tonumber(a1)
	a2 = tonumber(a2)
	a3 = tonumber(a3)
	a4 = tonumber(a4)
	s = tonumber(s)
	if 0>a1 or a1>255 or 0>a2 or a2>255 or 0>a3 or a3>255 or 0>a4 or a4>255 or 0>s or s>32 then
		return nil, "Error in daemon configuration"
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
	
	-- TODO: check in database to make sure ipv4 hasn't already been allocated to another subscriber
	
	return ipv4, nil
end

function gateway.allocateIpv6()
	
	-- TODO: implement ipv6 support, need ipv6 parser to parse config setting
	ipv6 = nil
	
	return ipv6, "unimplemented"
end

function gateway.allocateSid()
	
	-- come up with unused session id
	
	-- TODO: fix race condition
	
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
		return nil, "Failed to come up with an unused session id"
	end
	
	return sid, nil
end

return gateway
