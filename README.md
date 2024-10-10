# Goobie SQL

Goobie SQL is a Garry's Mod library that allows you to interact with MySQL and SQLite databases in a simple and efficient way. It provides a simple API that allows you to connect to a database, execute queries, and fetch results with ease.

# Usage

> [!WARNING]
> MySQL version uses prepared statements, so queries can't have multiple statements, however, sqlite won't stop you from doing that, but it's not recommended. To use multiple statements, you will have to pass `raw = true` to query options, but you won't have anyway to escape strings on MySQL, so only use it for setting up your tables and migrations, nothing else.

```lua
local goobie_sql = include("goobie-sql/sh_init.lua")

-- Connect is synchronous for both mysql and sqlite, in 95% of cases, you will only be calling this when your addon is initializing, which makes it easier
-- to setup your addon, incase you will be spawning lots of connections, you can supply `async_connect` to options
-- sqlite will call on_connected at the same time as mysql version, to make it easier to write code that works with both
local conn = goobie_sql.Connect({
    driver = "mysql", -- or "sqlite" - https://github.com/Srlion/goobie-mysql
    -- async_connect = true, -- optional, if you want to connect async, this will make it not block the main thread

    -- <<v<<v<< sqlite doesn't use any of these options >>v>>v>>

    ---------------------------------------
    uri = "mysql://user:password@localhost/database",

    -- OR

    host = "localhost",
    db = "database",
    user = "user",
    password = "password",
    port = 3306,
    ---------------------------------------

    charset = "utf8mb4", -- Default charset
    collation = "utf8mb4_0900_ai_ci", -- If you don't provide one then MySQL server will select the default one
    timezone = "UTC", -- Default timezone
    statement_cache_capacity = 100,

    -- Event Callbacks
    on_connected = function(conn) -- Called when connecting asynchronously to the database
        print("Connected to database")
    end,

    on_error = function(conn, err) -- Called when an error occurs while connecting asynchronously to the database
        print("Error: " .. err.message)
    end,

    on_disconnected = function(conn, err) -- Called when the connection is closed, will always be called if async/sync
        print("Disconnected from database")
    end
})

do
    local connected, err = conn:Ping() -- this is synchronous on both mysql and sqlite
    print("Ping: " .. tostring(connected))
end

print(conn:IsConnected()) -- Returns true if the connection is open
print(conn:IsConnecting()) -- Returns true if the connection is in the process of connecting
print(conn:IsDisconnected()) -- Returns true if the connection is closed

do
    local exists, err = conn:TableExists("players") -- this is synchronous on both mysql and sqlite
    print("Table exists: " .. tostring(exists))
end

if conn:IsMySQL() then
    print("Connected to MySQL")
elseif conn:IsSQLite() then
    print("Connected to SQLite")
end

-- All query functions can be sync and async, if you pass `sync = true` in the options, it will be synchronous
-- When `sync = true` is passed, the function will return two values, the first one being the error, and the second one being the result
local err, res = conn:QUERY_FUNCTION("YOUR_QUERY", {sync = true})
-- AND -- OR
conn:QUERY_FUNCTION("YOUR_QUERY", {
    callback = function(err, res)
    end
})

conn:Execute([[
    DROP TABLE IF EXISTS TESTss;
    CREATE TABLE IF NOT EXISTS TESTss (
        id {CROSS_PRIMARY_AUTO_INCREMENTED},
        name VARCHAR(255) {CROSS_COLLATE_BINARY},
        unique_id INTEGER,
        string TEXT,
        number INTEGER,
        bool BOOLEAN,
        nill TEXT,
        login_timestamp {CROSS_OS_TIME_TYPE},
        UNIQUE (unique_id)
    );
]], {
    raw = true,
    sync = true,
})

-- Insert a row into the table
local err, res = conn:Execute([[
        INSERT INTO TESTss (name, unique_id, string, number, bool, nill)
        VALUES ({1}, {2}, {string}, {number}, {bool}, {nill})
    ]], {
        sync = true,
        params = {
            "Test", -- numberical keys
            1,

            string = "string", -- named keys
            number = 5,
            bool = true,
            nill = utils.goobie_sql.NULL,
        }
    }
)
if err then
    print("Error: " .. err.message)
    return
end

--[[
Inserted row with id: 1
Rows affected: 1
]]
print("Inserted row with id: " .. res.last_insert_id)
print("Rows affected: " .. res.rows_affected)

-- Fetch all rows from the table
-- Or fetch one row, conn:FetchOne("SELECT * FROM TESTss", ...etc
local err, res = conn:Fetch("SELECT * FROM TESTss", {
    sync = true,
})
if err then
    print("Error: " .. err.message)
    return
end
--[[
mysql output:
{
   [1] = {
      ["number"] = 5,
      ["unique_id"] = 1,
      ["id"] = 1,
      ["bool"] = true,
      ["string"] = "string",
      ["name"] = "Test",
      ["timestamp_now"] = "1728531369"
   }
}

sqlite output:
unfortunately, a limitation of gmod's sqlite driver, is that it doesn't return the correct types nor anyway to know it's type,
so you are doomed :)
https://github.com/Facepunch/garrysmod-requests/issues/2489
https://github.com/Facepunch/garrysmod-issues/issues/6023
{
   [1] = {
      ["number"] = "5",
      ["name"] = "Test",
      ["nill"] = "NULL",
      ["string"] = "string",
      ["bool"] = "1",
      ["id"] = "1",
      ["unique_id"] = "1",
      ["timestamp_now"] = "1728531347"
   }
}
]]
PrintTable(res)
]])
```
