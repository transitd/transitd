--[[
@file support.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module support
local support = {}

local lfs = require("lfs")

local threadman = require("threadman")

local buildList = function(path)
	local list = {}
	for file in lfs.dir(path) do
		local mod = file:match("^(.+)\.lua$")
		if mod then
			local module = require(path..mod)
			local name = module.getName()
			list[mod] = {['name'] = name, ['module'] = mod}
		end
	end
	return list
end

function support.getNetworks()
	local networks = {}
	for name,suite in pairs(support.getSuites()) do
		networks[suite.network.module] = suite.network
	end
	return networks
end

function support.getTunnels()
	local networks = {}
	for name,suite in pairs(support.getSuites()) do
		networks[suite.tunnel.module] = suite.tunnel
	end
	return networks
end

function support.getPayments()
	local networks = {}
	for name,suite in pairs(support.getSuites()) do
		networks[suite.payment.module] = suite.payment
	end
	return networks
end

function support.getSuites()
	
	local list = threadman.getShared('suites')
	if list ~= nil then return list end
	
	local list = {}
	
	for netmod,net in pairs(buildList("./networks/")) do
		for tunmod,tun in pairs(buildList("./tunnels/")) do
			for paymod,pay in pairs(buildList("./payments/")) do
				
				local network = require("networks."..net.module)
				local tunnel = require("tunnels."..tun.module)
				local payment = require("payments."..pay.module)
				
				if network.checkSupport(net, tun, pay)
				and tunnel.checkSupport(net, tun, pay)
				and payment.checkSupport(net, tun, pay)
				then
					local id = netmod.."-"..tunmod.."-"..paymod
					list[id] = {
						["id"] = id,
						["name"] = id,
						["network"] = {["module"] = netmod},
						["tunnel"] = {["module"] = tunmod},
						["payment"] = {["module"] = paymod},
					}
				end
			end
		end
	end
	
	threadman.setShared('suites', list)
	
	return list
end

function support.getGeo()

	local list = threadman.getShared('geoModules')
	if list ~= nil then return list end

	for geomod, geo in pairs(buildList("./geo/")) do
		local geolocation = require("geo."..geo.module)
		if geolocation.checkSupport then
			list[net.name] = geo
		end
	end

	threadman.setShared('geoModules', list)

	return list

end

function support.matchSuite(suite)
	
	local matchedSuite = nil
	
	for myid, mySuite in pairs(support.getSuites()) do
		if mySuite.network.module == suite.network.module
		and mySuite.tunnel.module == suite.tunnel.module
		and mySuite.payment.module == suite.payment.module
		then
			matchedSuite = mySuite
			break
		end
	end
	
	return matchedSuite, nil
end

return support
