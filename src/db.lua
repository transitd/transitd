--[[
@file db.lua
@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex
--]]

--- @module db
local db = {}

local config = require("config")
local network = require("network")

-- TODO: switch to using ORM library (https://github.com/itdxer/4DaysORM)

local sqlite3 = require("luasql.sqlite3")
local env = sqlite3.sqlite3()
local dbfile = get_path_from_path_relative_to_config(config.database.file)
local dbc = env:connect(dbfile)

if dbc == nil then
	error("Failed to open database "..dbfile)
end

function db.prepareDatabase()
	
	assert(dbc:execute("PRAGMA journal_mode=WAL"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS nodes( \
	name varchar(255), \
	ip varchar(15), \
	port INTEGER, \
	last_seen_timestamp INTEGER \
	)"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS gateways( \
	name varchar(255), \
	ip varchar(15), \
	port INTEGER, \
	last_seen_timestamp INTEGER, \
	suite varchar(64) \
	)"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS sessions( \
	sid varchar(32) PRIMARY KEY, \
	name varchar(255), \
	subscriber INTEGER, \
	suite varchar(64), \
	meshIP varchar(45), \
	port INTEGER, \
	internetIPv4 varchar(18), \
	internetIPv4gateway varchar(15), \
	internetIPv6 varchar(49), \
	internetIPv6gateway varchar(45), \
	registerTimestamp INTEGER, \
	timeoutTimestamp INTEGER, active INTEGER \
	)"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS sessions_cjdns( \
	sid varchar(32) PRIMARY KEY, \
	key varchar(255) \
	)"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS network_hosts( \
	ip varchar(45), \
	visited INTEGER, \
	scanid INTEGER, \
	network varchar(16), \
	last_seen_timestamp INTEGER \
	)"))
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS network_links( \
	ip1 varchar(45), \
	ip2 varchar(45), \
	scanid INTEGER, \
	network varchar(16), \
	last_seen_timestamp INTEGER \
	)"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS schema_migrations( \
	name varchar(255) PRIMARY KEY, \
	timestamp INTEGER \
	)"))
	
	db.migrateSchema()
	
end

function db.migrateSchema()
	-- TODO: code simple schema migration system for painless upgrades
end

-- remove outdated data from database
function db.purge()
	
	local tables = {
			{ ['table'] = 'nodes', timeout = 31*24*60*60, timeoutField = 'last_seen_timestamp'},
			{ ['table'] = 'gateways', timeout = 31*24*60*60, timeoutField = 'last_seen_timestamp'},
			{ ['table'] = 'network_hosts', timeout = 24*60*60, timeoutField = 'last_seen_timestamp'},
			{ ['table'] = 'network_links', timeout = 24*60*60, timeoutField = 'last_seen_timestamp'},
		}
	
	local timestamp = os.time()
	
	for k,t in pairs(tables) do
		local query = string.format(
			"DELETE FROM '%s' WHERE '%s' < '%d'"
			,dbc:escape(t.table)
			,dbc:escape(t.timeoutField)
			,timestamp-t.timeout
		)
		local result, err = dbc:execute(query)
		if err then print(err) end
	end
end

function db.addNetworkHost(net, ip, scanid)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local timestamp = os.time()
	
	local host, err = db.lookupNetworkHost(net, ip, scanid)
	if err then return nil, err end
	if host then
		-- update last seen timestamp
		local result, err = dbc:execute(string.format("UPDATE network_hosts SET last_seen_timestamp = '%d' WHERE ip = '%s' AND network = '%s' AND scanid = '%d'", tonumber(timestamp), dbc:escape(ip), dbc:escape(net), tonumber(scanid)))
		if err ~= nil then
			return false, err
		end
		return true, nil
	end
	
	local query = string.format(
		"INSERT INTO network_hosts ("
		.." ip"
		..",visited"
		..",last_seen_timestamp"
		..",network"
		..",scanid"
		..") VALUES ("
		.."'%s'"
		..",0"
		..",'%d'"
		..",'%s'"
		..",'%d'"
		..")"
		,dbc:escape(ip)
		,tonumber(timestamp)
		,dbc:escape(net)
		,tonumber(scanid)
	)
	local result, err = dbc:execute(query)
	if err then return nil, err end
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.lookupNetworkHost(net, ip, scanid)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local cur, err = dbc:execute(string.format("SELECT * FROM network_hosts WHERE network = '%s' AND scanid = '%d' AND ip = '%s' LIMIT 1", dbc:escape(net), tonumber(scanid), dbc:escape(ip)))
	if err then return nil, err end
	local result = cur:fetch ({}, "a")
	cur:close()
	return result, nil
end

function db.visitNetworkHost(net, ip, scanid)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local timestamp = os.time()
	local result, err = dbc:execute(string.format("UPDATE network_hosts SET visited = 1, last_seen_timestamp = '%d' WHERE ip = '%s' AND network = '%s' AND scanid = '%d'", tonumber(timestamp), dbc:escape(ip), dbc:escape(net), tonumber(scanid)))
	if err then return nil, err end
	return true, nil
end

function db.getNextNetworkHost(net, scanid)
	local cur, err = dbc:execute(string.format("SELECT * FROM network_hosts WHERE network = '%s' AND scanid = '%d' AND visited = 0 LIMIT 1", dbc:escape(net), tonumber(scanid)))
	if cur == nil then
		return nil, err
	end
	local result = cur:fetch ({}, "a")
	cur:close()
	return result, nil
end

function db.visitAllNetworkHosts(net, scanid)
	
	local result, err = dbc:execute(string.format("UPDATE network_hosts SET visited = 1 WHERE network = '%s' AND scanid = '%d'", dbc:escape(net), tonumber(scanid)))
	if err then return nil, err end
	return true, nil
end

function db.getNetworkHostsSince(net, timestamp, scanid)
	
	local cur, err = dbc:execute(string.format("SELECT * FROM network_hosts WHERE network = '%s' AND scanid = '%d' AND last_seen_timestamp >= '%d'", dbc:escape(net), tonumber(scanid), tonumber(timestamp)))
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

function db.addNetworkLink(net, ip1, ip2, scanid)
	
	local ip1, err = network.canonicalizeIp(ip1)
	if err then return nil, err end
	local ip2, err = network.canonicalizeIp(ip2)
	if err then return nil, err end
	
	local timestamp = os.time()
	
	local linked, err = db.areLinked(net, ip1, ip2, scanid)
	if err then return nil, err end
	if linked then
		-- update last seen timestamp
		local result, err = dbc:execute(string.format("UPDATE network_links SET last_seen_timestamp = '%d' WHERE ((ip1 = '%s' AND ip2 = '%s') OR (ip1 = '%s' AND ip2 = '%s')) AND network = '%s' AND scanid = '%d'", tonumber(timestamp), dbc:escape(ip1), dbc:escape(ip2), dbc:escape(ip2), dbc:escape(ip1), dbc:escape(net), tonumber(scanid)))
		if err then return nil, err end
		return true, nil
	end
	
	local query = string.format(
		"INSERT INTO network_links ("
		.." ip1"
		..",ip2"
		..",last_seen_timestamp"
		..",network"
		..",scanid"
		..") VALUES ("
		.."'%s'"
		..",'%s'"
		..",'%d'"
		..",'%s'"
		..",'%d'"
		..")"
		,dbc:escape(ip1)
		,dbc:escape(ip2)
		,tonumber(timestamp)
		,dbc:escape(net)
		,tonumber(scanid)
	)
	local result, err = dbc:execute(query)
	if err then return nil, err end
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.areLinked(net, ip1, ip2, scanid)
	
	local ip1, err = network.canonicalizeIp(ip1)
	if err then return nil, err end
	local ip2, err = network.canonicalizeIp(ip2)
	if err then return nil, err end
	
	local cur, err = dbc:execute(string.format("SELECT * FROM network_links WHERE ((ip1 = '%s' AND ip2 = '%s') OR (ip1 = '%s' AND ip2 = '%s')) AND network = '%s' AND scanid = '%d'", dbc:escape(ip1), dbc:escape(ip2), dbc:escape(ip2), dbc:escape(ip1), dbc:escape(net), tonumber(scanid)))
	if err then return nil, err end
	if cur == nil then
		return nil, err
	end
	local result = cur:fetch ({}, "a")
	cur:close()
	if result then
		return true, nil
	else
		return false, nil
	end
	
end

function db.getLinks(net, ip, scanid)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local cur, err = dbc:execute(string.format("SELECT * FROM network_links WHERE (ip1 = '%s' OR ip2 = '%s') AND network = '%s' AND scanid = '%d'", dbc:escape(ip), dbc:escape(ip), dbc:escape(net), tonumber(scanid)))
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		local ip2 = row.ip1
		if ip2 == ip then ip2 = row.ip2 end
		list[#list+1] = ip2
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

function db.getLinksSince(net, timestamp, scanid)
	
	local cur, err = dbc:execute(string.format("SELECT * FROM network_links WHERE network = '%s' AND scanid = '%d' AND last_seen_timestamp >= '%d'", dbc:escape(net), tonumber(scanid), tonumber(timestamp)))
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

function db.getLastScanId(net)
	
	local cur, err = dbc:execute(string.format("SELECT MAX(scanid) as scanid FROM network_hosts WHERE network = '%s'", dbc:escape(net)))
	if cur == nil then
		return nil, err
	end
	local result = cur:fetch ({}, "a")
	cur:close()
	if result and result.scanid then
		return tonumber(result.scanid), nil
	else
		return nil, nil
	end
	
end

function db.isScanComplete(net, scanid)
	
	local cur, err = dbc:execute(string.format("SELECT * FROM network_hosts WHERE network = '%s' AND scanid = '%d' AND visited = 0 LIMIT 1", dbc:escape(net), tonumber(scanid)))
	if cur == nil then
		return nil, err
	end
	local result = cur:fetch ({}, "a")
	cur:close()
	if result then
		return false, nil
	else
		return true, nil
	end
	
end


-- TODO: add purge function to remove records with expired last_seen_timestamp values

function db.getLastActiveSessions()
	local cur, err = dbc:execute("SELECT * FROM sessions WHERE active = 1 ORDER BY timeoutTimestamp DESC")
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

function db.registerGatewaySession(sid, name, suite, meshIP, port)
	
	local meshIP, err = network.canonicalizeIp(meshIP)
	if err then return nil, err end
	
	local timestamp = os.time()
	local query = string.format(
		"INSERT INTO sessions ("
		.." sid"
		..",name"
		..",subscriber"
		..",suite"
		..",meshIP"
		..",port"
		..",active"
		..",registerTimestamp"
		..") VALUES ("
		.."'%s'"
		..",'%s'"
		..",0"
		..",'%s'"
		..(meshIP==nil and ",NULL%s" or ",'%s'")
		..",'%d'"
		..",0"
		..",'%d'"
		..")"
		,dbc:escape(sid)
		,dbc:escape(name)
		,dbc:escape(suite)
		,meshIP~=nil and dbc:escape(meshIP) or ""
		,tonumber(port)
		,timestamp
	)
	local result, err = dbc:execute(query)
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.updateGatewaySession(sid, active, internetIPv4, internetIPv4gateway, internetIPv6, internetIPv6gateway, timeoutTimestamp)
	
	if internetIPv4 then
		local err
		internetIPv4, err = network.canonicalizeIp(internetIPv4)
		if err then return nil, err end
	end
	if internetIPv4gateway then
		local err
		internetIPv4gateway, err = network.canonicalizeIp(internetIPv4gateway)
		if err then return nil, err end
	end
	if internetIPv6 then
		local err
		internetIPv6, err = network.canonicalizeIp(internetIPv6)
		if err then return nil, err end
	end
	if internetIPv6gateway then
		local err
		internetIPv6gateway, err = network.canonicalizeIp(internetIPv6gateway)
		if err then return nil, err end
	end
	
	local timestamp = os.time()
	local act = 0
	if active==true then act = 1 end
	local query = string.format(
		"UPDATE sessions SET "
		.." active = '%d'"
		..((internetIPv4==nil and "%s") or ",internetIPv4 = '%s'")
		..((internetIPv4gateway==nil and "%s") or ",internetIPv4gateway = '%s'")
		..((internetIPv6==nil and "%s") or ",internetIPv6 = '%s'")
		..((internetIPv6gateway==nil and "%s") or ",internetIPv6gateway = '%s'")
		..",registerTimestamp = '%d'"
		..",timeoutTimestamp = '%d'"
		.." WHERE sid = '%s'"
		,act
		,(internetIPv4==nil and "") or dbc:escape(internetIPv4)
		,(internetIPv4gateway==nil and "") or dbc:escape(internetIPv4gateway)
		,(internetIPv6==nil and "") or dbc:escape(internetIPv6)
		,(internetIPv6gateway==nil and "") or dbc:escape(internetIPv6gateway)
		,timestamp
		,tonumber(timeoutTimestamp)
		,dbc:escape(sid)
	)
	local result, err = dbc:execute(query)
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.registerSubscriberSession(sid, name, suite, meshIP, port, internetIPv4, internetIPv4gateway, internetIPv6, internetIPv6gateway, timeoutTimestamp)
	
	local meshIP, err = network.canonicalizeIp(meshIP)
	if err then return nil, err end
	if internetIPv4 then
		local err
		internetIPv4, err = network.canonicalizeIp(internetIPv4)
		if err then return nil, err end
	end
	if internetIPv4gateway then
		local err
		internetIPv4gateway, err = network.canonicalizeIp(internetIPv4gateway)
		if err then return nil, err end
	end
	if internetIPv6 then
		local err
		internetIPv6, err = network.canonicalizeIp(internetIPv6)
		if err then return nil, err end
	end
	if internetIPv6gateway then
		local err
		internetIPv6gateway, err = network.canonicalizeIp(internetIPv6gateway)
		if err then return nil, err end
	end
	
	local timestamp = os.time()
	local query = string.format(
		"INSERT INTO sessions ("
		.." sid"
		..",name"
		..",subscriber"
		..",suite"
		..",meshIP"
		..",port"
		..",internetIPv4"
		..",internetIPv4gateway"
		..",internetIPv6"
		..",internetIPv6gateway"
		..",registerTimestamp"
		..",timeoutTimestamp"
		..",active"
		..") VALUES ("
		.."'%s'"
		..",'%s'"
		..",1"
		..",'%s'"
		..(meshIP==nil and ",NULL%s" or ",'%s'")
		..",'%d'"
		..(internetIPv4==nil and ",NULL%s" or ",'%s'")
		..(internetIPv4gateway==nil and ",NULL%s" or ",'%s'")
		..(internetIPv6==nil and ",NULL%s" or ",'%s'")
		..(internetIPv6gateway==nil and ",NULL%s" or ",'%s'")
		..",'%d'"
		..",'%d'"
		..",1"
		..")"
		,dbc:escape(sid)
		,dbc:escape(name)
		,dbc:escape(suite)
		,meshIP~=nil and dbc:escape(meshIP) or ""
		,tonumber(port)
		,internetIPv4~=nil and dbc:escape(internetIPv4) or ""
		,internetIPv4gateway~=nil and dbc:escape(internetIPv4gateway) or ""
		,internetIPv6~=nil and dbc:escape(internetIPv6) or ""
		,internetIPv6gateway~=nil and dbc:escape(internetIPv6gateway) or ""
		,timestamp
		,tonumber(timeoutTimestamp)
	)
	local result, err = dbc:execute(query)
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.registerSubscriberSessionCjdnsKey(sid, key)
	local query = string.format(
		"INSERT INTO sessions_cjdns ("
		.." sid"
		..",key"
		..") VALUES ("
		.."'%s'"
		..",'%s'"
		..")"
		,dbc:escape(sid)
		,dbc:escape(key)
	)
	local result, err = dbc:execute(query)
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.getCjdnsSubscriberKey(sid)
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions_cjdns WHERE sid = '%s'", dbc:escape(sid)))
	if cur == nil then
		return nil, err
	end
	local result = cur:fetch ({}, "a")
	cur:close()
	if result and result.key then
		return result.key, nil
	else
		return nil, "Sid cjdns key mapping not found"
	end
end

function db.lookupSession(sid)
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions WHERE sid = '%s'", dbc:escape(sid)))
	if cur == nil then
		return nil, err
	end
	local result, err = cur:fetch ({}, "a")
	if err then
		return nil, err
	end
	cur:close()
	return result, nil
end

function db.activateSession(sid)
	local result, err = dbc:execute(string.format("UPDATE sessions SET active = 1 WHERE sid = '%s'", dbc:escape(sid)))
	if err ~= nil then
		return false, err
	end
	return true, nil
end

function db.updateSessionTimeout(sid, timeoutTimestamp)
	local timestamp = os.time()
	local result, err = dbc:execute(string.format("UPDATE sessions SET timeoutTimestamp = '%d' WHERE sid = '%s' AND active = 1", tonumber(timeoutTimestamp), dbc:escape(sid)))
	if err ~= nil then
		return false, err
	end
	return true, nil
end

function db.deactivateSession(sid)
	local result, err = dbc:execute(string.format("UPDATE sessions SET active = 0 WHERE sid = '%s'", dbc:escape(sid)))
	if err ~= nil then
		return false, err
	end
	return true, nil
end

function db.lookupActiveSubscriberSessionByIp(ip, port)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
 	local timestamp = os.time()
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions WHERE subscriber = 1 AND meshIP = '%s' AND port = '%d' AND '%d' <= timeoutTimestamp AND active = 1", dbc:escape(ip), tonumber(port), timestamp))
	if err then
		return nil, err
	end
	local result, err = cur:fetch ({}, "a")
	if err then
		return nil, err
	end
	cur:close()
	return result, nil
end

function db.lookupActiveSubscriberSessionByInternetIp(ip)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
 	local timestamp = os.time()
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions WHERE subscriber = 1 AND (internetIPv4 = '%s' OR internetIPv6 = '%s') AND '%d' <= timeoutTimestamp AND active = 1", dbc:escape(ip), dbc:escape(ip), timestamp))
	if err then
		return nil, err
	end
	local result, err = cur:fetch ({}, "a")
	if err then
		return nil, err
	end
	cur:close()
	return result, nil
end

function db.getTimingOutSubscribers(sinceTimestamp)
 	local timestamp = os.time()
	local sinceTimestamp = tonumber(sinceTimestamp)
	if sinceTimestamp >= timestamp then
		return nil, "Timestamp must be in the past"
	end
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions WHERE subscriber = 1 AND '%d' <= timeoutTimestamp AND timeoutTimestamp < '%d' AND active = 1", sinceTimestamp, timestamp))
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

function db.getActiveSessions()
 	local timestamp = os.time()
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions WHERE '%d' <= timeoutTimestamp AND active = 1", timestamp))
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

function db.registerNode(name, ip, port)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local timestamp = os.time()
	
	local query
	
	-- TODO: fix race condition
	local node = db.lookupNode(ip, port)
	if node ~= nil then
		query = string.format(
			"UPDATE nodes SET last_seen_timestamp = '%d' WHERE ip = '%s' AND port = '%d'"
			,timestamp
			,dbc:escape(ip)
			,tonumber(port)
		)
	else
		query = string.format(
			"INSERT INTO nodes ("
			.."name"
			..",ip"
			..",port"
			..",last_seen_timestamp"
			..") VALUES ("
			.."'%s'"
			..",'%s'"
			..",'%d'"
			..",'%d'"
			..")"
			,dbc:escape(name)
			,dbc:escape(ip)
			,tonumber(port)
			,tonumber(timestamp)
		)
	end
	local result, err = dbc:execute(query)
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.lookupNode(ip, port)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local cur, err = dbc:execute(string.format("SELECT * FROM nodes WHERE ip = '%s' AND port = '%d'",dbc:escape(ip),tonumber(port)))
	if cur == nil then
		return nil, err
	end
	local result, err = cur:fetch ({}, "a")
	if err then
		return nil, err
	end
	cur:close()
	return result, nil
end

function db.lookupNodeByIp(ip)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local cur, err = dbc:execute(string.format("SELECT * FROM nodes WHERE ip = '%s'",dbc:escape(ip)))
	if cur == nil then
		return nil, err
	end
	local result, err = cur:fetch ({}, "a")
	if err then
		return nil, err
	end
	cur:close()
	return result, nil
end

function db.getRecentNodes()
 	local timestamp = os.time() - 30*24*60*60
	local cur, err = dbc:execute(string.format("SELECT * FROM nodes WHERE last_seen_timestamp > '%d'", timestamp))
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

function db.registerGateway(name, ip, port, suite)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local timestamp = os.time()
	
	local query
	
	-- TODO: fix race condition
	local gateway = db.lookupGateway(ip, port, suite)
	if gateway ~= nil then
		query = string.format(
			"UPDATE gateways SET last_seen_timestamp = '%d' WHERE ip = '%s' AND port = '%d' AND suite = '%s'"
			,timestamp
			,dbc:escape(ip)
			,tonumber(port)
			,dbc:escape(suite)
		)
	else
		query = string.format(
			"INSERT INTO gateways ("
			.."name"
			..",ip"
			..",port"
			..",last_seen_timestamp"
			..",suite"
			..") VALUES ("
			.."'%s'"
			..",'%s'"
			..",'%d'"
			..",'%d'"
			..",'%s'"
			..")"
			,dbc:escape(name)
			,dbc:escape(ip)
			,tonumber(port)
			,tonumber(timestamp)
			,dbc:escape(suite)
		)
	end
	
	local result, err = dbc:execute(query)
	if result == nil then
		return nil, err
	end
	return true, nil
end

function db.lookupGateway(ip, port, suite)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local cur, err = dbc:execute(string.format("SELECT * FROM gateways WHERE ip = '%s' AND port = '%d' AND suite = '%s'",dbc:escape(ip),tonumber(port),dbc:escape(suite)))
	if cur == nil then
		return nil, err
	end
	local result, err = cur:fetch ({}, "a")
	if err then
		return nil, err
	end
	cur:close()
	return result, nil
end

function db.lookupGatewayByIp(ip)
	
	local ip, err = network.canonicalizeIp(ip)
	if err then return nil, err end
	
	local cur, err = dbc:execute(string.format("SELECT * FROM gateways WHERE ip = '%s'",dbc:escape(ip)))
	if cur == nil then
		return nil, err
	end
	local result, err = cur:fetch ({}, "a")
	if err then
		return nil, err
	end
	cur:close()
	return result, nil
end

function db.getRecentGateways()
 	local timestamp = os.time() - 30*24*60*60
	local cur, err = dbc:execute(string.format("SELECT * FROM gateways WHERE last_seen_timestamp > '%d'", timestamp))
	if cur == nil then
		return nil, err
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	cur:close()
	return list, nil
end

return db
