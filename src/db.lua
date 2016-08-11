--- @module db
local db = {}

local config = require("config")

-- TODO: switch to using ORM library

local sqlite3 = require("luasql.sqlite3")
local env = sqlite3.sqlite3()
local dbfile = get_path_from_path_relative_to_config(config.database.file)
local dbc = env:connect(dbfile)

if dbc == nil then
	error("Failed to open database "..dbfile)
end

function prepareDatabase()
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS nodes(name varchar(255), ip varchar(15), port INTEGER, last_seen_timestamp INTEGER)"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS gateways(name varchar(255), ip varchar(15), port INTEGER, last_seen_timestamp INTEGER, method varchar(64))"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS sessions(sid varchar(32) PRIMARY KEY, name varchar(255), subscriber INTEGER, method varchar(64), meshIP varchar(45), port INTEGER, internetIPv4 varchar(15), internetIPv6 varchar(45), register_timestamp INTEGER, timeout_timestamp INTEGER, active INTEGER)"))
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS sessions_cjdns(sid varchar(32) PRIMARY KEY, key varchar(255))"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS schema_migrations(name varchar(255) PRIMARY KEY, timestamp INTEGER)"))
	migrateSchema()
end

function migrateSchema()
	-- TODO: code simple schema migration system for painless upgrades
end

-- TODO: add purge function to remove records with expired last_seen_timestamp values

function db.getLastActiveSessions()
	local cur, error = dbc:execute("SELECT * FROM sessions WHERE active = 1 ORDER BY timeout_timestamp DESC")
	if cur == nil then
		return nil, error
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	return list, nil
end

function db.registerGatewaySession(sid, name, method, meshIP, port)
	local timestamp = os.time()
	local query = string.format(
		"INSERT INTO sessions ("
		.." sid"
		..",name"
		..",subscriber"
		..",method"
		..",meshIP"
		..",port"
		..",active"
		..",register_timestamp"
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
		,dbc:escape(method)
		,meshIP~=nil and dbc:escape(meshIP) or ""
		,tonumber(port)
		,timestamp
	)
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.updateGatewaySession(sid, active, internetIPv4, internetIPv6, timeout)
	local timestamp = os.time()
	local act = 0
	if active==true then act = 1 end
	local query = string.format(
		"UPDATE sessions SET "
		.." active = '%d'"
		..((internetIPv4==nil and "%s") or ",internetIPv4 = '%s'")
		..((internetIPv6==nil and "%s") or ",internetIPv6 = '%s'")
		..",register_timestamp = '%d'"
		..",timeout_timestamp = '%d'"
		.." WHERE sid = '%s'"
		,act
		,(internetIPv4==nil and "") or dbc:escape(internetIPv4)
		,(internetIPv6==nil and "") or dbc:escape(internetIPv6)
		,timestamp
		,timestamp+tonumber(timeout)
		,dbc:escape(sid)
	)
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.registerSubscriberSession(sid, name, method, meshIP, port, internetIPv4, internetIPv6, timeout)
	local timestamp = os.time()
	local query = string.format(
		"INSERT INTO sessions ("
		.." sid"
		..",name"
		..",subscriber"
		..",method"
		..",meshIP"
		..",port"
		..",internetIPv4"
		..",internetIPv6"
		..",register_timestamp"
		..",timeout_timestamp"
		..",active"
		..") VALUES ("
		.."'%s'"
		..",'%s'"
		..",1"
		..",'%s'"
		..(meshIP==nil and ",NULL%s" or ",'%s'")
		..",'%d'"
		..(internetIPv4==nil and ",NULL%s" or ",'%s'")
		..(internetIPv6==nil and ",NULL%s" or ",'%s'")
		..",'%d'"
		..",'%d'"
		..",1"
		..")"
		,dbc:escape(sid)
		,dbc:escape(name)
		,dbc:escape(method)
		,meshIP~=nil and dbc:escape(meshIP) or ""
		,tonumber(port)
		,internetIPv4~=nil and dbc:escape(internetIPv4) or ""
		,internetIPv6~=nil and dbc:escape(internetIPv6) or ""
		,timestamp
		,timestamp+timeout
	)
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
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
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.getCjdnsSubscriberKey(sid)
	local cur, error = dbc:execute(string.format("SELECT * FROM sessions_cjdns WHERE sid = '%s'", dbc:escape(sid)))
	if cur == nil then
		return nil, error
	end
	local result = cur:fetch ({}, "a")
	if result and result.key then
		return result.key, nil
	else
		return nil, "Sid not found"
	end
end

function db.lookupSession(sid)
	local cur, error = dbc:execute(string.format("SELECT * FROM sessions WHERE sid = '%s'", dbc:escape(sid)))
	if cur == nil then
		return nil, error
	end
	return cur:fetch ({}, "a"), nil
