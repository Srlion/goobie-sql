local string_format = string.format
local string_gsub = string.gsub
local string_char = string.char
local string_byte = string.byte
local table_insert = table.insert
local type = type

local common = {
    VERSION = "FULL_VERSION_PLACEHOLDER",
    NULL = NULL
}
common.MAJOR_VERSION = tonumber(common.VERSION:match("(%d+)%.%d+"))

local STATES = {
    CONNECTED = 0,
    CONNECTING = 1,
    NOT_CONNECTED = 2,
    DISCONNECTED = 3,
}
common.STATES = STATES

local STATES_NAMES = {}; do
    for k, v in pairs(STATES) do
        STATES_NAMES[v] = k
    end
end
common.STATES_NAMES = STATES_NAMES

do
    local hex = function(c)
        return string_format("%02X", string_byte(c))
    end
    function common.StringToHex(text)
        return (string_gsub(text, ".", hex))
    end

    local unhex = function(cc)
        return string_char(tonumber(cc, 16))
    end
    function common.StringFromHex(text)
        return (string_gsub(text, "..", unhex))
    end
end

local SetPrivate, GetPrivate; do
    local PRIVATE_KEY = "___PRIVATE___ANNOYING_KEY_TO_STOP_PLAYING_WITH___"

    function SetPrivate(conn, key, value)
        local private = conn[PRIVATE_KEY]
        if not private then
            private = {}
            conn[PRIVATE_KEY] = private
        end
        private[key] = value
    end

    ---@return any
    function GetPrivate(conn, key)
        local private = conn[PRIVATE_KEY]
        if not private then return nil end
        return private[key]
    end
end
common.SetPrivate, common.GetPrivate = SetPrivate, GetPrivate

local ERROR_META = {
    __tostring = function(s)
        return string.format("(%s) %s", s.code or "?", s.message or "unknown error")
    end
}
common.ERROR_META = ERROR_META

common.SQLError = function(msg)
    return setmetatable({
        message = msg,
    }, ERROR_META)
end

common.CROSS_SYNTAXES = include("goobie-sql/cross_syntaxes.lua")

local EMPTY_PARAMS = {}
local EMPTY_OPS = {
    params = EMPTY_PARAMS,
}

---@param query string|nil
---@param opts table|nil
---@return table
common.CheckQuery = function(query, opts)
    if type(query) ~= "string" then
        error("query must be a string", 4)
    end

    if opts == nil then
        return EMPTY_OPS
    end

    if type(opts) ~= "table" then
        error("opts must be a table", 4)
    end

    local params = opts.params
    if params == nil then
        opts.params = EMPTY_PARAMS
    elseif type(params) ~= "table" then
        error("params must be a table", 4)
    end

    local callback = opts.callback
    if callback ~= nil and type(callback) ~= "function" then
        error("callback must be a function", 4)
    end

    return opts
end

local COMMON_META = {}

function COMMON_META:StateName() return STATES_NAMES[self:State()] end

function COMMON_META:IsConnected() return self:State() == STATES.CONNECTED end

function COMMON_META:IsConnecting() return self:State() == STATES.CONNECTING end

function COMMON_META:IsDisconnected() return self:State() == STATES.DISCONNECTED end

function COMMON_META:IsNotConnected() return self:State() == STATES.NOT_CONNECTED end

common.COMMON_META = COMMON_META

local function errorf(err, ...)
    return error(string_format(err, ...))
end
common.errorf = errorf

local function errorlevelf(level, err, ...)
    return error(string_format(err, ...))
end
common.errorlevelf = errorlevelf

common.HandleNoEscape = function(v)
    local v_type = type(v)
    if v_type == "string" then
        return "'" .. v .. "'"
    elseif v_type == "number" then
        return v
    elseif v_type == "boolean" then
        return v and "TRUE" or "FALSE"
    else
        return errorf("invalid type '%s' was passed to escape '%s'", v_type, v)
    end
end

local PARAMS_PATTERN = "{[%s]*(%d+)[%s]*}"

local HandleQueryParams; do
    local ESCAPE_TYPES = {
        ["string"] = true,
        ["number"] = true,
        ["boolean"] = true,
    }
    local function escape_function(value)
        if ESCAPE_TYPES[type(value)] then
            return "?"
        else
            return errorf("invalid type '%s' was passed to escape '%s'", type(value), value)
        end
    end

    local fquery_params, fquery_new_params
    local has_matches = false
    local gsub_f = function(key)
        local raw_value = fquery_params[tonumber(key)]
        if raw_value == nil then
            return errorf("missing parameter for query: %s", key)
        end

        has_matches = true

        if raw_value == common.NULL then
            return "NULL"
        end


        table_insert(fquery_new_params, raw_value)

        return (escape_function(raw_value))
    end

    local EMPTY_QUERY_PARAMS = {}
    ---@return string
    ---@return table
    function HandleQueryParams(query, params)
        fquery_new_params = {}
        fquery_params = params
        has_matches = false

        -- We don't return the query immediately as that could cause hidden bugs. We must ensure that if the developer is using
        -- placeholders, they are checked for missing parameters.
        if fquery_params == nil then
            fquery_params = EMPTY_QUERY_PARAMS
        elseif type(fquery_params) ~= "table" then
            errorlevelf(4, "params must be a table, got %s", type(fquery_params))
        end

        local new_query = (string_gsub(query, PARAMS_PATTERN, gsub_f))

        -- if nothing matched, just return params as s
        if not has_matches then
            return query, params
        end

        return new_query, fquery_new_params
    end
end
common.HandleQueryParams = HandleQueryParams

return common
