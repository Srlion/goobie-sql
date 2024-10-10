TEST_DRIVER_NAME = "mysql"
local utils = include("goobie-sql/tests/utils.lua")
local conn = utils:Connect()

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

-- you were testing with, return it in readme file and keep typing

return {
    groupName = ("goobie_sql (%s): Init"):format(utils.options.driver),
    beforeAll = function()
        utils:CreateTable()
    end,
    afterAll = function()
        utils:DropTable()
    end,

    cases = {
        {
            name = "goobie_sql.Connect",
            func = function()
                expect(conn).to.beA("table")
            end
        },
        {
            name = "IsConnected",
            func = function()
                expect(conn:IsConnected()).to.beTrue()
            end
        },
        {
            name = "IsConnecting",
            func = function()
                expect(conn:IsConnecting()).to.beFalse()
            end
        },
        {
            name = "PreQuery",
            func = function()
                local query, params

                query, params = conn:PreQuery("test", {})
                expect(query).to.beA("string")
                expect(params).to.beA("table")

                query, params = conn:PreQuery("{test}-{ test }-{ test}-{test }{ 3 }", {
                    params = {test = 1, [3] = true}
                })
                if conn:IsMySQL() then
                    expect(query).to.equal("?-?-?-??")
                    expect(params[1]).to.equal(1)
                    expect(params[2]).to.equal(1)
                    expect(params[3]).to.equal(1)
                    expect(params[4]).to.equal(1)
                    expect(params[5]).to.equal(true)
                else
                    expect(query).to.equal("1-1-1-1TRUE")
                    expect(params[1]).to.equal(1)
                    expect(params[2]).to.equal(1)
                    expect(params[3]).to.equal(1)
                    expect(params[4]).to.equal(1)
                    expect(params[5]).to.equal(true)
                end
            end
        },
        {
            name = "Ping",
            func = function()
                local success, err = conn:Ping()
                expect(success).to.beTrue()
                expect(err).to.beNil()
            end
        },
        {
            name = "TableExists",
            func = function()
                local exists, err

                exists, err = conn:TableExists(utils.tableName)
                expect(err).to.beNil()
                expect(exists).to.beTrue()

                exists, err = conn:TableExists("goobie_sql_test_blah")
                expect(exists).to.beFalse()
                expect(err).to.beNil()
            end
        },
        {
            name = "DisconnectSync",
            func = function()
                local err = conn:DisconnectSync()
                expect(err).to.beNil()
                expect(conn:IsConnected()).to.beFalse()
            end
        }
    }
}
