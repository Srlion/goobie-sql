# Goobie SQL

A simple, lightweight, and fast MySQL/SQLite library for Garry's Mod.

> **⚠️ Note:** The latest version requires the next Garry's Mod update (available on dev/x86-64 branch).

## 📋 Table of Contents

- [🚀 Features](#-features)
- [📦 Installation](#-installation)
- [🛠️ Quick Setup](#️-quick-setup)
- [📚 API Reference](#-api-reference)
  - [Connection Setup](#connection-setup)
  - [Connection Management](#connection-management)
  - [Query Methods](#query-methods)
  - [Transactions](#transactions)
  - [Migrations](#migrations)
  - [Cross Syntaxes](#cross-syntaxes)
- [🔧 Configuration Options](#-configuration-options)
- [📄 Examples](#-examples)

## 🚀 Features

- ✅ **Dual Database Support** - MySQL and SQLite
- ⚡ **Async & Sync** - Both asynchronous and synchronous queries
- 🔄 **Easy Transactions** - Simple transaction handling with coroutines
- 📊 **Migration System** - Built-in database migrations
- 📦 **Single File** - One-file library for easy integration

## 📦 Installation

1. Download the latest `goobie-sql.lua` from [GitHub Releases](https://github.com/Srlion/goobie-sql/releases/latest)

2. **For MySQL users:** Also download `gmsv_goobie_mysql_x_x_x.dll` and extract to:
   ```
   garrysmod/lua/bin/gmsv_goobie_mysql_x_x_x.dll
   ```

3. Add `goobie-sql.lua` to your addon's `thirdparty` folder

## 🛠️ Quick Setup

### SQLite (Recommended for beginners)
```lua
local goobie_sql = include("myaddon/thirdparty/goobie-sql.lua")
local conn = goobie_sql.NewConn({
    driver = "sqlite",
})
```

### MySQL
```lua
local goobie_sql = include("myaddon/thirdparty/goobie-sql.lua")
local conn = goobie_sql.NewConn({
    driver = "mysql",
    uri = "mysql://USERNAME:PASSWORD@HOST/DATABASE",
})
```

## 📚 API Reference

### Connection Setup

#### `goobie_sql.NewConn(options)`
Creates and starts a connection automatically. For async initialization, pass a callback as the second argument.

**Parameters:**
- `options` (table) - Connection configuration options

**Example:**
```lua
local conn = goobie_sql.NewConn({
    driver = "mysql", -- "mysql" or "sqlite"
    
    -- Error handling callback
    on_error = function(err, trace)
        print("Database error:", err)
    end,

    -- MySQL Options (choose URI or individual options)
    uri = "mysql://user:pass@host:port/db", -- Recommended
    -- OR
    host = "127.0.0.1",
    port = 3306,
    username = "root",
    password = "password",
    database = "mydb",
    
    -- Additional MySQL settings
    charset = "utf8mb4",
    collation = "utf8mb4_unicode_ci",
    timezone = "UTC",
    statement_cache_capacity = 100,
    socket = "/tmp/mysql.sock",
})
```

### Connection Management

| Method | Description | Returns |
|--------|-------------|---------|
| [`Conn:Start(callback)`](#connstart) | Connect asynchronously | - |
| [`Conn:StartSync()`](#connstartsync) | Connect synchronously | throws on error |
| [`Conn:Disconnect(callback)`](#conndisconnect) | Disconnect asynchronously | - |
| [`Conn:DisconnectSync()`](#conndisconnectsync) | Disconnect synchronously | `err` |
| [`Conn:State()`](#connstate) | Get connection state | `number` |
| [`Conn:StateName()`](#connstatename) | Get connection state name | `string` |
| [`Conn:ID()`](#connid) | Get connection ID | `number` |
| [`Conn:Host()`](#connhost) | Get host | `string` |
| [`Conn:Port()`](#connport) | Get port | `number` |
| [`Conn:Ping(callback)`](#connping) | Ping database async | - |
| [`Conn:PingSync()`](#connpingsync) | Ping database sync | `err, latency` |

### Query Methods

| Method | Type | Description | Returns |
|--------|------|-------------|---------|
| [`Conn:Run(query, opts)`](#connrun) | Async | Execute query (no result) | - |
| [`Conn:RunSync(query, opts)`](#connrunsync) | Sync | Execute query (no result) | `err` |
| [`Conn:Execute(query, opts)`](#connexecute) | Async | Execute with metadata | - |
| [`Conn:ExecuteSync(query, opts)`](#connexecutesync) | Sync | Execute with metadata | `err, result` |
| [`Conn:Fetch(query, opts)`](#connfetch) | Async | Fetch multiple rows | - |
| [`Conn:FetchSync(query, opts)`](#connfetchsync) | Sync | Fetch multiple rows | `err, rows` |
| [`Conn:FetchOne(query, opts)`](#connfetchone) | Async | Fetch single row | - |
| [`Conn:FetchOneSync(query, opts)`](#connfetchonesync) | Sync | Fetch single row | `err, row` |
| [`Conn:UpsertQuery(table, opts)`](#connupsertquery) | Async | Insert or update | - |
| [`Conn:UpsertQuerySync(table, opts)`](#connupsertquerysync) | Sync | Insert or update | `err, result` |

#### Query Options
```lua
{
    params = {"value1", "value2"}, -- Parameters for placeholders {1}, {2}
    callback = function(err, res) end, -- Async callback
    raw = false -- Set true for multi-statement queries (no params)
}
```

### Transactions

Use `Begin()` or `BeginSync()` for database transactions. Inside transactions, queries return results directly (no callbacks).

```lua
-- Async transaction
conn:Begin(function(err, txn)
    if err then return end
    
    local err, res = txn:Execute("INSERT INTO users (name) VALUES ('John')")
    if err then
        txn:Rollback() -- Must rollback explicitly on error
        return
    end
    
    local err = txn:Commit()
    print("Transaction complete, open:", txn:IsOpen()) -- false
end)

-- Sync transaction
local err, txn = conn:BeginSync()
if not err then
    local err, res = txn:Execute("INSERT INTO users (name) VALUES ('Jane')")
    if err then
        txn:Rollback()
    else
        txn:Commit()
    end
end
```

### Migrations

Run database migrations with version tracking:

```lua
local conn = goobie_sql.NewConn({
    driver = "sqlite",
    addon_name = "my_addon", -- Required for migration tracking
})

local current_version, first_run = conn:RunMigrations({
    -- Migration 1: String format
    {
        UP = [[
            CREATE TABLE users (
                id {CROSS_PRIMARY_AUTO_INCREMENTED},
                name TEXT NOT NULL,
                created_at {CROSS_OS_TIME_TYPE}
            );
        ]],
        DOWN = "DROP TABLE users;"
    },
    
    -- Migration 2: Function format
    {
        UP = function(process, conn)
            process("ALTER TABLE users ADD COLUMN email TEXT;")
        end,
        DOWN = function(process, conn)
            process("ALTER TABLE users DROP COLUMN email;")
        end
    }
})

print("Database version:", current_version, "First run:", first_run)
```

#### Conditional Migrations
```lua
{
    UP = [[
        CREATE TABLE test (
        --@ifdef SQLITE
            id INTEGER PRIMARY KEY,
        --@else
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
        --@endif
            name TEXT
        );
    ]]
}
```

### Cross Syntaxes

Write database-agnostic queries using cross-syntax placeholders:

| Placeholder | SQLite | MySQL |
|-------------|---------|-------|
| `{CROSS_NOW}` | `(CAST(strftime('%s', 'now') AS INTEGER))` | `(UNIX_TIMESTAMP())` |
| `{CROSS_PRIMARY_AUTO_INCREMENTED}` | `INTEGER PRIMARY KEY` | `BIGINT AUTO_INCREMENT PRIMARY KEY` |
| `{CROSS_COLLATE_BINARY}` | `COLLATE BINARY` | `BINARY` |
| `{CROSS_CURRENT_DATE}` | `DATE('now')` | `CURDATE()` |
| `{CROSS_OS_TIME_TYPE}` | `INT UNSIGNED NOT NULL DEFAULT (...)` | `INT UNSIGNED NOT NULL DEFAULT (...)` |
| `{CROSS_INT_TYPE}` | `INTEGER` | `BIGINT` |
| `{CROSS_JSON_TYPE}` | `TEXT` | `JSON` |

**Example:**
```lua
conn:RunSync([[
    SELECT * FROM users WHERE created_at > {CROSS_NOW}
]])
```

## 🔧 Configuration Options

### Error Object Structure
```lua
{
    message = "Error description",
    code = 1234, -- MySQL error code (optional)
    sqlstate = "42000" -- SQL state code (optional)
}
-- Has __tostring metamethod for easy printing
```

### UpsertQuery Options
```lua
local opts = {
    primary_keys = {"id"}, -- Unique/primary keys that could conflict
    inserts = {            -- Values to insert
        id = 1,
        name = "John",
        email = "john@example.com"
    },
    updates = {"name", "email"}, -- Columns to update on conflict
    binary_columns = {"data"},   -- Binary columns (SQLite specific)
    callback = function(err, res) end -- Async callback
}

conn:UpsertQuery("users", opts)
-- OR
local err, res = conn:UpsertQuerySync("users", opts)
```

## 📄 Examples

### Basic Query Examples
```lua
-- Simple insert
conn:Execute("INSERT INTO users (name) VALUES ({1})", {
    params = {"Alice"},
    callback = function(err, res)
        if err then
            print("Error:", err)
        else
            print("Inserted ID:", res.last_insert_id)
            print("Rows affected:", res.rows_affected)
        end
    end
})

-- Fetch multiple rows
conn:Fetch("SELECT * FROM users WHERE age > {1}", {
    params = {18},
    callback = function(err, rows)
        if not err then
            for i, row in ipairs(rows) do
                print("User:", row.name, "Age:", row.age)
            end
        end
    end
})

-- Fetch single row
conn:FetchOne("SELECT * FROM users WHERE id = {1}", {
    params = {1},
    callback = function(err, user)
        if not err and user then
            print("Found user:", user.name)
        end
    end
})
```

### Synchronous Examples
```lua
-- Synchronous queries (easier for simple operations)
local err = conn:RunSync("DELETE FROM users WHERE inactive = 1")
if err then
    print("Delete failed:", err)
end

local err, users = conn:FetchSync("SELECT * FROM users LIMIT 10")
if not err then
    print("Found", #users, "users")
end
```

### Advanced Transaction Example
```lua
conn:Begin(function(err, txn)
    if err then return end
    
    -- Transfer money between accounts
    local err, sender = txn:FetchOne("SELECT balance FROM accounts WHERE id = {1}", {
        params = {sender_id}
    })
    if err or not sender or sender.balance < amount then
        txn:Rollback()
        return
    end
    
    -- Deduct from sender
    local err = txn:Execute("UPDATE accounts SET balance = balance - {1} WHERE id = {2}", {
        params = {amount, sender_id}
    })
    if err then
        txn:Rollback()
        return
    end
    
    -- Add to receiver
    local err = txn:Execute("UPDATE accounts SET balance = balance + {1} WHERE id = {2}", {
        params = {amount, receiver_id}
    })
    if err then
        txn:Rollback()
        return
    end
    
    -- Commit transaction
    local err = txn:Commit()
    if not err then
        print("Transfer completed successfully!")
    end
end)
```

### Complete Setup Example
```lua
-- Complete example with error handling and migrations
local goobie_sql = include("myaddon/thirdparty/goobie-sql.lua")

local conn = goobie_sql.NewConn({
    driver = "mysql",
    uri = "mysql://user:pass@localhost/gamedb",
    addon_name = "my_gamemode",
    
    on_error = function(err, trace)
        print("[DB Error]", err.message)
        if err.code then
            print("Error code:", err.code)
        end
    end
})

-- Run migrations
local version, first_run = conn:RunMigrations({
    {
        UP = [[
            CREATE TABLE players (
                steam_id VARCHAR(32) PRIMARY KEY,
                name VARCHAR(64) NOT NULL,
                playtime {CROSS_INT_TYPE} DEFAULT 0,
                created_at {CROSS_OS_TIME_TYPE}
            );
        ]],
        DOWN = "DROP TABLE players;"
    },
    {
        UP = "ALTER TABLE players ADD COLUMN last_seen {CROSS_OS_TIME_TYPE};",
        DOWN = "ALTER TABLE players DROP COLUMN last_seen;"
    }
})

if first_run then
    print("Database initialized for the first time!")
else
    print("Database updated to version", version)
end

-- Use the connection
conn:UpsertQuery("players", {
    primary_keys = {"steam_id"},
    inserts = {
        steam_id = "STEAM_1:0:123456",
        name = "PlayerName",
        playtime = 0
    },
    updates = {"name", "last_seen"}
})
```

---

## 📞 Support

- **Documentation:** [MySQL URI Format](https://docs.rs/sqlx/latest/sqlx/mysql/struct.MySqlConnectOptions.html)
- **Issues:** [GitHub Issues](https://github.com/Srlion/goobie-sql/issues)
- **Releases:** [GitHub Releases](https://github.com/Srlion/goobie-sql/releases)

> 💡 **Pro Tip:** Ping connections sparingly! Check [this article](https://www.percona.com/blog/checking-for-a-live-database-connection-considered-harmful/) on why frequent connection pinging can be harmful.
