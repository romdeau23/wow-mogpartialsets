---@class Addon
local addon = select(2, ...)
---@type Module[]
local modules = {}

---@return table
function addon.module()
    ---@class Module
    ---@field init fun()?
    local module = {}

    table.insert(modules, module)

    return module
end

addon.registerInitializer(function ()
    for _, module in ipairs(modules) do
        if module.init then
            module.init()
        end
    end
end)
