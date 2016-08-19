--- @module rpc
local rpc = {}

local copas = require("copas")
local socket = require("socket")

local jsonrpc = require("json.rpc")
jsonrpc.setTimeout(10)

local threadman = require("threadman")

local config = require("config")

function rpc.getRawProxy(ip, port)
	port = port or config.daemon.rpcport
	if string.find(ip, ":") ~= nil then
		ip = "[" .. tostring(ip) .. "]"
	end
	local url = "http://" .. tostring(ip) .. ":" .. tostring(port) .. "/jsonrpc"
	return jsonrpc.proxy(url)
end

local blockingCalls = {}

-- needed for a blocking call wrapper, this allows non-blocking json rpc calls
-- wrapper needs to start a thread to process the call and returns the call id
function rpc.allocateCallId()
	
	-- come up with unused call id
	
	local idchars = "1234567890abcdefghijklmnopqrstuvwxyz"
	local id = ""
	for t=0,5 do
		for i=1,32 do
			local char = math.random(1,string.len(idchars))
			id = id .. string.sub(idchars,char,char)
		end
	end
	if id == "" then
		return nil, "Failed to come up with an unused call id"
	end
	
	return id, nil
end

function rpc.processBlockingCallMsg(msg)
	local id = msg.callId
	if msg.type=="nonblockingcall.complete" then
		blockingCalls[id] = {callId = id, result = msg.result, msg.err}
	end
end

function rpc.isBlockingCallDone(id)
	return blockingCalls[id] ~= nil
end

function rpc.returnBlockingCallResult(id)
	if rpc.isBlockingCallDone(id) then
		local result = blockingCalls[id].result
		local err = blockingCalls[id].err
		blockingCalls[id] = nil
		return result, err
	end
	return nil
end

-- a polling wrapper, this allows non-blocking json rpc
function rpc.getProxy(ip, port)
	local proxy = {}
	local meta = {
		__index = function(self, method)
			return function(...)
				local proxy = rpc.getRawProxy(ip, port)
				local called, result, err = pcall(proxy[method], ...)
				if called ~= true then
					return nil, result
				end
				if err then
					return nil, err
				end
				if type(result)=="table" and result.callId then
					local id = result.callId
					-- poll for result until it arrives
					while type(result)=="table" and result.callId ~= nil do
						socket.sleep(2)
						called, result, err = pcall(proxy.pollCallStatus, id)
						if called ~= true then
							return nil, result
						end
						if err then
							return nil, err
						end
					end
				end
				return result, nil
			end
		end
	}
	setmetatable(proxy, meta)
	return proxy
end

function rpc.wrapBlockingCall(modname, funcname, ...)
	
	local callId, err = rpc.allocateCallId()
	if err ~= nil then
		return nil, err
	end
	
	threadman.startThreadInFunction('rpc', 'blockingCallWrapper', callId, modname, funcname, ...)
	
	return callId, nil
end

function rpc.blockingCallWrapper(callId, modname, funcname, ...)
	
	local threadman = require("threadman")
	
	threadman.notify({type="nonblockingcall.started", ["callId"]=callId, ["module"]=modname, ["function"]=funcname, ["args"] = {...}})
	
	local coxpcall = require("coxpcall")
	local result = {coxpcall.pcall(require, modname)}
	if result[1] then
		local module = result[2]
		result = {coxpcall.pcall(module[funcname], ...)}
	end
	if result[1] then
		threadman.notify({type="nonblockingcall.complete", ["callId"]=callId, ["result"]=result[2], ["err"]=result[3]})
	else
		local err = result[2]
		print("!!!! ERROR !!!!")
		print(err)
		print("!!!! ERROR !!!!")
		threadman.notify({type="nonblockingcall.complete", ["callId"]=callId, ["result"]=nil, ["err"]=err})
		threadman.notify({type="error", ["module"]=modname, ["function"]=funcname, ["error"]=err})
	end
	
end

return rpc
