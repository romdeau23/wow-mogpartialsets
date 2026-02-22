---@class Addon
local addon = select(2, ...)
local ui = addon.module()
addon.ui = ui

local hooked = false

function ui.hook()
    if hooked then
        return
    end

    local setsFrame = TransmogFrame.WardrobeCollection.TabContent.SetsFrame

    addon.ui.filter.hook(setsFrame)
    addon.ui.setsTab.hook(setsFrame)

    hooked = true
end
