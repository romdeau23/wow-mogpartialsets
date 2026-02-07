---@class Addon
local addon = select(2, ...)

---@generic T : function
---@param delay number seconds
---@param callback T
---@return T
function addon.debounce(delay, callback)
    local timer

    return function (...)
        local args = {...}
        local argCount = select('#', ...)

        -- re-schedule timer
        if timer then
            timer:Cancel()
        end

        timer = C_Timer.NewTimer(delay, function ()
            timer = nil
            callback(unpack(args, 1, argCount))
        end)
    end
end
