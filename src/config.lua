
local socket = require("socket")

-- need better random numbers
math.randomseed(socket.gettime()*1000)

function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

function get_path_from_path_relative_to_config(path)
	if path:sub(1,1) == "/" then
		return path
	else
		return script_path().."../"..path
	end
end

local lfs = require('lfs')

-- force cwd to src location
lfs.chdir(script_path())

if _G.config == nil then
	local inifile = require("inifile")
	
	local configfile = script_path() .. "../mnigs.conf"
	
	local options = require("options")
	local optarg = options.getArguments()
	
	if optarg.f then
		configfile = optarg.f
	end
	
	if not io.open(configfile,"r") then
		print("Configuration file '"..configfile.."' not found")
		os.exit(1)
	end
	
	_G.config = inifile.parse(configfile)
end

function save_config()
	local inifile = require("inifile")
	local configfile = script_path() .. "../mnigs.conf"
	inifile.save(configfile, _G.config)
end

return _G.config
