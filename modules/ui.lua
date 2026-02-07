---@class Addon
local addon = select(2, ...)
---@class UIModule
local ui = addon.module('ui')
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
