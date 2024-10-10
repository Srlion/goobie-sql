local utils = include("goobie-sql/tests/utils.lua")

return {
    groupName = ("goobie_sql (%s): Fetch"):format(utils.options.driver),
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
            name = "FetchSuccessSync",
            func = function(state)
                local row1Values = state.utils:GetTestValues()
                state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    sync = true,
                    params = row1Values
                })

                state.conn:Execute("INSERT INTO " .. state.tableName .. " (string, number, bool, nill) VALUES ({string}, {number}, {bool}, {nill})", {
                    sync = true,
                    params = state.utils:GetTestValues(overrides)
                })

                local err, res = state.conn:Fetch("SELECT * FROM " .. state.tableName, {
                    sync = true,
                })

                expect(err).to.beNil()

                expect(res).to.beA("table")
                expect(#res).to.equal(2)

                local row = res[1]
                expect(row).to.beA("table")
                expect(tonumber(row.id)).to.beA("number")
                expect(row.string).to.equal(row1Values.string)
                expect(tonumber(row.number)).to.equal(row1Values.number)
                expect(tobool(row.bool)).to.equal(row1Values.bool)
                expect(state.utils:TestNull(row.nill)).to.beTrue()
            end
        },
        {
            name = "FetchSuccessAsync",
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

                local data = false
                local is_error = false
                state.conn:Fetch("SELECT * FROM " .. state.tableName, {
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
                expect(#data).to.equal(2)

                local row = data[1]
                expect(row).to.beA("table")
                expect(tonumber(row.id)).to.beA("number")
                expect(row.string).to.equal(row1Values.string)
                expect(tonumber(row.number)).to.equal(row1Values.number)
                expect(tobool(row.bool)).to.equal(row1Values.bool)
                expect(state.utils:TestNull(row.nill)).to.beTrue()
            end
        },
        {
            name = "FetchErrorSync",
            func = function(state)
                local err, res = state.conn:Fetch("SELECT *", {
                    sync = true
                })

                expect(res).to.beNil()
                expect(state.utils:TestError(err)).to.beTrue()
            end
        },
        {
            name = "FetchErrorAsync",
            func = function(state)
                local err = false
                local is_success = false
                state.conn:Fetch("SELECT *", {
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

