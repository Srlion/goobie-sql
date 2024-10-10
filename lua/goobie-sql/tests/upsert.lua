local utils = include("goobie-sql/tests/utils.lua")
local goobie_sql = utils.goobie_sql

local conn = utils:Connect()

local raw_binary = goobie_sql.StringFromHex("0913F700055ACC0F820A")

return {
    groupName = ("goobie_sql (%s): Upsert"):format(utils.options.driver),
    beforeEach = function(state)
        state.utils = utils
        state.tableName = utils.tableName

        utils:CreateTable()
    end,
    afterEach = function(state)
        state.utils:DropTable()
    end,

    cases = {
        {
            name = "UpsertInsert",
            func = function(state)
                local err, res = conn:UpsertQuery(state.tableName, {
                    primary_keys = {"unique_id", "unique_id2"},
                    inserts = {
                        unique_id = 1,
                        unique_id2 = 2,
                        string = "test",
                        number = 1,
                        bool = true,
                        bloby = "blob",
                    },
                    updates = {
                        "string",
                        "number",
                        "bool",
                        "bloby",
                    },
                    binary_columns = {"bloby"},
                    sync = true,
                })

                expect(err).to.beNil()
                expect(res).to.beA("table")
                expect(res.last_insert_id).to.beA("number")
                expect(res.rows_affected).to.beA("number")
            end
        },
        {
            name = "UpsertUpdate",
            func = function(state)
                conn:UpsertQuery(state.tableName, {
                    primary_keys = {"unique_id", "unique_id2"},
                    inserts = {
                        unique_id = 1,
                        unique_id2 = 2,
                        string = "test",
                        number = 1,
                        bool = true,
                        bloby = raw_binary,
                    },
                    updates = {
                        "string",
                        "number",
                        "bool",
                        "bloby",
                    },
                    binary_columns = {"bloby"},
                    sync = true,
                })

                local err, data = conn:FetchOne("SELECT hex(bloby) as blobyss, t.* FROM " .. state.tableName .. " t", {
                    sync = true,
                })

                expect(err).to.beNil()
                expect(data).to.beA("table")
                expect(data.string).to.equal("test")
                expect(tonumber(data.number)).to.equal(1)
                expect(tobool(data.bool)).to.equal(true)
                if conn:IsSQLite() then
                    expect(data.blobyss).to.equal(goobie_sql.StringToHex(raw_binary))
                else
                    expect(data.bloby).to.equal(raw_binary)
                end

                conn:UpsertQuery(state.tableName, {
                    primary_keys = {"unique_id", "unique_id2"},
                    inserts = {
                        unique_id = 1,
                        unique_id2 = 2,
                        string = "new_test",
                        number = 2,
                        bool = false,
                        bloby = "new_blob",
                    },
                    updates = {
                        "string",
                        "number",
                        "bool",
                        "bloby",
                    },
                    binary_columns = {"bloby"},
                    sync = true,
                })

                err, data = conn:FetchOne("SELECT * FROM " .. state.tableName, {
                    sync = true,
                })

                expect(err).to.beNil()
                expect(data).to.beA("table")
                expect(data.string).to.equal("new_test")
                expect(tonumber(data.number)).to.equal(2)
                expect(tobool(data.bool)).to.equal(false)
                expect(data.bloby).to.equal("new_blob")
            end
        },
    }
}
