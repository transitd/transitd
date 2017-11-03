local xavante = require "xavante"
local redirecthandler = require "xavante.redirecthandler"

local rules = {

    {
      match = "^.*$",
      with = redirecthandler,
      params = {"http://192.168.1.1:65533"}
    },

}

xavante.HTTP{
    server = {host = "192.168.1.1", port = 65530},

    defaultHost = {
        rules = rules
    },
}

xavante.start();
