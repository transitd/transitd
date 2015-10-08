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
		,timestamp+config.server.clientTimeout
	)
	local result, error = dbc:execute(query)
	if result == nil then
		return nil, error
	end
	return true, nil
end

function db.lookupClientBySession(sid)
	cur = dbc:execute(string.format("SELECT * FROM clients WHERE sid = '%s'", dbc:escape(sid)))
	local clients = {}
	return cur:fetch ({}, "a")
end

function db.lookupActiveClientByIp(ip)
 	local timestamp = os.time()
	cur = dbc:execute(string.format("SELECT * FROM clients WHERE (meshIPv4 = '%s' OR meshIPv6 = '%s') AND '%d' <= timeout_timestamp AND active = 1", dbc:escape(ip), dbc:escape(ip), timestamp))
	local clients = {}
	return cur:fetch ({}, "a")
end

function db.getTimingOutClients(sinceTimestamp)
 	local timestamp = os.time()
	if sinceTimestamp >= timestamp then
		error("Timestamp must be in the past")
	end
	cur = dbc:execute(string.format("SELECT * FROM clients WHERE '%d' <= timeout_timestamp AND timeout_timestamp < '%d'", sinceTimestamp, timestamp))
	local clients = {}
	row = cur:fetch ({}, "a")
	while row do
		clients[#clients+1] = row.sid
		row = cur:fetch (row, "a")
	end
	return clients
end

function db.getActiveClients()
 	local timestamp = os.time()
	cur = dbc:execute(string.format("SELECT * FROM clients WHERE '%d' <= timeout_timestamp AND active = 1", timestamp))
	local clients = {}
	row = cur:fetch ({}, "a")
	while row do
		clients[#clients+1] = row.sid
		row = cur:fetch (row, "a")
	end
	return clients
end

prepareDatabase()

return db