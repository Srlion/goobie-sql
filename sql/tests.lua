local goobie_sql = include("goobie-sql/goobie-sql.lua")

local TestSuite = {}
TestSuite.__index = TestSuite

function TestSuite.New()
    return setmetatable({
        tests = {}
    }, TestSuite)
end

function TestSuite:Add(name, fn)
    table.insert(self.tests, { name = name, fn = fn })
end

function TestSuite:Run(on_start, after_each, on_end, conn)
    local i = 1

    local function runNextTest()
        if i > #self.tests then
            on_end(conn)
            print("All tests complete.")
            return
        end

        local test = self.tests[i]
        i = i + 1
        print("Running test: " .. test.name)
        local callbackCalled = false

        local function nextCallback()
            if callbackCalled then return end
            callbackCalled = true
            after_each(conn)
            runNextTest()
        end

        local success, err = pcall(test.fn, nextCallback, conn)
        if not success then
            print("Test '" .. test.name .. "' failed with error: " .. err)
            nextCallback()
        end
    end

    on_start(conn)

    runNextTest()
end

local suite = TestSuite.New()

suite:Add("ConnID", function(next, conn)
    assert(conn:ID() == 1, "ID should be 1")
    next()
end)

suite:Add("ConnHost", function(next, conn)
    assert(type(conn:Host()) == "string", "Host should be a string")
    next()
end)

suite:Add("ConnPort", function(next, conn)
    assert(type(conn:Port()) == "number", "Port should be a number")
    next()
end)

suite:Add("ConnPing", function(next, conn)
    conn:Ping(function(err, latency)
        assert(err == nil, "Ping should succeed without error")
        assert(type(latency) == "number", "Latency should be a number")
        next()
    end)
end)

suite:Add("ConnPingSync", function(next, conn)
    local err, latency = conn:PingSync()
    assert(err == nil, "PingSync should succeed without error")
    assert(type(latency) == "number", "Latency should be a number")
    next()
end)

suite:Add("ConnRun", function(next, conn)
    conn:Run("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" },
        callback = function(err)
            assert(err == nil, "Run should insert without error")
            next()
        end
    })
end)

suite:Add("ConnRunSync", function(next, conn)
    local err = conn:RunSync("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" }
    })
    assert(err == nil, "RunSync should insert without error")
    next()
end)

suite:Add("ConnExecute", function(next, conn)
    conn:Execute("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" },
        callback = function(err, res)
            assert(err == nil, "Execute should insert without error")
            assert(res.last_insert_id == 1, "Last insert ID should be 1")
            assert(res.rows_affected == 1, "Rows affected should be 1")
            next()
        end
    })
end)

suite:Add("ConnExecuteSync", function(next, conn)
    local err, res = conn:ExecuteSync("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" }
    })
    assert(err == nil, "ExecuteSync should insert without error")
    assert(res.rows_affected == 1, "Rows affected should be 1")
    assert(res.last_insert_id == 1, "Last insert ID should be 1")
    next()
end)

suite:Add("ConnFetch", function(next, conn)
    conn:RunSync("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" }
    })
    conn:Fetch("SELECT * FROM test_table", {
        callback = function(err, res)
            assert(err == nil, "Fetch should succeed without error")
            assert(#res == 1, "Should return one row")
            assert(res[1].value == "test", "Value should be 'test'")
            next()
        end
    })
end)

suite:Add("ConnFetchSync", function(next, conn)
    conn:RunSync("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" }
    })
    local err, res = conn:FetchSync("SELECT * FROM test_table")
    assert(err == nil, "FetchSync should succeed without error")
    assert(#res == 1, "Should return one row")
    assert(res[1].value == "test", "Value should be 'test'")
    next()
end)

suite:Add("ConnFetchOne", function(next, conn)
    conn:RunSync("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" }
    })
    conn:FetchOne("SELECT * FROM test_table", {
        callback = function(err, res)
            assert(err == nil, "FetchOne should succeed without error")
            assert(res.value == "test", "Value should be 'test'")
            next()
        end
    })
end)

suite:Add("ConnFetchOneSync", function(next, conn)
    conn:RunSync("INSERT INTO test_table (value) VALUES ({1})", {
        params = { "test" }
    })
    local err, res = conn:FetchOneSync("SELECT * FROM test_table")
    assert(err == nil, "FetchOneSync should succeed without error")
    assert(res.value == "test", "Value should be 'test'")
    next()
end)

suite:Add("ConnTableExists", function(next, conn)
    local exists, err = conn:TableExists("test_table")
    assert(exists, "Table 'test_table' should exist")
    assert(err == nil, "No error expected")
    next()
end)

suite:Add("UpsertQuery", function(next, conn)
    conn:UpsertQuery("test_table", {
        primary_keys = { "id" },
        inserts = {
            id = 1,
            value = "test",
        },
        updates = {
            value = "test2"
        },
        callback = function(err, res)
            assert(err == nil, "UpsertQuery should succeed without error")
            assert(res.last_insert_id == 1, "Last insert ID should be 1")
            assert(res.rows_affected == 1, "Rows affected should be 1")
            next()
        end
    })
end)

