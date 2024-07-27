local _, addon = ...

function addon.defer(delay, callback)
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
