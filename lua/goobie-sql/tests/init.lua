local utils = include("goobie-sql/tests/utils.lua")
local conn = utils:Connect()

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
