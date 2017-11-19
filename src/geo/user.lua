--[[
@file user.lua
@license The MIT License (MIT)
@copyright 2017 transitd
--]]

--- @module user
local user = {}
local config = require("config")

function user.getName()
    return "User Defined Location in Configuration File"
end

function user.checkSupport()
    return true
end

function user.queryLocation()
    return {
        latitude = config.main.latitude,
        longitude = config.main.longitude,
        altitude = config.main.altitude
    }
end

return user