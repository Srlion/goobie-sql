local utils = include("goobie-sql/tests/utils.lua")
local conn = utils:Connect()

return {
    groupName = ("goobie_sql (%s): Transaction"):format(utils.options.driver),
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
            name = "Begin",
            func = function(state)
                local success = false
                conn:BeginSync(function(err, txn)
                    expect(err).to.beNil()
                    expect(txn).to.beA("table")
                    expect(txn.Commit).to.beA("function")
                    expect(txn.Rollback).to.beA("function")
                    success = true
                    txn:Rollback()
                end)
                expect(success).to.beTrue()
            end
        },
        {
            name = "Commit",
            func = function(state)
                local success = false
                conn:BeginSync(function(err, txn)
                    txn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                        params = state.utils:GetTestValues()
                    })

                    txn:Commit()
                    success = true
                end)

                expect(success).to.beTrue()

                local err, res = conn:FetchOne("SELECT * FROM " .. state.tableName, {
                    sync = true,
                })

                expect(err).to.beNil()
                expect(res).to.beA("table")
            end
        },
        {
            name = "Rollback",
            func = function(state)
                local success = false
                conn:BeginSync(function(err, txn)
                    txn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                        params = state.utils:GetTestValues()
                    })

                    txn:Rollback()
                    success = true
                end)

                expect(success).to.beTrue()

                local err, res = conn:FetchOne("SELECT * FROM " .. state.tableName, {
                    sync = true,
                })

                expect(err).to.beNil()
                expect(res).to.beNil()
            end
        },
        {
            name = "RollbackOnRuntimeError",
            func = function(state)
                pcall(function()
                    conn:BeginSync(function(err, txn)
                        txn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                            params = state.utils:GetTestValues()
                        })

                        error("Should Rollback - IGNORE THIS ERROR")
                        txn:Commit()
                    end)
                end)

                local err, res = conn:FetchOne("SELECT * FROM " .. state.tableName, {
                    sync = true,
                })

                expect(err).to.beNil()
                expect(res).to.beNil()
            end
        },

    }
}
