---@class Addon
local addon = select(2, ...)
local addonName = select(1, ...)
local modules = {}

---@param ... string
---@return table
function addon.module(...)
    local module = addon.namespace(...)
    table.insert(modules, module)

    return module
end

addon.on('ADDON_LOADED', function (name)
    if name == addonName then
        for _, module in ipairs(modules) do
            if module.init then
                module.init()
            end
        end

        return false
    end
end)
