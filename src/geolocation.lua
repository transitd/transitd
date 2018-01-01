--[[
@file geolocation.lua
@license The MIT License (MIT)
@copyright 2017 William Fleurant
--]]

--- @module geolocation

local geolocation = {}

local config = require("config")
local shell = require("lib.shell")
local threadman = require("threadman")
local support = require("support")

function geolocation.run()

    local listener = threadman.registerListener("geolocation",{"exit", "heartbeat"})
	local lastTime = 0
    while true do
        local msg = listener:listen()
        if msg ~= nil then
            if msg["type"] == "exit" then
                break
            end
        end
        if msg["type"] == "heartbeat" then
			local time = os.time()
			if time > lastTime + 30 then
				geolocation.updateLocation()
				lastTime = time
			end
		end
    end

    threadman.unregisterListener(listener)

end

function geolocation.updateLocation()
    local modules = support.getGeo()
    local bestlocation = {}
    for geomod, geo in pairs(modules) do
        local module = require("geo."..geo.module)
        -- TODO: use algo that takes in multiple readings
        -- and returns single higher accuracy reading
        bestlocation = module.queryLocation()
    end

    threadman.setShared('geolocation', bestlocation)

end

function geolocation.getLocation()
    return threadman.getShared('geolocation')
end


