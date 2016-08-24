--- @module threadman
local threadman = {}

local config = require("config")
local luaproc = require("luaproc")
local cjson_safe = require("cjson.safe")

function threadman.setup()
	-- TODO: catch errors
	
	-- set number of worker threads, most not be too low or deadlocks will occur
	luaproc.setnumworkers(20)
	
	-- create message channel (for passing messages between threads)
	luaproc.newchannel("master")
	
	assert(luaproc.newproc(function()
		
		-- luaproc doesn't load everything by default
		io = require("io")
		os = require("os")
		table = require("table")
		string = require("string")
		math = require("math")
		debug = require("debug")
		coroutine = require("coroutine")
		
		local luaproc = require("luaproc")
		local cjson_safe = require("cjson.safe")
		
		local listeners = {}
		local numListeners = 0
		
		print("[dispatcher]", "started")
		
		local msg
		local doExit = false
		while not doExit or numListeners > 0 do
			msg = luaproc.receive("master")
			print("[dispatcher]", "msg = "..msg)
			msg = cjson_safe.decode(msg)
			if msg ~= nil then
				if msg["type"] == "removedListener" then
					listeners[msg["name"]] = nil
					numListeners = numListeners - 1
					print("[dispatcher]", "removed listener "..msg["name"])
				end
				for name, listener in pairs(listeners) do
					local doSend = false
					if listener.types then
						for k,type in pairs(listener.types) do
							if type == msg["type"] then
								doSend = true
							end
						end
					else
						doSend = true
					end
					if doSend then
						-- TODO: catch errors
						local emsg = cjson_safe.encode(msg)
						-- send message in another thread to prevent deadlocks
						luaproc.newproc(function()
							local luaproc = require("luaproc")
							luaproc.send(name, emsg)
						end)
					end
				end
				if msg["type"] == "newListener" then
					listeners[msg["name"]] = {name = msg["name"], types = msg["types"]}
					numListeners = numListeners + 1
					print("[dispatcher]", "added listener "..msg["name"])
				end
				if msg["type"] == "exit" then
					doExit = true
				end
			end
		end
		luaproc.delchannel("master")
		print("[dispatcher]", "exiting")
	end))
end

function threadman.teardown()
	-- TODO: catch errors
	-- wait for workers to finish
	-- TODO: figure out why normal exit hangs
	-- luaproc.wait()
	require('socket').sleep(5)
end

function threadman.startThread(func)
	return assert(luaproc.newproc(func))
end

function threadman.threadWrapper(modname, funcname, ...)
	
	threadman.notify({type="thread.started", ["module"]=modname, ["function"]=funcname, ["args"] = {...}})
	
	local coxpcall = require("coxpcall")
	local result = {coxpcall.pcall(require, modname)}
	if result[1] then
		local module = result[2]
		result = {coxpcall.pcall(module[funcname], ...)}
	end
	if result[1] then
		table.remove(result,1)
		threadman.notify({type="thread.finished", ["module"]=modname, ["function"]=funcname, ["retvals"]=result})
	else
		local err = result[2]
		print("!!!! THREAD CRASHED !!!!")
		print(err)
		print("!!!! THREAD CRASHED !!!!")
		threadman.notify({type="thread.crashed", ["module"]=modname, ["function"]=funcname, ["error"]=err})
		threadman.notify({type="error", ["module"]=modname, ["function"]=funcname, ["error"]=err})
		threadman.notify({type="exit",retval=1})
	end
	
end

function threadman.startThreadInFunction(modname, funcname, ...)
	
	-- TODO: switch to using notifications to propagate config variables to threads
	-- instead of running config code for each thread
	local cjson_safe = require("cjson.safe")
	local config_encoded = cjson_safe.encode(_G.config)
	local args_encoded = cjson_safe.encode({...})
	
	return threadman.startThread(function()
		-- luaproc doesn't load everything by default
		_G.io = require("io")
		_G.os = require("os")
		_G.table = require("table")
		_G.string = require("string")
		_G.math = require("math")
		_G.debug = require("debug")
		_G.coroutine = require("coroutine")
		local luaproc = require("luaproc")
		
		-- restore config global
		local cjson_safe = require("cjson.safe")
		_G.config = cjson_safe.decode(config_encoded)
		local args = cjson_safe.decode(args_encoded)
		
		local threadman = require("threadman")
		threadman.threadWrapper(modname, funcname, unpack(args))
	end)
end

function threadman.notify(msg)
	-- TODO: catch errors
	local emsg = cjson_safe.encode(msg)
	-- send message in another thread to prevent deadlocks
	luaproc.newproc(function()
		local luaproc = require("luaproc")
		luaproc.send("master", emsg)
	end)
end

threadman.ThreadListener = {channel = nil, types = {}}

function threadman.ThreadListener:new(c, t)
	o = {channel = c, types = t}
	setmetatable(o, self)
	self.__index = self
	return o
end

function threadman.ThreadListener:listen(asynchronous)
	asynchronous = asynchronous or false
	local msg, err = nil, nil
	if asynchronous then
		msg, err = luaproc.receive(self.channel, true)
	else
		msg, err = luaproc.receive(self.channel)
	end
	if msg ~= nil then
		msg = cjson_safe.decode(msg)
	end
	return msg, err
end

function threadman.ThreadListener:unregister()
	-- TODO: catch errors
	threadman.notify({type="removedListener",name=self.channel})
	luaproc.delchannel(self.channel)
end

function threadman.registerListener(name, types)
	if types and type(types) ~= "table" then types = {types} end
	-- TODO: catch errors
	luaproc.newchannel(name)
	threadman.notify({type = "newListener", ["name"] = name, ["types"] = types})
	return threadman.ThreadListener:new(name, types)
end

function threadman.unregisterListener(l)
	-- TODO: catch errors
	l:unregister()
end

return threadman