suite:Add("UpsertQuerySync", function(next, conn)
    local err, res = conn:UpsertQuerySync("test_table", {
        primary_keys = { "id" },
        inserts = {
            id = 1,
            value = "test",
        },
        updates = {
            value = "test2"
        },
    })
    assert(err == nil, "UpsertQuerySync should succeed without error")
    assert(res.last_insert_id == 1, "Last insert ID should be 1")
    assert(res.rows_affected == 1, "Rows affected should be 1")
    next()
end)

suite:Add("BeginCommit", function(next, conn)
    conn:Begin(function(err, txn)
        assert(err == nil, "Begin should succeed without error")
        assert(txn:IsOpen(), "Transaction should be open")

        local res

        err, res = txn:Execute("INSERT INTO test_table (value) VALUES ('test')")
        assert(err == nil, "Run should insert without error")
        assert(res.last_insert_id == 1, "Last insert ID should be 1")
        assert(res.rows_affected == 1, "Rows affected should be 1")

        err, res = txn:FetchOne("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res.value == "test", "Value should be 'test'")

        err = txn:Commit()
        assert(err == nil, "Commit should succeed without error")
        assert(txn:IsOpen() == false, "Transaction should be closed")

        err, res = conn:FetchOneSync("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res.value == "test", "Value should be 'test'")

        next()
    end)
end)

suite:Add("BeginRollback", function(next, conn)
    conn:Begin(function(err, txn)
        assert(err == nil, "Begin should succeed without error")
        assert(txn:IsOpen(), "Transaction should be open")

        local res

        err, res = txn:Execute("INSERT INTO test_table (value) VALUES ('test')")
        assert(err == nil, "Run should insert without error")
        assert(res.last_insert_id == 1, "Last insert ID should be 1")
        assert(res.rows_affected == 1, "Rows affected should be 1")

        err, res = txn:FetchOne("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res.value == "test", "Value should be 'test'")

        err = txn:Rollback()
        assert(err == nil, "Rollback should succeed without error")
        assert(txn:IsOpen() == false, "Transaction should be closed")

        err, res = conn:FetchOneSync("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res == nil, "Value should be nil")

        next()
    end)
end)

suite:Add("BeginSyncCommit", function(next, conn)
    conn:BeginSync(function(err, txn)
        assert(err == nil, "BeginSync should succeed without error")
        assert(txn:IsOpen(), "Transaction should be open")

        local res

        err, res = txn:Execute("INSERT INTO test_table (value) VALUES ('test')")
        assert(err == nil, "Run should insert without error")
        assert(res.last_insert_id == 1, "Last insert ID should be 1")
        assert(res.rows_affected == 1, "Rows affected should be 1")

        err, res = txn:FetchOne("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res.value == "test", "Value should be 'test'")

        err = txn:Commit()
        assert(err == nil, "Commit should succeed without error")
        assert(txn:IsOpen() == false, "Transaction should be closed")

        err, res = conn:FetchOneSync("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res.value == "test", "Value should be 'test'")

        next()
    end)
end)

suite:Add("BeginSyncRollback", function(next, conn)
    conn:BeginSync(function(err, txn)
        assert(err == nil, "BeginSync should succeed without error")
        assert(txn:IsOpen(), "Transaction should be open")

        local res

        err, res = txn:Execute("INSERT INTO test_table (value) VALUES ('test')")
        assert(err == nil, "Run should insert without error")
        assert(res.last_insert_id == 1, "Last insert ID should be 1")
        assert(res.rows_affected == 1, "Rows affected should be 1")

        err, res = txn:FetchOne("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res.value == "test", "Value should be 'test'")

        err = txn:Rollback()
        assert(err == nil, "Rollback should succeed without error")
        assert(txn:IsOpen() == false, "Transaction should be closed")

        err, res = conn:FetchOneSync("SELECT * FROM test_table")
        assert(err == nil, "FetchOne should succeed without error")
        assert(res == nil, "Value should be nil")
    end)

    next()
end)

print("\n\n\n\n\n\n")

local function on_start(conn)
    assert(conn:IsConnected(), "Connection should be connected after StartSync")
    local createQuery = "CREATE TABLE IF NOT EXISTS test_table (id INTEGER PRIMARY KEY, value TEXT)"
    if conn:IsMySQL() then
        createQuery = "CREATE TABLE IF NOT EXISTS test_table (id INTEGER PRIMARY KEY AUTO_INCREMENT, value TEXT)"
    end
    local opts = { params = {} }
    local err = conn:RunSync(createQuery, opts)
    assert(not err, "Failed to create table")
end

local function after_each(conn)
    conn:RunSync("DELETE FROM test_table")
    if conn:IsMySQL() then
        -- mysql does not reset the auto increment counter after a delete
        conn:RunSync("TRUNCATE TABLE test_table")
    end
end

local function on_end(conn)
    conn:RunSync("DROP TABLE test_table")
end


local sqlite_conn = goobie_sql.NewConn({ driver = "sqlite", addon_name = "test" })
local mysql_conn = goobie_sql.NewConn({ driver = "mysql", uri = "mysql://USER:PASS@IP/DB", addon_name = "test" })

MsgC("Running: ", Color(0, 255, 0, 255), "SQLite tests", "\n")
suite:Run(on_start, after_each, on_end, sqlite_conn)

MsgC("Running: ", Color(255, 0, 0, 255), "MySQL tests", "\n")
suite:Run(on_start, after_each, on_end, mysql_conn)
