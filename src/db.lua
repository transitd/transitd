--- @module db
local db = {}

local config = require("config")

local sqlite3 = require("luasql.sqlite3")
local env = sqlite3.sqlite3()
local dbfile = get_path_from_path_relative_to_config(config.database.file)
local dbc = env:connect(dbfile)

if dbc == nil then
	error("Failed to open database "..dbfile)
end

function prepareDatabase()
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS clients(sid varchar(32) PRIMARY KEY, name varchar(255), method varchar(64), meshIPv4 varchar(15), meshIPv6 varchar(45), internetIPv4 varchar(15), internetIPv6 varchar(45), register_timestamp INTEGER, timeout_timestamp INTEGER, active INTEGER)"))
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS servers(name varchar(255), ip varchar(15), last_seen_timestamp INTEGER)"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS clients_cjdns(sid varchar(32) PRIMARY KEY, key varchar(255))"))
	
	assert(dbc:execute("CREATE TABLE IF NOT EXISTS schema_migrations(name varchar(255) PRIMARY KEY, timestamp INTEGER)"))
	migrateSchema()
end

function migrateSchema()
	-- TODO: code simple schema migration system for painless upgrades
end

function db.registerClient(sid, name, method, meshIPv4, meshIPv6, internetIPv4, internetIPv6)
	local timestamp = os.time()
	local query = string.format(
		"INSERT INTO clients ("
		.." sid"
		..",name"
		..",method"
		..",meshIPv4"
		..",meshIPv6"
		..",internetIPv4"
		..",internetIPv6"
		..",register_timestamp"
		..",timeout_timestamp"
		..",active"
		..") VALUES ("
		.."'%s'"
		..",'%s'"
		..",'%s'"
		..(meshIPv4==nil and ",NULL%s" or ",'%s'")
		..(meshIPv6==nil and ",NULL%s" or ",'%s'")
		..(internetIPv4==nil and ",NULL%s" or ",'%s'")
		..(internetIPv6==nil and ",NULL%s" or ",'%s'")
		..",'%d'"
		..",'%d'"
		..",1"
		..")"
		,dbc:escape(sid)
		,dbc:escape(name)
		,dbc:escape(method)
		,meshIPv4~=nil and dbc:escape(meshIPv4) or ""
		,meshIPv6~=nil and dbc:escape(meshIPv6) or ""
		,internetIPv4~=nil and dbc:escape(internetIPv4) or ""
		,internetIPv6~=nil and dbc:escape(internetIPv6) or ""
		,timestamp
		,timestamp+config.gateway.subscriberTimeout
	)
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.registerCjdnsClient(sid, key)
	local query = string.format(
		"INSERT INTO clients_cjdns ("
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

function db.getCjdnsClientKey(sid)
	local cur, error = dbc:execute(string.format("SELECT * FROM clients_cjdns WHERE sid = '%s'", dbc:escape(sid)))
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

function db.lookupClientBySession(sid)
	local cur, error = dbc:execute(string.format("SELECT * FROM clients WHERE sid = '%s'", dbc:escape(sid)))
	if cur == nil then
		return nil, error
	end
	return cur:fetch ({}, "a"), nil
end

function db.deactivateClientBySession(sid)
	local cur, error = dbc:execute(string.format("UPDATE clients SET active = 0 WHERE sid = '%s'", dbc:escape(sid)))
	if error ~= nil then
		return false, error
	end
	return true, nil
end

function db.lookupActiveClientByIp(ip)
 	local timestamp = os.time()
	local cur, error = dbc:execute(string.format("SELECT * FROM clients WHERE (meshIPv4 = '%s' OR meshIPv6 = '%s') AND '%d' <= timeout_timestamp AND active = 1", dbc:escape(ip), dbc:escape(ip), timestamp))
	if cur == nil then
		return nil, error
	end
	return cur:fetch ({}, "a"), nil
end

function db.getTimingOutClients(sinceTimestamp)
 	local timestamp = os.time()
	if sinceTimestamp >= timestamp then
		error("Timestamp must be in the past")
	end
	local cur, error = dbc:execute(string.format("SELECT * FROM clients WHERE '%d' <= timeout_timestamp AND timeout_timestamp < '%d' AND active = 1", sinceTimestamp, timestamp))
	if cur == nil then
		return nil, error
	end
	local clients = {}
	local row = cur:fetch ({}, "a")
	while row do
		clients[#clients+1] = row
		row = cur:fetch ({}, "a")
	end
	return clients, nil
end

function db.getActiveClients()
 	local timestamp = os.time()
	local cur, error = dbc:execute(string.format("SELECT * FROM clients WHERE '%d' <= timeout_timestamp AND active = 1", timestamp))
	if cur == nil then
		return nil, error
	end
	local clients = {}
	local row = cur:fetch ({}, "a")
	while row do
		clients[#clients+1] = row.sid
		row = cur:fetch ({}, "a")
	end
	return clients, nil
end

function db.registerServer(name, ip)
	local timestamp = os.time()
	
	-- TODO: fix race condition
	
	local server = db.lookupServer(ip)
	local query
	if server ~= nil then
		query = string.format(
			"UPDATE servers SET last_seen_timestamp = '%d' WHERE ip = '%s'"
			,timestamp
			,dbc:escape(ip)
		)
	else
		query = string.format(
			"INSERT INTO servers ("
			.."name"
			..",ip"
			..",last_seen_timestamp"
			..") VALUES ("
			.."'%s'"
			..",'%s'"
			..",'%d'"
			..")"
			,dbc:escape(name)
			,dbc:escape(ip)
			,timestamp
		)
	end
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.lookupServer(ip)
	local cur, error = dbc:execute(string.format("SELECT * FROM servers WHERE ip = '%s'",dbc:escape(ip)))
	if cur == nil then
		return nil, error
	end
	return cur:fetch ({}, "a")
end

function db.getRecentServers()
 	local timestamp = os.time() - 30*24*60*60
	local cur, error = dbc:execute(string.format("SELECT * FROM servers WHERE last_seen_timestamp > '%d'", timestamp))
	if cur == nil then
		return nil, error
	end
	local servers = {}
	local row = cur:fetch ({}, "a")
	while row do
		servers[#servers+1] = row
		row = cur:fetch ({}, "a")
	end
	return servers, nil
end

prepareDatabase()

return db
