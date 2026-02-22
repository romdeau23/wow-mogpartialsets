---@class Addon
local addon = select(2, ...)

function addon.createObservable()
    ---@class Observable
    local observable = {}
    ---@type table<string, table<function, true>>
    local listeners = {}

    ---@param eventName string
    ---@param callback function
    function observable.on(eventName, callback)
        if not listeners[eventName] then
            listeners[eventName] = {}
        end

        listeners[eventName][callback] = true
    end

    ---@param eventName string
    ---@param callback function
    function observable.off(eventName, callback)
        if listeners[eventName] then
            listeners[eventName][callback] = nil

            if next(listeners[eventName]) == nil then
                listeners[eventName] = nil
            end
        end
    end

    ---@param eventName string
    ---@param ... any
    function observable.dispatch(eventName, ...)
        if not listeners[eventName] then
            return
        end

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
            listeners[eventName] = nil
        end
    end

    return observable
end
