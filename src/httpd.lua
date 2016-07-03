--- @module httpd
local httpd = {}

local xavante = require("xavante")
local filehandler = require("xavante.filehandler")
local cgiluahandler = require("xavante.cgiluahandler")
local redirecthandler = require("xavante.redirecthandler")

local config = require("config")
local threadman = require("threadman")

-- Define here where Xavante HTTP documents scripts are located
local webDir = "./www"

local rules = {}

-- index (redirect)
table.insert(rules, {
	match  = "^[^%./]*/$",
	with   = redirecthandler,
	params = { "index.html" }
})

-- rpc (redirect)
table.insert(rules, {
	match  = "^[^%./]*/jsonrpc/?$",
	with   = redirecthandler,
	params = { "jsonrpc.lua" }
})

-- cgi
table.insert(rules, {
	match = {
		"%.lp$", "%.lp/.*$", "%.lua$", "%.lua/.*$"
	},
	with  = cgiluahandler.makeHandler(webDir)
})

-- static content
table.insert(rules, {
	match  = ".",
	with   = filehandler,
	params = { baseDir = webDir }
})

local listenOn = {}

local function xavante_params(addr, port)
	return { host = addr, port = port }
end

if (config.daemon.listenIpv6) then
	table.insert(listenOn, xavante_params('::', config.daemon.rpcport))
end

if (config.daemon.listenIpv4) then
	table.insert(listenOn, xavante_params('0.0.0.0', config.daemon.rpcport))
end


function httpd.run()
	
	for ifs, server in pairs(listenOn) do
	
	print('[xavante]', 'listening on '..server.host..' port '..server.port)
	
	xavante.HTTP {
		defaultHost = { rules = rules },
		server = server
	  }
	
	end
	
	local listener = threadman.registerListener("xavante")
	
	xavante.start(function()
		local msg = "";
		while msg ~= nil do
			msg = listener:listen(true)
			if msg ~= nil then
				if msg["type"] == "exit" then
					return true
				end
			end
		end
		return false
	end, 1);
	
	threadman.unregisterListener(listener)
	
end

return httpd
