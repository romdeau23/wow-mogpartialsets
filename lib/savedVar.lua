---@class Addon
local addon = select(2, ...)

---@class SavedVarLib.Var
---@field version integer
---@field data table

---@generic TData
---@param name string
---@param version integer
---@param defaults TData
---@param migrations table<integer, fun(data: table)>
---@return TData
function addon.loadSavedVar(name, version, defaults, migrations)
    ---@type SavedVarLib.Var
    local var

    ---@return boolean
    local function ensureUpToDate()
        if var.version == version then
            -- up to date
            return true
        end

        if type(version) ~= 'number' then
            -- invalid version
            return false
        end

        if var.data == nil then
            -- old structure, convert to new one before migration
            local currentVersion = var.version
            local data = {}

            for k, v in pairs(var) do
                if k ~= 'version' then
                    data[k] = v
                end
            end

            table.wipe(var)
            var.version = currentVersion
            var.data = data
        end

        if var.version < version then
            -- old version
            for to = var.version + 1, version do
                if migrations[to] then
                    migrations[to](var.data)
                end
            end

            var.version = version

            return true
        end

        -- newer version - addon downgraded?
        return false
    end

    -- init saved variable
    if type(_G[name]) == 'table' then
        var = _G[name]

        local success, result = pcall(ensureUpToDate)

        if not success or not result then
            -- reset var on crash or failure
            table.wipe(var)
            var.version = version
            var.data = CopyTable(defaults)
        end

        if not success then
            CallErrorHandler(result)
        end
    else
        var = {
            version = version,
            data = CopyTable(defaults)
        }

        _G[name] = var
    end

    return var.data
end
