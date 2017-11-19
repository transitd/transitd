--[[
@file geolocation.lua
@license The MIT License (MIT)
@copyright 2017 transitd
--]]

--- @module geolocation

local geolocation = {}

local config = require("config")
local shell = require("lib.shell")
local threadman = require("threadman")
local support = require("support")

function geolocation.run()


    local listener = threadman.registerListener("geolocation",{"exit", "heartbeat"}

    while true do
        local msg = listener:listen()
        if msg ~= nil then
            if msg["type"] == "exit" then
                break
            end
        end
    end

    if cmd then

        local result = shrunner.execute(cmd)

        if result then
            threadman.notify({type = "info", module = "daemon", info = "Command `"..cmd.."` successfully executed"})
        else
            threadman.notify({type = "error", module = "daemon", error = "Command `"..cmd.."` failed"})
        end
    end

    threadman.unregisterListener(listener)
end

function geolocation.updateLocation()

    local modules = support.getGeo()
    local bestlocation = []
    for geomod, geo in pairs(modules) do
        bestlocation = module.queryLocation()
    end

    threadman.setShared('geolocation', bestlocation)

end


function geolocation.getLocation()
    return threadman.getShared('geolocation')
end


