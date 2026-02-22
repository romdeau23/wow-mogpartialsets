---@class Addon
local addon, gameEvent = select(2, ...), {}
addon.gameEvent = gameEvent

local frame = CreateFrame('Frame')
---@type table<string, table<function, true>>
local listeners = {}

---@param eventName string
---@param callback function
function gameEvent.on(eventName, callback)
    if not listeners[eventName] then
        frame:RegisterEvent(eventName)
        listeners[eventName] = {}
    end

    listeners[eventName][callback] = true
end

---@param eventName string
---@param callback function
function gameEvent.off(eventName, callback)
    if listeners[eventName] then
        listeners[eventName][callback] = nil

        if next(listeners[eventName]) == nil then
            frame:UnregisterEvent(eventName)
            listeners[eventName] = nil
        end
    end
end

frame:SetScript('OnEvent', function (_, eventName, ...)
    local selfRemoved = false

    for listener in pairs(listeners[eventName]) do
        local success, result = pcall(listener, ...)

        if success then
            if result == false then
                listeners[eventName][listener] = nil
                selfRemoved = true
            end
        else
            CallErrorHandler(result)
        end
    end

    if selfRemoved and next(listeners[eventName]) == nil then
        frame:UnregisterEvent(eventName)
        listeners[eventName] = nil
    end
end)

-- convenience shortcut
addon.on = gameEvent.on
