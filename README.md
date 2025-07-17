# Goobie SQL

A simple, lightweight, and fast MySQL/SQLite library for Garry's Mod.

> **Note (Added 10/Jul/2025):** The latest version will only work on the next Garry's Mod update (currently available on the dev/x86-64 branch, just waiting for sql.QueryTyped).

## Features

- MySQL and SQLite.
- Asynchronous and synchronous queries.
- Easy to use transactions. (Using coroutines)
- Simple migrations system.
- One-file library.

## Installation

Download the latest `goobie-sql.lua` from [GitHub releases](https://github.com/Srlion/goobie-sql/releases/latest).

- If you are going to use MySQL, also download the `gmsv_goobie_mysql_x_x_x.dll` from [GitHub releases](https://github.com/Srlion/goobie-sql/releases/latest). Extract it to `garrysmod/lua/bin/gmsv_goobie_mysql_x_x_x.dll`.

Add `goobie-sql.lua` to your addon folder in `thirdparty`.

## Usage

#### SQLite

```lua
local goobie_sql = include("myaddon/thirdparty/goobie-sql.lua")
local conn = goobie_sql.NewConn({
    driver = "sqlite",
})
```

#### MySQL

```lua
local goobie_sql = include("myaddon/thirdparty/goobie-sql.lua")
local conn = goobie_sql.NewConn({
    driver = "mysql",
    uri = "mysql://USERNAME:PASSWORD@HOST/DATABASE",
})
```

## Documentation

```lua
-- NewConn Starts a connection automatically synchronously, if you want to use it asynchronously, pass a function as the second argument.
local conn = goobie_sql.NewConn({
    driver = "mysql", -- or "sqlite"

    -- called when a query returns an error
    on_error = function(err, trace)
    end,

    -- MySQL specific options

    -- The URI format is `mysql://[user[:password]@][host][:port]/[database][?properties]`.
    -- Read more info here https://docs.rs/sqlx/latest/sqlx/mysql/struct.MySqlConnectOptions.html
    uri = "mysql://USERNAME:PASSWORD@HOST/DATABASE",
    -- OR
    host = "127.0.0.1",
    port = 3306,
    username = "root",
    password = "1234",
    database = "test",

    charset = "utf8mb4",
    collation = "utf8mb4_unicode_ci",
    timezone = "UTC",
    statement_cache_capacity = 100,
    socket = "/tmp/mysql.sock",
})
```

### Error object

```lua
{
    message = string,
    code = number|nil,
    sqlstate = string|nil,
}
```

- Has `__tostring` metamethod that returns a formatted string.

### Query options

```lua
{
    params = table, -- {1, 3, 5}
    callback = function(err, res),
    end,
    -- if true, the params will not be used and you can have multi statement queries.
    raw = boolean
}
```

### Connection methods

`Conn:Start(function(err) end)`

- Attempts to reconnect if the connection is lost.

`Conn:StartSync()`

- Attempts to reconnect if the connection is lost.
- Throws an error if the connection fails.

`Conn:Disconnect(function(err) end)`

- Disconnects from the database asynchronously.

`Conn:DisconnectSync()` -> `err`

- Disconnects from the database synchronously.
- Unlike `Conn:StartSync`, this function returns an error if the connection fails.

`Conn:State()` -> `state: number`

`Conn:StateName()` -> `state: string`

- Returns the current state of the connection as a string.

`Conn:ID()` -> `id: number`

- Returns the id of the inner mysql connection, it's incremental for each inner connection that is created.
- Returns 1 if it's sqlite connection.

`Conn:Host()` -> `host: string`

`Conn:Port()` -> `port: number`

`Conn:Ping(function(err, latency) end)`

- Pings the database to check the connection status.
- **Note:** It's generally not recommended to use this method to check if a connection is alive, as it may not be reliable. For more information, refer to [this article](https://www.percona.com/blog/checking-for-a-live-database-connection-considered-harmful/).

`Conn:PingSync()` -> `err, latency`

- Pings the database to check the connection status.

### Query methods

`Conn:Run(query: string, opts: table)`

- Runs a query asynchronously.
- Callback gets called with `err` if the query fails. Nothing is passed if the query succeeds.

`Conn:RunSync(query: string, opts: table)` -> `err`

`Conn:Execute(query: string, opts: table)` -> `err, res`

- Executes a query asynchronously.
- Callback gets called with `err, res` where `res` is a table with the following fields:
  - `last_insert_id: number`
  - `rows_affected: number`

`Conn:ExecuteSync(query: string, opts: table)` -> `err, res`

`Conn:Fetch(query: string, opts: table)` -> `err, res`

- Fetches a query asynchronously.
- Callback gets called with `err, res` where `res` is an array of rows.

`Conn:FetchSync(query: string, opts: table)` -> `err, res`

`Conn:FetchOne(query: string, opts: table)` -> `err, res`

- Fetches a single row asynchronously.
- Callback gets called with `err, res` where `res` is a single row.

`Conn:FetchOneSync(query: string, opts: table)` -> `err, res`

#### Example

```lua
conn:Execute("INSERT INTO test_table (value, value2) VALUES ({1}, {2})", {
    params = {"test", "test2"},
    callback = function(err, res)
        print(err, res)
    end
})
```

### UpsertQuery

```lua
local opts = {
    -- primary keys that could conflict, basically the unique/primary key
    primary_keys = { "id" },
    -- will try to insert these values, if it fails due to a conflict, it will update the values
    inserts = {
        id = 1,
        value = "test",
    },
    -- if the insert fails due to a conflict, these values will be updated
    updates = { "value" },
    binary_columns = { "value" }, -- if you want to insert binary data, you need to specify the columns that are binary, this is just sqlite specific till Rubat adds https://github.com/Facepunch/garrysmod-requests/issues/2654
    callback = function(err, res)
    end,
}

