local common = include("goobie-sql/common.lua")
local ConnBeginSync = include("goobie-sql/sqlite/txn.lua")

local STATES = common.STATES

local type = type
local setmetatable = setmetatable
local table_insert = table.insert
local string_format = string.format
local table_HasValue = table.HasValue
local table_concat = table.concat
local CheckQuery = common.CheckQuery
local string_gsub = string.gsub
local unpack = unpack

local CROSS_SYNTAXES = common.CROSS_SYNTAXES.sqlite

local goobie_sqlite = {}

local Conn = {}
for k, v in pairs(common.COMMON_META) do
    Conn[k] = v
end

function Conn:IsMySQL() return false end

function Conn:IsSQLite() return true end

function Conn:Driver() return "SQLite" end

function Conn:State() return common.GetPrivate(self, "state") end

-- we delay async start in sqlite to be close as possible to mysql behaviour
function Conn:Start(callback)
    if type(callback) ~= "function" then
        return error("callback needs to be a function")
    end

    if self:State() == STATES.CONNECTING then
        return
    end

    common.SetPrivate(self, "state", STATES.CONNECTING)

    timer.Simple(0, function()
        common.SetPrivate(self, "state", STATES.CONNECTED)
        callback()
    end)
end

function Conn:StartSync()
    common.SetPrivate(self, "state", STATES.CONNECTED)
end

function Conn:Disconnect(callback)
    if type(callback) ~= "function" then
        return error("callback needs to be a function")
    end
    common.SetPrivate(self, "state", STATES.DISCONNECTED)
    callback()
end

function Conn:DisconnectSync()
    common.SetPrivate(self, "state", STATES.DISCONNECTED)
end

function Conn:ID() return 1 end

function Conn:Host() return "localhost" end

function Conn:Port() return 0 end

function Conn:Ping(callback)
    if type(callback) ~= "function" then
        return error("callback needs to be a function")
    end
    callback(nil, 0)
end

function Conn:PingSync()
    return nil, 0
end

local sqlite_SQLStr = sql.SQLStr
local function prepare_query(query, opts)
    opts = CheckQuery(query, opts)
    query = string_gsub(query, "{([%w_]+)}", CROSS_SYNTAXES)
    local params = opts.params
    if not opts.raw then
        query, params = common.HandleQueryParams(query, params)
    end
    opts.params = params
    return query, opts
end

local sqlite_Query = sql.Query
local sqlite_QueryTyped = sql.QueryTyped
local sqlite_LastError = sql.LastError
local function raw_query(query, opts)
    local res; if opts.raw then
        res = sqlite_Query(query)
    else
        res = sqlite_QueryTyped(query, unpack(opts.params))
    end
    if res == false then
        local last_error = sqlite_LastError()
        local err = common.SQLError(last_error)
        return err
    end
    return nil, res
end

local function ConnProcessQuery(conn, query, opts, async, exec_func)
    query, opts = prepare_query(query, opts)
    if opts.sync then
        async = false
    end
    local err, res = exec_func(query, opts)
    if err then
        local on_error = conn.on_error
        if on_error then
            ProtectedCall(on_error, err, debug.traceback("", 2))
        end
    end
    if async then
        if opts.callback then
            opts.callback(err, res)
        end
    else
        return err, res
    end
end

function Conn:RunSync(query, opts)
    return ConnProcessQuery(self, query, opts, false, raw_query)
end

function Conn:Run(query, opts)
    return ConnProcessQuery(self, query, opts, true, raw_query)
end

do
    local function internal_execute(query, opts)
        local err = raw_query(query, opts)
        if err then return err end
        local info = sqlite_QueryTyped("SELECT last_insert_rowid() AS `last_insert_id`, changes() AS `rows_affected`;")
        info = info[1]
        local res = {
            last_insert_id = info.last_insert_id,
            rows_affected = info.rows_affected,
        }
        return nil, res
    end

    function Conn:ExecuteSync(query, opts)
        return ConnProcessQuery(self, query, opts, false, internal_execute)
    end

    function Conn:Execute(query, opts)
        return ConnProcessQuery(self, query, opts, true, internal_execute)
    end
end

do
    local function internal_fetch(query, opts)
        local err, res = raw_query(query, opts)
        if err then return err end
        return nil, res or {}
    end

    function Conn:FetchSync(query, opts)
        return ConnProcessQuery(self, query, opts, false, internal_fetch)
    end

    function Conn:Fetch(query, opts)
        return ConnProcessQuery(self, query, opts, true, internal_fetch)
    end
end

do
    local function internal_fetch_one(query, opts)
        local err, res = raw_query(query, opts)
        if err then return err end
        return nil, res and res[1] or nil
    end

    function Conn:FetchOneSync(query, opts)
        return ConnProcessQuery(self, query, opts, false, internal_fetch_one)
    end

    function Conn:FetchOne(query, opts)
        return ConnProcessQuery(self, query, opts, true, internal_fetch_one)
    end
end

function Conn:TableExists(name)
    if type(name) ~= "string" then
        return error("table name must be a string")
    end
    local err, res = raw_query(
        "SELECT name FROM sqlite_master WHERE name=" .. sqlite_SQLStr(name) .. " AND type='table'", { params = {} })
    if err then
        return nil, err
    end
    return res ~= nil
end

do
    local query_count = 0
    local query_parts = {}

    local function insert_to_query(str)
        query_count = query_count + 1
        query_parts[query_count] = str
    end

    local function ConnUpsertQuery(conn, tbl_name, opts, sync)
        if type(tbl_name) ~= "string" then
            return error("table name must be a string")
        end

        query_count = 0

        local primary_keys = opts.primary_keys
        local inserts = opts.inserts
        local updates = opts.updates
        local no_escape_columns = opts.no_escape_columns

        local params = { nil, nil, nil, nil, nil, nil }
        local values = { nil, nil, nil, nil, nil, nil }

        insert_to_query("INSERT INTO`")
        insert_to_query(tbl_name)
        insert_to_query("`(")

        for column, value in pairs(inserts) do
            insert_to_query("`" .. column .. "`")
            insert_to_query(",")
            if no_escape_columns and table_HasValue(no_escape_columns, column) then
                table_insert(values, common.HandleNoEscape(value))
            else
                table_insert(values, "?")
                table_insert(params, value)
            end
        end
        query_count = query_count - 1 -- remove last comma

        insert_to_query(")VALUES(")
        insert_to_query(table_concat(values, ","))
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
                insert_to_query(string_format("`%s`=excluded.`%s`", column, column))
                insert_to_query(",")
            end

            query_count = query_count - 1 -- remove last comma
        end

        local query = table_concat(query_parts, nil, 1, query_count)

        if opts.return_query then
            return query, params
        end

        opts.params = params

        if sync then
            local err, res = conn:ExecuteSync(query, opts)
            return err, res
        else
            local err, res = conn:Execute(query, opts)
            return err, res
        end
    end

    function Conn:UpsertQuery(tbl_name, opts)
        return ConnUpsertQuery(self, tbl_name, opts, false)
    end

    function Conn:UpsertQuerySync(tbl_name, opts)
        return ConnUpsertQuery(self, tbl_name, opts, true)
    end
end

function Conn:BeginSync(callback)
    return ConnBeginSync(self, callback)
end

Conn.Begin = Conn.BeginSync

function goobie_sqlite.NewConn(opts)
    local conn = setmetatable({}, {
        __index = Conn,
        __tostring = function()
            return "Goobie SQLite Connection"
        end
    })
    common.SetPrivate(conn, "state", STATES.NOT_CONNECTED)
    return conn
end

return goobie_sqlite
