local common = include("goobie-sql/common.lua")
local RunMigrations = include("goobie-sql/migrations.lua")

local goobie_sql = {
    NULL = common.NULL,
    STATES = common.STATES,

    VERSION = common.VERSION,
    MAJOR_VERSION = common.MAJOR_VERSION,
}

local goobie_sqlite
local goobie_mysql

function goobie_sql.NewConn(opts, on_connected)
    if type(opts) ~= "table" then
        return error("opts must be a table")
    end

    local conn
    if opts.driver == "mysql" then
        if goobie_mysql == nil then
            goobie_mysql = include("goobie-sql/mysql/main.lua")
            if not goobie_mysql then
                return error("failed to load mysql binary module")
            end
        end
        conn = goobie_mysql.NewConn(opts)
    elseif opts.driver == "sqlite" then
        if goobie_sqlite == nil then
            goobie_sqlite = include("goobie-sql/sqlite/main.lua")
        end
        conn = goobie_sqlite.NewConn(opts)
    else
        return error("invalid driver '%s'", opts.driver)
    end

    conn.options = opts
    conn.on_error = opts.on_error

    if on_connected then
        conn:Start(on_connected)
    else
        conn:StartSync()
    end

    conn.RunMigrations = RunMigrations

    return conn
end

return goobie_sql
