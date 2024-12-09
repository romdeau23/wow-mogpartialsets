local _, addon = ...

function addon.isAddonEnabled(name)
    return select(4, C_AddOns.GetAddOnInfo(name)) == true
end
