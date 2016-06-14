
local xavante = require "xavante"
local filehandler = require "xavante.filehandler"
local cgiluahandler = require "xavante.cgiluahandler"
local redirecthandler = require "xavante.redirecthandler"

local config = require("config")

local conman = require("conman")

-- Define here where Xavante HTTP documents scripts are located
local webDir = "./www"

local rules = {
	
	-- redirect
    {
      match = "^[^%./]*/$",
      with = redirecthandler,
      params = {"index.lua"}
    }, 
    {
      match = "^[^%./]*/jsonrpc/?$",
      with = redirecthandler,
      params = {"jsonrpc.lua"}
    }, 
	
	-- cgi
    {
      match = {"%.lp$", "%.lp/.*$", "%.lua$", "%.lua/.*$" },
      with = cgiluahandler.makeHandler (webDir)
    },
	
	-- static content
    {
      match = ".",
      with = filehandler,
      params = {baseDir = webDir}
    },
} 

xavante.HTTP{
    server = {host = "::", port = config.main.rpcport},
    
    defaultHost = {
    	rules = rules
    },
}

xavante.HTTP{
    server = {host = "0.0.0.0", port = config.main.rpcport},
    
    defaultHost = {
    	rules = rules
    },
}

print "\nStarting mnigs daemon...\n"

local thread = require "llthreads2".new[[
	local conman = require("conman")
	conman.startConnectionManager()
]]

thread:start(true, true)

xavante.start()

print "exiting...\n"

thread:join()
