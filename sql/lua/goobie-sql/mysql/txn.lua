local common = include("goobie-sql/common.lua")

local coroutine = coroutine

local CheckQuery = common.CheckQuery

local Txn = {}
local Txn_MT = { __index = Txn }

-- mysql does not support begin/commit/rollback using prepared statements
local IS_RAW = { raw = true }

local function NewTransaction(conn, co, traceback)
    return setmetatable({
        conn = conn,
        conn_id = conn:ID(),
        co = co,
        traceback = traceback,
        open = true,
    }, Txn_MT)
end

local TxnQuery, TxnFinalize

local function TxnResume(txn, ...)
    local co = txn.co
    local err

    local co_status = coroutine.status(co)
    if co_status == "dead" then
        if txn.open then
            err = "transaction was left open!" .. txn.traceback
        end
    else
        local success, co_err = coroutine.resume(co, ...)
        if success then
            if coroutine.status(co) == "dead" and txn.open then
                err = "transaction was left open!" .. txn.traceback
            end
        else
            err = co_err .. "\n" .. debug.traceback(co)
        end
    end

    if err then
        ErrorNoHalt(err, "\n")
        TxnFinalize(txn, "rollback", true)
    end
end

function TxnQuery(txn, query_type, query, opts)
    opts = CheckQuery(query, opts)

    if not txn.open then
        return error("transaction is closed")
    end

    if opts.trace == nil then
        opts.trace = debug.traceback("", 2)
    end

    local conn = txn.conn
    -- we need to set locked to false to make sure queries are not queued
    -- it's not an issue if it errors or not because TxnResume will handle it anyway

    opts.callback = function(err, res)
        TxnResume(txn, err, res)
    end

    common.SetPrivate(conn, "locked", false)
    conn[query_type](conn, query, opts)
    common.SetPrivate(conn, "locked", true)

    return coroutine.yield()
end

function TxnFinalize(txn, action, failed)
    if not txn.open then
        return
    end

    local conn = txn.conn
    common.SetPrivate(conn, "locked", false)

    local err
    -- if the connection dropped/lost/reconnected, we don't want to send a query
    -- because we are not in a transaction anymore
    if conn:IsConnected() and txn.conn_id == conn:ID() then
        if failed then
            conn:Run("ROLLBACK;", IS_RAW) -- we don't care about the result
        else
            if action == "commit" then
                err = TxnQuery(txn, "Run", "COMMIT;", IS_RAW)
            elseif action == "rollback" then
                err = TxnQuery(txn, "Run", "ROLLBACK;", IS_RAW)
            end
        end

        common.SetPrivate(conn, "locked", false) -- TxnQuery will set it back to true
    end

    txn.open = false

    -- cleanup

    common.SetPrivate(conn, "txn", nil)
    txn.conn = nil
    txn.co = nil
    common.SetPrivate(conn, "locked", false)
    common.GetPrivate(conn, "ConnProcessQueue")(conn)

    return err
end

function Txn:IsOpen() return self.open end

function Txn:Ping()
    if not self.open then
        return error("transaction is closed")
    end
    return self.conn:Ping(function(err, latency)
        TxnResume(self, err, latency)
    end)
end

function Txn:Run(query, opts)
    return TxnQuery(self, "Run", query, opts)
end

function Txn:Execute(query, opts)
    return TxnQuery(self, "Execute", query, opts)
end

function Txn:Fetch(query, opts)
    return TxnQuery(self, "Fetch", query, opts)
end

function Txn:FetchOne(query, opts)
    return TxnQuery(self, "FetchOne", query, opts)
end

function Txn:TableExists(name)
    if not self.open then
        return error("transaction is closed")
    end
    local conn = self.conn
    common.SetPrivate(conn, "locked", false)
    local exists, err = conn:TableExists(name)
    common.SetPrivate(conn, "locked", true)
    return exists, err
end

function Txn:UpsertQuery(tbl_name, opts)
    return TxnQuery(self, "UpsertQuery", tbl_name, opts)
end

function Txn:Commit()
    return TxnFinalize(self, "commit")
end

function Txn:Rollback()
    return TxnFinalize(self, "rollback")
end

local function ConnBegin(conn, callback, sync)
    if type(callback) ~= "function" then
        return error("callback must be a function")
    end

    local traceback = debug.traceback("", 2)
    local callback_done = false
    conn:Run("START TRANSACTION;", {
        raw = true,
        callback = function(err)
            callback_done = true

            common.SetPrivate(conn, "locked", true)

            local co = coroutine.create(callback)
            local txn = NewTransaction(conn, co, traceback)
            common.SetPrivate(conn, "txn", txn)

            if err then
                txn.open = false
                TxnResume(txn, err)
            else
                TxnResume(txn, nil, txn)
            end

            -- this is a nice way to make it easier to use sync transactions lol
            if sync then
                while txn.open do
                    conn:Poll()
                end
            end
        end,
    })

    if sync then
        while not callback_done do
            conn:Poll()
        end
    end
end


return ConnBegin
