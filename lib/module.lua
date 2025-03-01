local addonName, addon = ...
local modules = {}

function addon.module(...)
    local module = addon.namespace(...)
    table.insert(modules, module)

    return module, {}
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
