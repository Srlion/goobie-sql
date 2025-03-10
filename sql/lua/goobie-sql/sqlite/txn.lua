local setmetatable = setmetatable

local Txn = {}
local Txn_MT = { __index = Txn }

local function NewTransaction(conn)
    local txn = setmetatable({
        open = true,
        conn = conn,
        options = conn.options,
    }, Txn_MT)
    return txn
end

function Txn:IsOpen() return self.open end

function Txn:PingSync()
    return self.conn:PingSync()
end

function Txn:Ping(callback)
    return self.conn:Ping(callback)
end

function Txn:Run(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:RunSync(query, opts)
end

function Txn:Execute(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:ExecuteSync(query, opts)
end

function Txn:Fetch(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:FetchSync(query, opts)
end

function Txn:FetchOne(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    opts = opts or {}
    opts.sync = true
    return self.conn:FetchOneSync(query, opts)
end

function Txn:TableExists(name)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:TableExists(name)
end

function Txn:UpsertQuery(tbl_name, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:UpsertQuerySync(tbl_name, opts)
end

function Txn:Commit()
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    self.open = false
    local err = self.conn:RunSync("COMMIT TRANSACTION")
    if err then
        self.conn:RunSync("ROLLBACK TRANSACTION")
    end
    return err
end

function Txn:Rollback()
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    self.open = false
    local err = self.conn:RunSync("ROLLBACK TRANSACTION")
    return err
end

local function ConnBeginSync(conn, callback)
    local status, err

    local txn = NewTransaction(conn)
    -- if creating the transaction fails, do not rollback
    local should_rollback = true
    -- this probably will only error when you try to begin a transaction inside another transaction
    err = conn:RunSync("BEGIN TRANSACTION")
    if err then
        txn.open = false
        should_rollback = false
    end

    status, err = pcall(callback, err, txn)
    if status ~= true then
        if should_rollback and txn:IsOpen() then
            txn:Rollback()
        end
        ErrorNoHaltWithStack(err)
        return
    end

    if txn:IsOpen() then
        ErrorNoHaltWithStack("transactions was left open!\n")
        txn:Rollback()
    end
end

return ConnBeginSync
