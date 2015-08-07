
local interface = {
  echo = function (msg) return msg end,
  gatewayInfo = function()
		
  	local config = require("config")
    
    return { name = config.server.name }
  end
}

return interface
