local _, addon = ...

function addon.namespace(...)
    local namespace = addon

    for _, key in ipairs({...}) do
        if namespace[key] == nil then
            namespace[key] = {}
        end

        namespace = namespace[key]
    end

    return namespace
end
