-- TOTALLY WRITTEN BY ME AND NOT BY @PHATSO https://github.com/brandonsturgeon
local TEST_DRIVER_NAME = TEST_DRIVER_NAME
local goobie_sql = include("goobie-sql/sh_init.lua")

local function getTableName()
    return "goobie_sql_test" .. string.Replace(tostring(math.Round(SysTime(), 5)), ".", "")
end

local TestUtils = {
    options = {
        driver = TEST_DRIVER_NAME,
        uri = "mysql://root:1234@localhost/YES",
    },
    tableName = getTableName(),
    testValueIter = 0,
    goobie_sql = goobie_sql
}

function TestUtils:Connect()
    self.conn = goobie_sql.Connect(self.options)
    return self.conn
end

function TestUtils:CreateTable()
    self:DropTable()
    self.conn:Execute([[
        CREATE TABLE IF NOT EXISTS ]] .. self.tableName .. [[ (
            id {CROSS_PRIMARY_AUTO_INCREMENTED},
            unique_id INTEGER,
            unique_id2 INTEGER,
            string TEXT,
            number INTEGER,
            bool BOOLEAN,
            nill TEXT,
            bloby BLOB,
            UNIQUE (unique_id, unique_id2)
        )
    ]], {sync = true})
end

function TestUtils:DropTable()
    self.conn:Execute("DROP TABLE IF EXISTS " .. self.tableName, {sync = true})
end

function TestUtils:TestError(err)
    if self.conn:IsMySQL() then
        return istable(err) and (isstring(err.message) and err.message ~= "") and isnumber(err.code)
    else
        return istable(err) and (isstring(err.message) and err.message ~= "")
    end
end

function TestUtils:TestNull(value)
    if self.conn:IsMySQL() then
        return value == nil
    else
        return value == "NULL"
    end
end

function TestUtils:GetTestValues(overrides)
    local iter = self.testValueIter + 1
    self.testValueIter = iter

    local values = {
        string = "hello佐藤太郎محمد" .. iter,
        number = iter,
        bool = true,
        nill = goobie_sql.NULL
    }

    if overrides then
        for k, v in pairs(overrides) do
            values[k] = v
        end
    end

    return values
end

return TestUtils
