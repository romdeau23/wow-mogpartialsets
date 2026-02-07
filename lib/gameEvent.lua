---@class Addon
local addon = select(2, ...)
local frame = CreateFrame('Frame')
local listenerMap = {}

---@param eventName string
---@param callback function
function addon.on(eventName, callback)
    if not listenerMap[eventName] then
        frame:RegisterEvent(eventName)
        listenerMap[eventName] = {}
    end

    table.insert(listenerMap[eventName], callback)
end

---@param eventName string
---@param callback function
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

frame:SetScript('OnEvent', function (_, eventName, ...)
    local toClear

    for index, listener in ipairs(listenerMap[eventName]) do
        if listener(...) == false then
            if not toClear then
                toClear = {}
            end

            table.insert(toClear, index)
        end
    end

    if toClear then
        for i = #toClear, 1, -1 do
            table.remove(listenerMap[eventName], toClear[i])
        end

        if #listenerMap[eventName] == 0 then
            frame:UnregisterEvent(eventName)
            listenerMap[eventName] = nil
        end
    end
end)
