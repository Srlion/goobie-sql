local type = type

local tonumber = tonumber
local tostring = tostring
local setmetatable = setmetatable
local pcall = pcall
local pairs = pairs

local tableinsert = table.insert
local tableconcat = table.concat
local tableHasValue = table.HasValue

local stringformat = string.format
local stringrep = string.rep
local stringsub = string.sub
local stringgsub = string.gsub
local stringfind = string.find
local stringbyte = string.byte
local stringchar = string.char

local GOOBIE_MYSQL_VERSION = "0.2.4"
GOOBIE_MYSQL_VERSION = GOOBIE_MYSQL_VERSION:gsub("%.", "_")

local PARAMS_PATTERN = "{[%s]*([%w_]+)[%s]*:?[%s]*([%a_,?]*)[%s]*}"

local STATES = {
    CONNECTED = 1,
    CONNECTING = 2,
    NOT_CONNECTED = 3,
    DISCONNECTED = 4,
    ERROR = 5,
}

local goobie_sql = {
    ["NULL"] = {},
    STATES = STATES,

    VERSION = "0.1.8",
}

local CROSS_SYNTAXES = {
    sqlite = {
        CROSS_NOW = "(CAST(strftime('%s', 'now') AS INTEGER))",
        -- INTEGER PRIMARY KEY auto increments in SQLite, see https://www.sqlite.org/autoinc.html
        CROSS_PRIMARY_AUTO_INCREMENTED = "INTEGER PRIMARY KEY",
        CROSS_COLLATE_BINARY = "COLLATE BINARY",
        CROSS_CURRENT_DATE = "DATE('now')",
        CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER))",
        CROSS_INT_TYPE = "INTEGER",
        CROSS_JSON_TYPE = "TEXT",
    },
    mysql = {
        CROSS_NOW = "(UNIX_TIMESTAMP())",
        CROSS_PRIMARY_AUTO_INCREMENTED = "BIGINT AUTO_INCREMENT PRIMARY KEY",
        CROSS_COLLATE_BINARY = "BINARY",
        CROSS_CURRENT_DATE = "CURDATE()",
        CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (UNIX_TIMESTAMP())",
        CROSS_INT_TYPE = "BIGINT",
        CROSS_JSON_TYPE = "JSON",
    },
}

do
    local hex = function(c)
        return stringformat("%02X", stringbyte(c))
    end
    function goobie_sql.StringToHex(text)
        return (stringgsub(text, ".", hex))
    end

    local unhex = function(cc)
        return stringchar(tonumber(cc, 16))
    end
    function goobie_sql.StringFromHex(text)
        return (stringgsub(text, "..", unhex))
    end
end

-- These so you can override them in your own code
function goobie_sql.Error(msg, ...)
    return ErrorNoHaltWithStack(stringformat(msg, ...))
end

function goobie_sql.ErrorHalt(msg, ...)
    return error(stringformat(msg, ...))
end

function goobie_sql.ErrorHaltLevel(msg, level, ...)
    return error(stringformat(msg, ...), level)
end

function goobie_sql.SetTypeFunc(func)
    type = func
end
-------------------------------------

local handle_query_parameters; do
    local fquery_params
    local fquery_new_params
    local escape_function
    local gsub_f = function(key, options)
        -- local no_quotes = options:find("no_quotes") ~= nil
        local no_escape = stringfind(options, "no_escape", 1, true) ~= nil
        local is_binary = stringfind(options, "binary", 1, true) ~= nil
        local raw_value = fquery_params[tonumber(key)] or fquery_params[key]

        if raw_value == nil then
            return goobie_sql.ErrorHalt("missing parameter for query: %s", key)
        end

        if raw_value == goobie_sql.NULL then
            return "NULL"
        end

        if no_escape then
            return raw_value
        end

        tableinsert(fquery_new_params, raw_value)

        return escape_function(raw_value, {is_binary = is_binary})
    end

    function handle_query_parameters(query, params, escape_func)
        fquery_new_params = {}
        fquery_params = params
        escape_function = escape_func

        -- We don't return the query immediately as that could cause hidden bugs. We must ensure that if the developer is using
        -- placeholders, they are checked for missing parameters.
        if fquery_params == nil then
            fquery_params = {}
        elseif type(fquery_params) ~= "table" then
            return goobie_sql.ErrorHalt("params must be a table, got %s", type(fquery_params))
        end

        return (stringgsub(query, PARAMS_PATTERN, gsub_f)), fquery_new_params
    end
