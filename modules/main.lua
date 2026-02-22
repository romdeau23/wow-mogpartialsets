---@class Addon
local addon = select(2, ...)
local main, private = addon.module(), {}

function main.init()
    addon.on('TRANSMOGRIFY_OPEN', private.onTransmogrifyOpen)
end

function private.onTransmogrifyOpen()
    -- hook the transmog UI
    if C_AddOns.IsAddOnLoaded('Blizzard_Transmog') then
        private.hookComponents()
    else
        addon.on('ADDON_LOADED', function (loadedAddonName)
            if loadedAddonName == 'Blizzard_Transmog' then
                private.hookComponents()

                return false
            end
        end)
    end

    return false
end

function private.hookComponents()
    addon.setLoader.hook()
    addon.ui.hook()
end
