
function script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

local inifile = require("inifile")
local conf = inifile.parse(script_path() .. "../mnigs.conf")

return conf
