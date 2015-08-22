
local xavante = require "xavante"
local filehandler = require "xavante.filehandler"
local cgiluahandler = require "xavante.cgiluahandler"
local redirecthandler = require "xavante.redirecthandler"

local config = require("config")

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
    server = {host = "::", port = config.server.rpcport},
    
    defaultHost = {
    	rules = rules
    },
}

xavante.HTTP{
    server = {host = "0.0.0.0", port = config.server.rpcport},
    
    defaultHost = {
    	rules = rules
    },
}

print "\nStarting mnigs server...\n";

xavante.start();

print "exiting...\n"

