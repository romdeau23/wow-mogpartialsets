---@class Addon
local addon = select(2, ...)
---@class EventBusLib
local event = addon.namespace('event')
local listenerMap = {}

---@param eventName string
---@param callback function
function event.on(eventName, callback)
    if not listenerMap[eventName] then
        listenerMap[eventName] = {}
    end

    table.insert(listenerMap[eventName], callback)
end

---@param eventName string
---@param ... any
function event.dispatch(eventName, ...)
    if not listenerMap[eventName] then
        return
    end

    for _, listener in ipairs(listenerMap[eventName]) do
        listener(...)
    end
end
