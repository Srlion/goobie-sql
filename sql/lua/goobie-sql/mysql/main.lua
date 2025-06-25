local common = include("goobie-sql/common.lua")
local ConnBegin = include("goobie-sql/mysql/txn.lua")

local MAJOR_VERSION = common.MAJOR_VERSION
local goobie_mysql; if MAJOR_VERSION then
    local goobie_mysql_version = "goobie_mysql_" .. MAJOR_VERSION
    if not util.IsBinaryModuleInstalled(goobie_mysql_version) then
        common.errorf(
            "'%s' module doesn't exist, get it from https://github.com/Srlion/goobie-sql/releases/tag/%s",
            goobie_mysql_version, common.VERSION)
    end

    require("goobie_mysql_" .. MAJOR_VERSION)
    goobie_mysql = _G["goobie_mysql_" .. MAJOR_VERSION]
else
    _G["require"]("goobie_mysql")
    goobie_mysql = _G["goobie_mysql"]
end
if goobie_mysql.lua_loaded then return goobie_mysql end -- lua part loaded already
goobie_mysql.lua_loaded = true

local type = type
local tostring = tostring
local CheckQuery = common.CheckQuery
local table_HasValue = table.HasValue
local table_concat = table.concat
local table_insert = table.insert
local string_format = string.format
local string_gsub = string.gsub

local CROSS_SYNTAXES = common.CROSS_SYNTAXES.mysql

goobie_mysql.ERROR_META = common.ERROR_META

local Conn = goobie_mysql.CONN_META

local QUERIES = {
    Run = Conn.Run,
    Execute = Conn.Execute,
    FetchOne = Conn.FetchOne,
    Fetch = Conn.Fetch,
}

for k, v in pairs(common.COMMON_META) do
    Conn[k] = v
end

local function ConnSyncOP(conn, op)
    local done
    local err, res
    op(function(e, r)
        done = true
        err, res = e, r
    end)
    while not done do
        conn:Poll()
    end
    return err, res
end

local function ConnQueueTask(conn, func, p1, p2, p3)
    if common.GetPrivate(conn, "locked") then
        local txn = common.GetPrivate(conn, "txn")
        if txn and txn.open and coroutine.running() == txn.co then
            return error("you can't run queries on a `connection` inside an open transaction's coroutine", 2)
        end
        local queue = common.GetPrivate(conn, "queue")
        queue[#queue + 1] = { func, p1, p2, p3 }
    else
        func(conn, p1, p2, p3)
    end
end

local function ConnProcessQueue(conn)
    if common.GetPrivate(conn, "locked") then return end -- we can't process if connection is query locked

    ---@type table
    local queue = common.GetPrivate(conn, "queue")
    local queue_len = #queue
    if queue_len == 0 then return end

    common.SetPrivate(conn, "queue", {}) -- make sure to clear the queue to avoid conflicts

    for i = 1, queue_len do
        local task = queue[i]
        -- we call QueueTask again because a task can be a Transaction Begin
        local func = task[1]
        ConnQueueTask(conn, func, task[2], task[3], task[4])
    end
end

function Conn:IsMySQL() return true end

function Conn:IsSQLite() return false end

function Conn:StartSync()
    local err = ConnSyncOP(self, function(cb)
        self:Start(cb)
    end)
    if err then
        return error(tostring(err))
    end
end

function Conn:DisconnectSync()
    local err = ConnSyncOP(self, function(cb)
        self:Disconnect(cb)
    end)
    return err
end

function Conn:PingSync()
    local done, err, res
    self:Ping(function(e, r)
        done = true
        err, res = e, r
    end)
    while not done do
        self:Poll()
    end
    return err, res
end

local function prepare_query(query, opts, is_async)
    opts = CheckQuery(query, opts, is_async)
    query = string_gsub(query, "{([%w_]+)}", CROSS_SYNTAXES)
    local params = opts.params
    if not opts.raw then -- raw queries can't be escaped in sqlx, hopefully they expose an escape function
        query, params = common.HandleQueryParams(query, params)
    end
    opts.params = params
    return query, opts
end

local function create_query_method(query_type)
    local query_func = QUERIES[query_type]

    Conn[query_type] = function(self, query, opts)
        query, opts = prepare_query(query, opts, true)
        if opts.sync then
            return ConnSyncOP(self, function(cb)
                opts.callback = cb
                ConnQueueTask(self, query_func, query, opts)
            end)
        else
            ConnQueueTask(self, query_func, query, opts)
        end
    end

    Conn[query_type .. "Sync"] = function(self, query, opts)
        query, opts = prepare_query(query, opts)
        return ConnSyncOP(self, function(cb)
            opts.callback = cb
            ConnQueueTask(self, query_func, query, opts)
        end)
    end
end

create_query_method("Run")
create_query_method("Execute")
create_query_method("Fetch")
create_query_method("FetchOne")

-- someone could ask, why the hell is this function synchronous? because for obvious reasons,
-- you use this function when setting up your server, so it's not a big deal if it's synchronous
function Conn:TableExists(name)
    if type(name) ~= "string" then
        return error("table name must be a string")
    end
    local err, data = self:FetchOneSync("SHOW TABLES LIKE '" .. name .. "'")
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

    local function ConnUpsertQuery(conn, tbl_name, opts, sync)
        if type(tbl_name) ~= "string" then
            return error("table name must be a string")
        end

        query_count = 0

        -- mysql doesn't use primary keys, so we don't need to check for them to keep consistency with sqlite
        if not opts.primary_keys then
            return error("upsert query must have primary_keys")
        end

        local inserts = opts.inserts
        local updates = opts.updates
        local no_escape_columns = opts.no_escape_columns

        local params = { nil, nil, nil, nil, nil, nil }
        local values = { nil, nil, nil, nil, nil, nil }

        -- INSERT INTO `tbl_name`(`column1`, ...) VALUES(?, ?, ...) ON DUPLICATE KEY UPDATE `column1`=VALUES(`column1`), ...
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
        insert_to_query(")ON DUPLICATE KEY UPDATE")

        -- basically, if there are no updates, we just update the first column with itself
        if updates == nil or #updates == 0 then
            local next_key = next(inserts)
            updates = { next_key }
        end

        for i = 1, #updates do
            local column = updates[i]
            insert_to_query(string_format("`%s`=VALUES(`%s`)", column, column))
            insert_to_query(",")
        end
        query_count = query_count - 1 -- remove last comma

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

function Conn:Begin(callback)
    return ConnBegin(self, callback, false)
end

function Conn:BeginSync(callback)
    return ConnBegin(self, callback, true)
end

local RealNewConn = goobie_mysql.NewConn
function goobie_mysql.NewConn(opts)
    local conn = RealNewConn(opts)
    common.SetPrivate(conn, "queue", {})
    common.SetPrivate(conn, "ConnProcessQueue", ConnProcessQueue)
    return conn
end

return goobie_mysql
