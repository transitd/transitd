
function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

local lfs = require('lfs')
lfs.chdir(script_path())

function get_path_from_path_relative_to_config(path)
	if path:sub(1,1) == "/" then
		return path
	else
		return script_path().."../"..path
	end
end

local inifile = require("inifile")
local conf = inifile.parse(script_path() .. "../mnigs.conf")

return conf
