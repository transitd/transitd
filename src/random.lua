--[[
@file random.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module random
local random = {}

-- seed PRNG
local seed = 0
local urandom = io.open("/dev/urandom")
if urandom then
	local bit32 = require("bit32")
	local bytes = 4
	local data = {urandom:read(bytes):byte(1,bytes)}
	for k,v in pairs(data) do
		seed = bit32.lshift(seed,8)
		seed = bit32.bxor(seed,v)
	end
	urandom:close()
end
local socket = require("socket")
local mstimestamp = socket.gettime()
seed = seed + (mstimestamp-math.floor(mstimestamp))*4294967296
math.randomseed(seed)

function random.mktoken(len)
	
	local idchars = "1234567890abcdefghijklmnopqrstuvwxyz"
	local token = ""
	for i=1,len do
		local char = math.random(1,string.len(idchars))
		token = token .. string.sub(idchars,char,char)
	end
	if token == "" then
		return nil, "Failed to make a random token"
	end
	
	return token, nil
end

return random
