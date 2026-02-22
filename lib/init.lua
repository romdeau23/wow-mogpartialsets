---@class Addon
local addon = select(2, ...)
local addonName = select(1, ...)
local loaded = false
---@type fun()[]
local initializers = {}

---@param initializer fun()
function addon.registerInitializer(initializer)
    assert(not loaded)
    table.insert(initializers, initializer)
end

addon.on('ADDON_LOADED', function (name)
    if name == addonName then
        loaded = true

        for _, initializer in ipairs(initializers) do
            local success, result = pcall(initializer)

            if not success then
                CallErrorHandler(result)
            end
        end

        return false
    end
end)
