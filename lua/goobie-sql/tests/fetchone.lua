local utils = include("goobie-sql/tests/utils.lua")

return {
    groupName = ("goobie_sql (%s): FetchOne"):format(utils.options.driver),
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
            name = "FetchOneSuccessSync",
            func = function(state)
                local row1Values = state.utils:GetTestValues()
                state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    sync = true,
                    params = row1Values
                })

                state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    sync = true,
                    params = state.utils:GetTestValues()
                })

                local err, res = state.conn:FetchOne("SELECT * FROM " .. state.tableName, {
                    sync = true,
                })

                expect(err).to.beNil()

                expect(res).to.beA("table")
                expect(#res).to.equal(0)

                expect(tonumber(res.id)).to.beA("number")
                expect(res.string).to.equal(row1Values.string)
                expect(tonumber(res.number)).to.equal(row1Values.number)
                expect(tobool(res.bool)).to.equal(row1Values.bool)
                expect(state.utils:TestNull(res.nill)).to.beTrue()
            end
        },
        {
            name = "FetchOneSuccessAsync",
            func = function(state)
                local row1Values = state.utils:GetTestValues()
                state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    sync = true,
                    params = row1Values
                })

                state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    sync = true,
                    params = state.utils:GetTestValues()
                })

                local failed = stub()

                local data = false
                local done = false
                state.conn:FetchOne("SELECT * FROM " .. state.tableName, {
                    callback = function(err, new_data)
                        if err then
                            done = true
                            failed()
                            return
                        end

                        done = true
                        data = new_data
                    end
                })

                while not done do
                    state.conn:Poll()
                end

                expect(failed).wasNot.called()

                expect(data).to.beA("table")
                expect(#data).to.equal(0)

                expect(tonumber(data.id)).to.beA("number")
                expect(data.string).to.equal(row1Values.string)
                expect(tonumber(data.number)).to.equal(row1Values.number)
                expect(tobool(data.bool)).to.equal(row1Values.bool)
                expect(state.utils:TestNull(data.nill)).to.beTrue()
            end
        },
        {
            name = "FetchOneErrorSync",
            func = function(state)
                local err, res = state.conn:FetchOne("SELECT *", {
                    sync = true
                })

                expect(res).to.beNil()
                expect(state.utils:TestError(err)).to.beTrue()
            end
        },
        {
            name = "FetchOneErrorAsync",
            func = function(state)
                local success = stub()

                local err = false
                local done = false
                state.conn:FetchOne("SELECT *", {
                    callback = function(new_err, data)
                        if new_err then
                            done = true
                            err = new_err
                            return
                        end

                        done = true
                        success()
                    end
                })

                while not done do
                    state.conn:Poll()
                end

                expect(success).wasNot.called()
                expect(state.utils:TestError(err)).to.beTrue()
            end
        },
    }
}
