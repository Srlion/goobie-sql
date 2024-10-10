local utils = include("goobie-sql/tests/utils.lua")

return {
    groupName = ("goobie_sql (%s): Execute"):format(utils.options.driver),
    beforeEach = function(state)
        state.utils = utils
        state.tableName = utils.tableName
        state.conn = utils:Connect()

        utils:CreateTable()
    end,
    afterEach = function(state)
        state.utils:DropTable()
    end,

    cases = {
        {
            name = "ExecuteSuccessSync",
            func = function(state)
                local err, res = state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    sync = true,
                    params = state.utils:GetTestValues()
                })

                expect(err).to.beNil()
                expect(res).to.beA("table")
                expect(res.last_insert_id).to.beA("number")
                expect(res.rows_affected).to.beA("number")
            end
        },
        {
            name = "ExecuteSuccessAsync",
            func = function(state)

                local data = false
                local is_error = false
                state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    params = state.utils:GetTestValues(),
                    callback = function(err, new_data)
                        data = true

                        if err then
                            is_error = true
                            return
                        end

                        data = new_data
                    end
                })

                while not data do
                    state.conn:Poll()
                end

                expect(is_error).to.beFalse()

                expect(data).to.beA("table")
                expect(data.last_insert_id).to.beA("number")
                expect(data.rows_affected).to.equal(1)
            end
        },
        {
            name = "ExecuteErrorSync",
            func = function(state)
                local err, res = state.conn:Execute("INSERT s", {
                    sync = true
                })

                expect(res).to.beNil()
                expect(state.utils:TestError(err)).to.beTrue()
            end
        },
        {
            name = "ExecuteErrorAsync",
            func = function(state)
                local err = false
                local is_success = false
                state.conn:Execute("INSERT s", {
                    callback = function(new_err, data)
                        err = true

                        if data then
                            is_success = true
                            return
                        end

                        err = new_err
                    end
                })

                while not err do
                    state.conn:Poll()
                end

                expect(is_success).to.beFalse()
                expect(state.utils:TestError(err)).to.beTrue()
            end
        },
    }
}
