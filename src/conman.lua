--[[
@file conman.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module conman
local conman = {}

local config = require("config")
local db = require("db")
local threadman = require("threadman")
local rpc = require("rpc")
local rpcInterface = require("rpc-interface")
local support = require("support")

function conman.heartbeat()
	
	local sessions, err = db.getActiveSessions()
	if err then
		threadman.notify({type = "error", module = "conman", ["function"] = 'subscriberManager', error = err})
	else
		for k,session in pairs(sessions) do
			if session.suite then
				
				local suites = support.getSuites()
				local suite = suites[session.suite]
				if not suite then
					threadman.notify({type = "error", module = "conman", ["function"] = 'heartbeat', error = "Local suite disappeared"})
				end
				local module = require("tunnels."..suite.tunnel.module)
				local result, err = module.maintainConnection(session)
				if err then
					threadman.notify({type = "error", module = "conman", ["function"] = 'heartbeat', error = err})
				end
			end
		end
	end
	
	if config.gateway.enabled == "yes" then
		conman.subscriberManager()
	else
		conman.gatewayManager()
	end
	
end

local conManTs = 0

function conman.subscriberManager()
	
	local sinceTimestamp = conManTs
	conManTs = os.time()
	
	-- remove timed out subscriber keys from cjdroute
	local sessions, err = db.getTimingOutSubscribers(sinceTimestamp)
	if err == nil and sessions == nil then
		err = "Unexpected subscriber list query result"
	end
	if err then
		threadman.notify({type = "error", module = "conman", ["function"] = 'subscriberManager', error = err})
		return
	end
	if sessions then
		for k,session in pairs(sessions) do
			
			local result, err = rpcInterface.releaseConnection(session.sid)
			if err then
				threadman.notify({type = "error", module = "conman", ["function"] = 'subscriberManager', error = err})
			elseif not result then
				threadman.notify({type = "error", module = "conman", ["function"] = 'subscriberManager', error = "Unknown error"})
			elseif not result.success and result.errorMsg then
				threadman.notify({type = "error", module = "conman", ["function"] = 'subscriberManager', ["error"] = result.errorMsg})
			elseif not result.success then
				threadman.notify({type = "error", module = "conman", ["function"] = 'subscriberManager', ["error"] = "Unknown error"})
			end
			
			threadman.notify({type = "subscriberSessionTimedOut", ["sid"] = session.sid})
		end
	end
end

function conman.gatewayManager()
	
	local currentTimestamp = os.time()
	local gracePeriod = 10;
	
	local sessions, err = db.getLastActiveSessions()
	if err == nil and sessions == nil then
		err = "Unexpected session list query result"
	end
	if err then
		threadman.notify({type = "error", module = "conman", error = err})
		return
	end
	
	for k, session in pairs(sessions) do
		if session.subscriber == 0 and session.active == 1 then
			if currentTimestamp > session.timeoutTimestamp then
				
				local result, err = rpcInterface.disconnect(session.sid)
				if err then
					threadman.notify({type = "error", module = "conman", ["function"] = 'gatewayManager', error = err})
				elseif not result then
					threadman.notify({type = "error", module = "conman", ["function"] = 'gatewayManager', error = "Unknown error"})
				elseif not result.success and result.errorMsg then
					threadman.notify({type = "error", module = "conman", ["error"] = result.errorMsg})
				elseif not result.success then
					threadman.notify({type = "error", module = "conman", ["error"] = "Unknown error"})
				end
				
			elseif currentTimestamp > session.timeoutTimestamp-gracePeriod then
				
				local proxy = rpc.getProxy(session.meshIP, session.port)
				
				local result, err = proxy.renewConnection(session.sid)
				if err then
					threadman.notify({type = "error", module = "conman", ["function"] = 'gatewayManager', ["error"] = err})
				elseif not result then
					threadman.notify({type = "error", module = "conman", ["function"] = 'gatewayManager', ["error"] = "Unknown error"})
				elseif not result.success and result.errorMsg then
					threadman.notify({type = "error", module = "conman", ["function"] = 'gatewayManager', ["error"] = result.errorMsg})
				elseif not result.success then
					threadman.notify({type = "error", module = "conman", ["function"] = 'gatewayManager', ["error"] = "Unknown error"})
				else
					db.updateSessionTimeout(session.sid, result.timeoutTimestamp)
					threadman.notify({type = "renewedGatewaySession", ["sid"] = session.sid, ["timeoutTimestamp"] = result.timeoutTimestamp})
				end
			end
		end
	end
end

function conman.run()
	local socket = require("socket")
	local listener = threadman.registerListener("conman",{"exit","heartbeat"})
	local lastTime = 0
	while true do
		local msg = {};
		while msg ~= nil do
			msg = listener:listen()
			if msg ~= nil then
				if msg["type"] == "exit" then
					threadman.unregisterListener(listener)
					return
				end
			end
			if msg["type"] == "heartbeat" then
				local time = os.time()
				if time > lastTime + 2 then
					conman.heartbeat()
					lastTime = time
				end
			end
		end
	end
end

return conman