Conn:UpsertQuery("test_table", opts)
local err, res = Conn:UpsertQuerySync("test_table", opts)
```

### Transactions

Inside `Begin(Sync)`, you don't use callback, instead queries return errors and results directly.

In MySQL, this is achieved by using coroutines to make transactions easier to use.

```lua
Conn:Begin(function(err, txn)
    if err then
        return
    end
    local err, res = txn:Execute("INSERT INTO test_table (value) VALUES ('test')")
    if err then
        txn:Rollback() -- you must rollback explicitly if you want to stop execution
        return
    end
    local err = txn:Commit()
    print(txn:IsOpen()) -- false
end)

-- If you want to have it run synchronously, you can use `BeginSync`, it's the the same as `Begin` but instead everything runs synchronously.
```

### Cross Syntaxes

Cross syntaxes try to make queries easier to write for both SQLite and MySQL.

Here is a list of current cross syntaxes:

```lua
--- SQLite
{
    CROSS_NOW = "(CAST(strftime('%s', 'now') AS INTEGER))",
    -- INTEGER PRIMARY KEY auto increments in SQLite, see https://www.sqlite.org/autoinc.html
    CROSS_PRIMARY_AUTO_INCREMENTED = "INTEGER PRIMARY KEY",
    CROSS_COLLATE_BINARY = "COLLATE BINARY",
    CROSS_CURRENT_DATE = "DATE('now')",
    CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER))",
    CROSS_INT_TYPE = "INTEGER",
    CROSS_JSON_TYPE = "TEXT",
}

--- MySQL
{
    CROSS_NOW = "(UNIX_TIMESTAMP())",
    CROSS_PRIMARY_AUTO_INCREMENTED = "BIGINT AUTO_INCREMENT PRIMARY KEY",
    CROSS_COLLATE_BINARY = "BINARY",
    CROSS_CURRENT_DATE = "CURDATE()",
    CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (UNIX_TIMESTAMP())",
    CROSS_INT_TYPE = "BIGINT",
    CROSS_JSON_TYPE = "JSON",
}
```

They can be used in the following way:

```lua
conn:RunMigrations({
    {
        UP = [[
                CREATE TABLE IF NOT EXISTS test_table (
                    id {CROSS_PRIMARY_AUTO_INCREMENTED},
                    value TEXT,
                    `created_at` {CROSS_OS_TIME_TYPE},
                );
            ]],
        DOWN = [[
            DROP TABLE test_table;
        ]]
    }
})

conn:RunSync([[
    SELECT * FROM test_table WHERE `created_at` > {CROSS_NOW};
]])
```

### Migrations

```lua
local conn = goobie_sql.NewConn({
    driver = "sqlite",
    addon_name = "test",
})

local current_version, first_run = conn:RunMigrations({
    -- can use string or function for UP and DOWN
    {
        UP = [[
                CREATE TABLE IF NOT EXISTS test_table (
                    id INTEGER PRIMARY KEY,
                    value TEXT
                );
            ]],
        DOWN = [[
            DROP TABLE test_table;
        ]]
    },
    {
        UP = function(process, conn)
            process([[
                CREATE TABLE IF NOT EXISTS test_table (
                    id INTEGER PRIMARY KEY,
                    value TEXT
                );
            ]])
        end,
        DOWN = function(process, conn)
            process([[
                DROP TABLE test_table;
            ]])
        end,
    }
})

print(current_version, first_run)
```

You can also have conditionals in your migrations:

```lua
conn:RunMigrations({
    {
        UP = [[
            CREATE TABLE IF NOT EXISTS test_table (
            --@ifdef SQLITE
                id INTEGER PRIMARY KEY,
            --@else
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
            --@endif
                value TEXT
            );
        ]],
        DOWN = [[
            DROP TABLE test_table;
        ]]
    }
})
```