end

function db.activateSession(sid)
	local result, error = dbc:execute(string.format("UPDATE sessions SET active = 1 WHERE sid = '%s'", dbc:escape(sid)))
	if error ~= nil then
		return false, error
	end
	return true, nil
end

function db.updateSessionTimeout(sid, timeout)
	local timestamp = os.time()
	local result, error = dbc:execute(string.format("UPDATE sessions SET timeout_timestamp = '%d' WHERE sid = '%s' AND active = 1", timestamp+tonumber(timeout), dbc:escape(sid)))
	if error ~= nil then
		return false, error
	end
	return true, nil
end

function db.deactivateSession(sid)
	local result, error = dbc:execute(string.format("UPDATE sessions SET active = 0 WHERE sid = '%s'", dbc:escape(sid)))
	if error ~= nil then
		return false, error
	end
	return true, nil
end

function db.lookupActiveSubscriberSessionByIp(ip, port)
 	local timestamp = os.time()
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions WHERE subscriber = 1 AND meshIP = '%s' AND port = '%d' AND '%d' <= timeout_timestamp AND active = 1", dbc:escape(ip), tonumber(port), timestamp))
	if err then
		return nil, err
	end
	return cur:fetch ({}, "a"), nil
end

function db.lookupActiveSubscriberSessionByInternetIp(ip)
 	local timestamp = os.time()
	local cur, err = dbc:execute(string.format("SELECT * FROM sessions WHERE subscriber = 1 AND (internetIPv4 = '%s' OR internetIPv6 = '%s') AND '%d' <= timeout_timestamp AND active = 1", dbc:escape(ip), dbc:escape(ip), timestamp))
	if err then
		return nil, err
	end
	return cur:fetch ({}, "a"), nil
end

function db.getTimingOutSubscribers(sinceTimestamp)
 	local timestamp = os.time()
	local sinceTimestamp = tonumber(sinceTimestamp)
	if sinceTimestamp >= timestamp then
		return nil, "Timestamp must be in the past"
	end
	local cur, error = dbc:execute(string.format("SELECT * FROM sessions WHERE subscriber = 1 AND '%d' <= timeout_timestamp AND timeout_timestamp < '%d' AND active = 1", sinceTimestamp, timestamp))
	if cur == nil then
		return nil, error
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	return list, nil
end

function db.getActiveSessions()
 	local timestamp = os.time()
	local cur, error = dbc:execute(string.format("SELECT * FROM sessions WHERE '%d' <= timeout_timestamp AND active = 1", timestamp))
	if cur == nil then
		return nil, error
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	return list, nil
end

function db.registerNode(name, ip, port)
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
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.lookupNode(ip, port)
	local cur, error = dbc:execute(string.format("SELECT * FROM nodes WHERE ip = '%s' AND port = '%d'",dbc:escape(ip),tonumber(port)))
	if cur == nil then
		return nil, error
	end
	return cur:fetch ({}, "a")
end

function db.getRecentNodes()
 	local timestamp = os.time() - 30*24*60*60
	local cur, error = dbc:execute(string.format("SELECT * FROM nodes WHERE last_seen_timestamp > '%d'", timestamp))
	if cur == nil then
		return nil, error
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	return list, nil
end

function db.registerGateway(name, ip, port, method)
	local timestamp = os.time()
	
	local query
	
	-- TODO: fix race condition
	local gateway = db.lookupGateway(ip, port, method)
	if gateway ~= nil then
		query = string.format(
			"UPDATE gateways SET last_seen_timestamp = '%d' WHERE ip = '%s' AND port = '%d' AND method = '%s'"
			,timestamp
			,dbc:escape(ip)
			,tonumber(port)
			,dbc:escape(method)
		)
	else
		query = string.format(
			"INSERT INTO gateways ("
			.."name"
			..",ip"
			..",port"
			..",last_seen_timestamp"
			..",method"
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
			,dbc:escape(method)
		)
	end
	
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.lookupGateway(ip, port, method)
	local cur, error = dbc:execute(string.format("SELECT * FROM gateways WHERE ip = '%s' AND port = '%d' AND method = '%s'",dbc:escape(ip),tonumber(port),dbc:escape(method)))
	if cur == nil then
		return nil, error
	end
	return cur:fetch ({}, "a")
end

function db.getRecentGateways()
 	local timestamp = os.time() - 30*24*60*60
	local cur, error = dbc:execute(string.format("SELECT * FROM gateways WHERE last_seen_timestamp > '%d'", timestamp))
	if cur == nil then
		return nil, error
	end
	local list = {}
	local row = cur:fetch ({}, "a")
	while row do
		list[#list+1] = row
		row = cur:fetch ({}, "a")
	end
	return list, nil
end

prepareDatabase()

return db
