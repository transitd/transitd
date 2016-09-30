--[[
@file free.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module free
local free = {}

function free.getName()
	return "Free"
end

function free.checkSupport(network, tunnel, payment)
	return true
end

return free
