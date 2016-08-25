--[[
@file config.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

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
	
	local configfile = script_path() .. "../transitd.conf"
	
	local options = require("options")
	local optarg = options.getArguments()
	
	if optarg.f then
		configfile = optarg.f
	else
		-- create config file if it doesn't exist
		local fh = io.open(configfile,"r")
		if fh ~= nil then fh:close() else
			local infile = io.open(script_path().."../transitd.conf.sample", "r")
			local outfile = io.open(configfile, "w")
			outfile:write(infile:read("*a"))
			infile:close()
			outfile:close()
		end
	end
	
	local fh = io.open(configfile,"r")
	if not fh then
		error("Configuration file '"..configfile.."' not found")
	else
		fh:close()
	end
	
	_G.config = inifile.parse(configfile)
	_G.configfile = configfile
end

function set_config(name, value)
	local con = _G.config
	local tokens = {}
	for token in string.gmatch(name, "%w+") do table.insert(tokens, token) end
	for num,section in pairs(tokens) do
		if not con[section] then
			return nil, "Invalid configuration token '"..section.."'"
		else
			if type(con[section]) ~= "table" then
				if num ~= #tokens then
					return nil, "Configuration token '"..section.."' does not have subelements"
				end
				con[section] = value
				return true, nil
			else
				if num == #tokens then
					return nil, "Configuration token '"..section.."' cannot have a value"
				else
					con = con[section]
				end
			end
		end
	end
	return true, nil
end

function save_config()
	local inifile = require("inifile")
	inifile.save(_G.configfile, _G.config)
end

return _G.config
