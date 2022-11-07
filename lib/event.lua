local _, addon = ...
local frame = CreateFrame('Frame')
local listenerMap = {}

function addon.on(eventName, callback)
    if not listenerMap[eventName] then
        frame:RegisterEvent(eventName)
        listenerMap[eventName] = {}
    end

    table.insert(listenerMap[eventName], callback)
end

function addon.off(eventName, callback)
    if listenerMap[eventName] then
        for i, listener in ipairs(listenerMap[eventName]) do
            if callback == listener then
                table.remove(listenerMap[eventName], i)

                if #listenerMap[eventName] == 0 then
                    frame:UnregisterEvent(eventName)
                    listenerMap[eventName] = nil
                end

                return true
            end
        end
    end

    return false
end

frame:SetScript('onEvent', function (_, eventName, ...)
    local toClear

    for _, listener in ipairs(listenerMap[eventName]) do
        if listener(...) == false then
            if not toClear then
                toClear = {}
            end

            table.insert(toClear, listener)
        end
    end

    if toClear then
        for _, listener in ipairs(toClear) do
            addon.off(eventName, listener)
        end
    end
end)
