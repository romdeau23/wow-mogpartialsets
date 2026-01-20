local _, addon = ...
local ui = addon.module('ui'), {}
local hooked = false

function ui.hook()
    if hooked then
        return
    end

    local setsFrame = TransmogFrame.WardrobeCollection.TabContent.SetsFrame

    addon.ui.filter.hook(setsFrame)
    addon.ui.sets.hook(setsFrame)

    hooked = true

    addon.ui.sets.refresh()
end