end

local function handle_options(options)
    if options == nil then
        return {}
    elseif type(options) ~= "table" then
        return goobie_sql.ErrorHalt("options must be a table, got %s", type(options))
    end

    return options
end

-------------------------------------
-- MySQL
-------------------------------------
local mysql = {}; do
    local goobie_mysql

    local CONN_METHODS = {}
    local CONN_META = {__index = CONN_METHODS}

    function mysql.Connect(options)
        do
            local goobie_mysql_name = "goobie_mysql_" .. GOOBIE_MYSQL_VERSION
            if not util.IsBinaryModuleInstalled(goobie_mysql_name) then
                local err = string.format("%s module doesn't exist, get it from https://github.com/Srlion/goobie-mysql/releases/tag/%s",
                goobie_mysql_name, GOOBIE_MYSQL_VERSION)
                goobie_sql.ErrorHalt(err)
            end

            require(goobie_mysql_name)

            goobie_mysql = _G[goobie_mysql_name]
        end

        local inner_conn = goobie_mysql.NewConn(options)

        local conn = setmetatable({
            inner = inner_conn,
            options = options,
        }, CONN_META)

        return conn
    end

    function mysql.Poll()
        goobie_mysql.Poll()
    end
    CONN_METHODS.Poll = mysql.Poll

    function CONN_METHODS:IsMySQL()
        return true
    end

    function CONN_METHODS:IsSQLite()
        return false
    end

    function CONN_METHODS:StartSync()
        self.inner:StartSync()
    end

    function CONN_METHODS:StartAsync()
        self.inner:Start()
    end

    function CONN_METHODS:DisconnectSync()
        self.inner:DisconnectSync()
    end

    function CONN_METHODS:DisconnectAsync()
        self.inner:Disconnect()
    end

    function CONN_METHODS:State()
        return self.inner:State()
    end

    function CONN_METHODS:IsConnected()
        return self.inner:IsConnected()
    end

    function CONN_METHODS:IsConnecting()
        return self.inner:IsConnecting()
    end

    function CONN_METHODS:IsDisconnected()
        return self.inner:IsDisconnected()
    end

    function CONN_METHODS:Ping()
        return self.inner:Ping()
    end

    local escape_function = function() return "?" end
    function CONN_METHODS:PreQuery(query, options)
        local params = options.params
        query = stringgsub(query, "{([%w_]+)}", CROSS_SYNTAXES.mysql)

        if not options.raw then
            query, params = handle_query_parameters(query, params, escape_function)
        end

        query = self:ApplyTablePrefix(query)

        return query, params
    end

    function CONN_METHODS:ApplyTablePrefix(query)
        local table_prefix = self.options.table_prefix
        local server_table_prefix = self.options.server_table_prefix
        if table_prefix and server_table_prefix then
            query = stringgsub(query, table_prefix, server_table_prefix .. table_prefix)
        end
        return query
    end

    function CONN_METHODS:Execute(query, options)
        options = handle_options(options)

        local params
        query, params = self:PreQuery(query, options)
        options.params = params

        return self.inner:Execute(query, options)
    end

    function CONN_METHODS:Fetch(query, options)
        options = handle_options(options)

        local params
        query, params = self:PreQuery(query, options)
        options.params = params

        return self.inner:Fetch(query, options)
    end

    function CONN_METHODS:FetchOne(query, options)
        options = handle_options(options)

        local params
        query, params = self:PreQuery(query, options)
        options.params = params

        return self.inner:FetchOne(query, options)
    end

    -- someone could ask, why the hell is this function synchronous? because for obvious reasons,
    -- you use this function when setting up your server, so it's not a big deal if it's synchronous
    function CONN_METHODS:TableExists(name)
        if type(name) ~= "string" then
            return goobie_sql.ErrorHalt("table name must be a string")
        end

        name = self:ApplyTablePrefix(name)

        local err, data = self.inner:FetchOne("SHOW TABLES LIKE '" .. name .. "'", {sync = true})
        if err then
            return nil, err
        end

        return data ~= nil
    end

    do
        local query_count = 0
        local query_parts = {}

        local function insert_to_query(str)
            query_count = query_count + 1
            query_parts[query_count] = str
        end

        function CONN_METHODS:UpsertQuery(tbl_name, options)
            query_count = 0

            tbl_name = self:ApplyTablePrefix(tbl_name)

            local inserts = options.inserts
            local updates = options.updates

            local params = {}

            -- INSERT INTO `tbl_name`(`column1`, ...) VALUES(?, ?, ...) ON DUPLICATE KEY UPDATE `column1`=VALUES(`column1`), ...
            insert_to_query("INSERT INTO`")
            insert_to_query(tbl_name)
            insert_to_query("`(")

            for column, value in pairs(inserts) do
                insert_to_query("`" .. column .. "`")
                insert_to_query(",")
                tableinsert(params, value)
            end
            query_count = query_count - 1 -- remove last comma

            insert_to_query(")VALUES(")
            do
                local placeholders = stringrep("?,", #params)
                placeholders = stringsub(placeholders, 1, -2) -- remove last comma

                insert_to_query(placeholders)
            end

            insert_to_query(")ON DUPLICATE KEY UPDATE")

            -- basically, if there are no updates, we just update the first column with itself
            if updates == nil or #updates == 0 then
                updates = {next(inserts)}
            end

            for i = 1, #updates do
                local column = updates[i]
                insert_to_query(stringformat("`%s`=VALUES(`%s`)", column, column))
                insert_to_query(",")
            end
            query_count = query_count - 1 -- remove last comma

            local query = tableconcat(query_parts, nil, 1, query_count)

            if options.return_query then
                return query, params
            end

            options.params = params

            return self.inner:Execute(query, options)
        end
    end

    local Transaction = {}; do
        local METHODS = {}

        function Transaction.New(txn, conn)
            return setmetatable({
                conn = conn,
                inner = txn,
                options = conn.options
            }, {__index = METHODS})
        end

        function METHODS:IsOpen()
            return self.inner:IsOpen()
        end

        METHODS.Ping = CONN_METHODS.Ping
        METHODS.PreQuery = CONN_METHODS.PreQuery
        METHODS.Execute = CONN_METHODS.Execute
        METHODS.Fetch = CONN_METHODS.Fetch
        METHODS.FetchOne = CONN_METHODS.FetchOne
        METHODS.TableExists = CONN_METHODS.TableExists
        METHODS.UpsertQuery = CONN_METHODS.UpsertQuery
        METHODS.ApplyTablePrefix = CONN_METHODS.ApplyTablePrefix

        function METHODS:Commit()
            return self.inner:Commit()
        end

        function METHODS:Rollback()
            return self.inner:Rollback()
        end
    end

    function CONN_METHODS:Begin(func)
        return self.inner:Begin(function(err, txn)
            local txn_obj = Transaction.New(txn, self)
            return func(err, txn_obj)
        end)
    end

    function CONN_METHODS:BeginSync(func)
        return self.inner:BeginSync(function(err, txn)
            local txn_obj = Transaction.New(txn, self)
            return func(err, txn_obj)
        end)
    end
end
-------------------------------------

-------------------------------------
-- SQLite
-------------------------------------
local sqlite = {}; do
    local sqlQuery = sql.Query
    local sqlLastError = sql.LastError
    local sqlSQLStr = sql.SQLStr

    local CONN_METHODS = {}
    local CONN_META = {__index = CONN_METHODS}

    function sqlite.Connect(options)
        local conn = setmetatable({
            state = STATES.NOT_CONNECTED,
            options = options
        }, CONN_META)
        return conn
    end

    function sqlite.Poll()
    end

    function CONN_METHODS:Poll()
    end

    function CONN_METHODS:IsMySQL()
        return false
    end

    function CONN_METHODS:IsSQLite()
        return true
    end

    function CONN_METHODS:StartSync()
        self.state = STATES.CONNECTED
    end

    function CONN_METHODS:StartAsync()
        if STATES.CONNECTING then
            return
        end

        self.state = STATES.CONNECTING

        local on_connected = self.options.on_connected
        if not on_connected then return end

        timer.Simple(0, function()
            self.state = STATES.CONNECTED

            if on_connected then
                on_connected(self)
            end
        end)
    end

    function CONN_METHODS:DisconnectSync()
        if self.state ~= STATES.CONNECTED then return end
        self.state = STATES.DISCONNECTED

        local on_disconnected = self.options.on_disconnected
        if on_disconnected then
            on_disconnected(self)
        end
    end
    CONN_METHODS.DisconnectAsync = CONN_METHODS.DisconnectSync

    function CONN_METHODS:State()
        return self.state
    end

    function CONN_METHODS:IsConnected()
        return self.state == STATES.CONNECTED
    end

    function CONN_METHODS:IsConnecting()
        return self.state == STATES.CONNECTING
    end

    function CONN_METHODS:IsDisconnected()
        return self.state == STATES.DISCONNECTED
    end

    function CONN_METHODS:Ping()
        return true
    end

    local escape_function = function(value, options)
        local value_type = type(value)
        if value_type == "string" then
            if options.is_binary then
                return "X'" .. goobie_sql.StringToHex(value) .. "'"
            else
                return sqlSQLStr(value)
            end
        elseif value_type == "number" then
            return tostring(value)
        elseif value_type == "boolean" then
            return value and "TRUE" or "FALSE"
        else
            return goobie_sql.ErrorHalt("invalid type '%s' was passed to escape '%s'", value_type, value)
        end
    end
    function CONN_METHODS:PreQuery(query, options)
        local params = options.params
        query = stringgsub(query, "{([%w_]+)}", CROSS_SYNTAXES.sqlite)

        if not options.raw then
            query, params = handle_query_parameters(query, params, escape_function)
        end

        return query, params
    end

    local function handle_query(query, options)
        options = handle_options(options)
        query, options.params = CONN_METHODS.PreQuery(nil, query, options)

        local res = sqlQuery(query)
        if res == false then
            local err = {message = sqlLastError()}

            if options.sync then
                return err
            end

            return err
        end

        if res == nil then
            res = {}
        end

        return nil, res
    end

    function CONN_METHODS:Execute(query, options)
        local err, res = handle_query(query, options)
        if err then
            if options.sync then
                return err
            end

            if options.callback then
                options.callback(err)
            else
                goobie_sql.Error("Query error: " .. err.message)
            end

            return
        end

        local query_info = sqlQuery("SELECT last_insert_rowid() AS `last_insert_id`, CHANGES() AS `rows_affected`;")
        query_info = query_info[1]

        res = {
            last_insert_id = tonumber(query_info.last_insert_id),
            rows_affected = tonumber(query_info.rows_affected),
        }

        if options.sync then
            return nil, res
        end

        if options.callback then
            options.callback(nil, res)
        end
    end

    function CONN_METHODS:Fetch(query, options)
        local err, res = handle_query(query, options)
        if err then
            if options.sync then
                return err
            end

            if options.callback then
                options.callback(err)
            else
                goobie_sql.Error("Query error: " .. err.message)
            end

            return
        end

        if options.sync then
            return nil, res
        end

        if options.callback then
            options.callback(nil, res)
        end
    end

    function CONN_METHODS:FetchOne(query, options)
        local err, res = handle_query(query, options)
        if err then
            if options.sync then
                return err
            end

            if options.callback then
                options.callback(err)
            else
                goobie_sql.Error("Query error: " .. err.message)
            end

            return
        end

        local first_row = res[1]

        if options.sync then
            return nil, first_row
        end

        if options.callback then
            options.callback(nil, first_row)
        end
    end

    function CONN_METHODS:TableExists(name)
        if type(name) ~= "string" then
            return goobie_sql.ErrorHalt("table name must be a string")
        end

        local data = sqlQuery("SELECT name FROM sqlite_master WHERE name=" .. sqlSQLStr(name) .. " AND type='table'")
        if data == false then
            return nil, {message = sqlLastError()}
        end

        return data ~= nil
    end

    do
        local query_count = 0
        local query_parts = {}

        local function insert_to_query(str)
            query_count = query_count + 1
            query_parts[query_count] = str
        end

        function CONN_METHODS:UpsertQuery(tbl_name, options)
            query_count = 0

            local primary_keys = options.primary_keys
            local inserts = options.inserts
            local updates = options.updates
            local binary_columns = options.binary_columns or {}

            local values = {nil, nil, nil, nil, nil, nil}

            insert_to_query("INSERT INTO`")
            insert_to_query(tbl_name)
            insert_to_query("`(")

            for column, value in pairs(inserts) do
                insert_to_query("`" .. column .. "`")
                insert_to_query(",")
                if tableHasValue(binary_columns, column) then
                    value = goobie_sql.StringToHex(value)
                    tableinsert(values, "X'" .. value .. "'")
                else
                    tableinsert(values, sqlSQLStr(value))
                end
            end
            query_count = query_count - 1 -- remove last comma

            insert_to_query(")VALUES(")
            insert_to_query(tableconcat(values, ","))
            insert_to_query(")ON CONFLICT(")

            for i = 1, #primary_keys do
                insert_to_query("`" .. primary_keys[i] .. "`")
                insert_to_query(",")
            end
            query_count = query_count - 1 -- remove last comma

            if updates == nil or #updates == 0 then
                insert_to_query(")DO NOTHING")
            else
                insert_to_query(")DO UPDATE SET ")

                for i = 1, #updates do
                    local column = updates[i]
                    insert_to_query(stringformat("`%s`=excluded.`%s`", column, column))
                    insert_to_query(",")
                end

                query_count = query_count - 1 -- remove last comma
            end

            local query = tableconcat(query_parts, nil, 1, query_count)

            if options.return_query then
                return query, {}
            end

            return self:Execute(query, options)
        end
    end

    local Transaction = {}; do
        local METHODS = {}

        function Transaction.New()
            return setmetatable({open = true}, {__index = METHODS})
        end

        function METHODS:IsOpen()
            return self.open == true
        end

        function METHODS:Ping()
            return true
        end

        function METHODS:Execute(query, options)
            options = handle_options(options)

            if not self:IsOpen() then
                return goobie_sql.ErrorHalt("transaction is closed")
            end

            options.sync = true

            return CONN_METHODS.Execute(nil, query, options)
        end

        function METHODS:Fetch(query, options)
            options = handle_options(options)

            if not self:IsOpen() then
                return goobie_sql.ErrorHalt("transaction is closed")
            end

            options.sync = true

            return CONN_METHODS.Fetch(nil, query, options)
        end

        function METHODS:FetchOne(query, options)
            options = handle_options(options)

            if not self:IsOpen() then
                return goobie_sql.ErrorHalt("transaction is closed")
            end

            options.sync = true

            return CONN_METHODS.FetchOne(nil, query, options)
        end

        METHODS.TableExists = CONN_METHODS.TableExists
        METHODS.UpsertQuery = CONN_METHODS.UpsertQuery

        function METHODS:Commit()
            if not self:IsOpen() then
                return goobie_sql.ErrorHalt("transaction is closed")
            end

            self.open = false

            local err = CONN_METHODS.Execute(nil, "COMMIT TRANSACTION", {sync = true})
            if err then
                sqlQuery("ROLLBACK TRANSACTION")
            end

            return err
        end

        function METHODS:Rollback()
            if not self:IsOpen() then
                return goobie_sql.ErrorHalt("transaction is closed")
            end

            self.open = false

            local err = CONN_METHODS.Execute(nil, "ROLLBACK TRANSACTION", {sync = true})
            return err
        end
    end

    function CONN_METHODS:Begin(func)
        local status, err

        local txn = Transaction.New()

        -- if creating the transaction fails, no need to rollback
        local should_rollback = true
        -- this probably will only error when you try to begin a transaction inside another transaction
        err = CONN_METHODS.Execute(nil, "BEGIN TRANSACTION", {sync = true})
        if err then
            should_rollback = false
        end

        status, err = pcall(func, err, txn)
        if status ~= true then
            if should_rollback and txn:IsOpen() then
                txn:Rollback()
            end
            return goobie_sql.ErrorHaltLevel(err, 0)
        end

        if txn:IsOpen() then
            ErrorNoHaltWithStack("forgot to finalize transaction!\n")
            txn:Rollback()
        end
    end
    CONN_METHODS.BeginSync = CONN_METHODS.Begin
end
-------------------------------------

goobie_sql.mysql = mysql
goobie_sql.sqlite = sqlite

function goobie_sql.Connect(options)
    if type(options) ~= "table" then
        return goobie_sql.ErrorHalt("options must be a table, got %s", type(options))
    end

    local conn
    if options.driver == "mysql" then
        conn = mysql.Connect(options)
    elseif options.driver == "sqlite" then
        conn = sqlite.Connect(options)
    else
        return goobie_sql.ErrorHalt("invalid driver '%s'", options.driver)
    end

    if options.async_connect then
        conn:StartAsync()
    else
        conn:StartSync()
    end

    return conn
end

return goobie_sql
