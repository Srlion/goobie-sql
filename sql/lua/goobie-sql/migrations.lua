local fmt = string.format

local function is_ascii(s)
    return not s:match("[\128-\255]") -- Match any byte outside the ASCII range (0-127)
end

local function preprocess(text, defines)
    for k, v in pairs(defines) do
        defines[k:upper()] = v
    end

    local output = {}
    local state_stack = {}
    local active = true

    for line in text:gmatch("([^\n]*)\n?") do
        local macro = line:match("^%s*%-%-@ifdef%s+(%w+)")
        if macro then
            macro = macro:upper()
            table.insert(state_stack, active)
            active = active and (defines[macro] == true)
        elseif line:match("^%s*%-%-@else%s*$") then
            if #state_stack == 0 then
                return error("Unexpected --@else without matching --@ifdef")
            end
            local parentActive = state_stack[#state_stack]
            active = parentActive and not active
        elseif line:match("^%s*%-%-@endif%s*$") then
            if #state_stack == 0 then
                return error("Unexpected --@endif without matching --@ifdef")
            end
            active = table.remove(state_stack)
        else
            if active then
                table.insert(output, line)
            end
        end
    end

    if #state_stack > 0 then
        return error("Missing --@endif: " .. #state_stack .. " --@ifdef directives were not closed")
    end

    return table.concat(output, "\n")
end

local function RunMigrations(conn, migrations, ...)
    local addon_name = conn.options.addon_name

    assert(type(migrations) == "table", "migrations must be an array sorted by version")
    assert(type(addon_name) == "string", "addon_name must be supplied to connection options")
    assert(addon_name ~= "", "addon_name cannot be empty")
    assert(is_ascii(addon_name), "addon_name must be ascii only")

    local TABLE_NAME = fmt("goobie_sql_migrations_version_%s", addon_name)

    local current_version = 0

    do
        local err = conn:RunSync(fmt([[
            CREATE TABLE IF NOT EXISTS %s (
                `id` TINYINT PRIMARY KEY,
                `version` MEDIUMINT UNSIGNED NOT NULL
            )
        ]], TABLE_NAME))
        if err then
            return error(fmt("Failed to create migrations table: %s", err))
        end
    end

    local first_run = false
    do
        local err, res = conn:FetchOneSync(fmt([[
            SELECT `version` FROM %s
        ]], TABLE_NAME))
        if err then
            return error(fmt("Failed to fetch migrations version: %s", err))
        end
        -- if nothing was returned, then the table didn't exist
        if res then
            local version = tonumber(res.version)
            if type(version) == "number" then
                current_version = version
            else
                return error(fmt("Migrations table is corrupted, version is not a number"))
            end
        else
            first_run = true
        end
    end

    -- make sure that migrations has UP, DOWN and version
    for _, migration in ipairs(migrations) do
        assert(type(migration) == "table", "migrations must be an array of tables")
        assert(type(migration.UP) == "function" or type(migration.UP) == "string",
            "migration `UP` must be a function or string")
        assert(type(migration.DOWN) == "function" or type(migration.DOWN) == "string",
            "migration `DOWN` must be a function or string")
    end

    local function process(query)
        local defines = {}
        if conn:IsMySQL() then
            defines["mysql"] = true
        else
            defines["sqlite"] = true
        end
        query = preprocess(query, defines)
        local err = conn:RunSync(query, { raw = true })
        if err then
            return error(tostring(err))
        end
    end

    local applied_migrations = {}
    local function revert_migrations(...)
        for idx, migration in ipairs(applied_migrations) do
            local success
            if type(migration.DOWN) == "function" then
                success = ProtectedCall(migration.DOWN, process, conn, ...)
            else
                success = ProtectedCall(process, migration.DOWN)
            end
            if not success then
                return error("failed to revert #" .. idx .. " migration")
            end
        end
    end

    for idx, migration in ipairs(migrations) do
        if idx <= current_version then
            goto _continue_
        end

        local success
        if type(migration.UP) == "function" then
            success = ProtectedCall(migration.UP, process, conn, ...)
        else
            success = ProtectedCall(process, migration.UP)
        end
        if not success then
            revert_migrations(...)
            return error("failed to apply migration: " .. idx)
        end

        applied_migrations[idx] = migration
        current_version = idx
        ::_continue_::
    end

    conn:RunSync(fmt([[
        REPLACE INTO %s (`id`, `version`) VALUES (1, %d);
    ]], TABLE_NAME, current_version))

    return current_version, first_run
end

return RunMigrations
