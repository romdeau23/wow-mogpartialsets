local addonName, addon = ...
local main, private = addon.module('main'), {}
local conflictingAddons = {'ExtendedSets', 'BetterWardrobe'}

function main.init()
    addon.on('TRANSMOGRIFY_OPEN', private.onTransmogrifyOpen)
end

function private.onTransmogrifyOpen()
    -- check conflicting addons
    for _, conflictingAddonName in ipairs(conflictingAddons) do
        if C_AddOns.IsAddOnLoaded(conflictingAddonName) then
            print(string.format(
                '|cffff0000[ERROR] %s cannot be used together with %s|r',
                addonName,
                conflictingAddonName
            ))

            return false
        end
    end

    -- hook the transmog UI
    if C_AddOns.IsAddOnLoaded('Blizzard_Transmog') then
        addon.ui.hook()
    else
        addon.on('ADDON_LOADED', function (loadedAddonName)
            if loadedAddonName == 'Blizzard_Transmog' then
                addon.ui.hook()

                return false
            end
        end)
    end

    return false
end
