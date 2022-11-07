local _, addon = ...

function addon.tryFinally(try, finally, ...)
    local status, err = pcall(try, ...)

    finally()

    if not status then
        error(err)
    end
end
