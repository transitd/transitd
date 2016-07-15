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
		if blockingCalls[id] ~= nil then
			id = ""
		else
			break
		end
	end
	if id == "" then
		return nil, "Failed to come up with an unused call id"
	end
	
	blockingCalls[id] = {callId = id}
	
	return id, nil
end

function rpc.processBlockingCallMsg(msg)
	local id = msg.callId
	if blockingCalls[id] and msg.type=="nonblockingcall.complete" then
		blockingCalls[id]["result"] = msg.result
		blockingCalls[id]["err"] = msg.err
	end
end

function rpc.isBlockingCallDone(id)
	return blockingCalls[id] and (blockingCalls[id].result ~= nil or blockingCalls[id].err ~= nil)
end

function rpc.returnBlockingCallResult(id)
	if blockingCalls[id] and rpc.isBlockingCallDone(id) then
		return blockingCalls[id].result, blockingCalls[id].err
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

return rpc
