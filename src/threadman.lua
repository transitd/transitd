--- @module threadman
local threadman = {}

local config = require("config")
local luaproc = require("luaproc")
local cjson_safe = require("cjson.safe")

function threadman.setup()
	-- TODO: catch errors
	
	-- set number of worker threads, most not be too low or deadlocks will occur
	luaproc.setnumworkers(10)
	
	-- create message channel (for passing messages between threads)
	luaproc.newchannel("master")
	
	threadman.startThread(function()
		
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
		
		print("[dispatcher]", "started")
		
		local msg
		while true do
			msg = luaproc.receive("master")
			--print("[dispatcher]", "message: "..msg)
			msg = cjson_safe.decode(msg)
			if msg ~= nil then
				if msg["type"] == "removedListener" then
					listeners[msg["name"]] = nil
					print("[dispatcher]", "removed listener "..msg["name"])
				end
				--print("[dispatcher]", "started dispatching")
				for k, listener in pairs(listeners) do
					--print("[dispatcher]", "dispatching "..cjson_safe.encode(msg).." to "..listener)
					-- TODO: catch errors
					local emsg = cjson_safe.encode(msg)
					-- send message in another thread to prevent deadlocks
					luaproc.newproc(function()
						local luaproc = require("luaproc")
						luaproc.send(listener, emsg)
					end)
					--print("[dispatcher]", "done dispatching "..cjson_safe.encode(msg).." to "..listener)
				end
				--print("[dispatcher]", "done dispatching")
				if msg["type"] == "newListener" then
					listeners[msg["name"]] = msg["name"]
					print("[dispatcher]", "added listener "..msg["name"])
				end
				if msg["type"] == "exit" then
					print("[dispatcher]", "exiting")
					return
				end
			end
		end
	end)
end

function threadman.teardown()
	-- TODO: catch errors
	-- wait for workers to finish
	luaproc.wait()
	luaproc.delchannel("master")
end

function threadman.startThread(func)
	local started, err = luaproc.newproc(func)
	if started ~= true then
		print("[threadman]", "Error: failed to start thread: "..err)
		os.exit(1)
	end
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

threadman.ThreadListener = {channel = nil}

function threadman.ThreadListener:new(c)
	o = {channel = c}
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
	threadman.notify({type="removedListener",name=n})
	luaproc.delchannel(self.channel)
end

function threadman.registerListener(n)
	-- TODO: catch errors
	luaproc.newchannel(n)
	threadman.notify({type="newListener",name=n})
	return threadman.ThreadListener:new(n)
end

function threadman.unregisterListener(l)
	-- TODO: catch errors
	l:unregister()
end

return threadman
