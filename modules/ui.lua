local _, addon = ...
local ui, private = addon.module('ui')
local deferredRefreshSets

function ui.init()
    deferredRefreshSets = addon.defer(0.5, ui.refreshSets)
end

function ui.attach()
    -- attach filter frames
    ui.filter.attach()

    -- handle transmog UI actions
    hooksecurefunc(WardrobeFrame, 'Show', private.onWardrobeShow)
    hooksecurefunc(WardrobeFrame, 'Hide', private.onWardrobeHide)
    hooksecurefunc(WardrobeCollectionFrame, 'SetTab', private.onWardrobeTabSwitch)

    -- handle some events
    addon.on('TRANSMOG_COLLECTION_ITEM_UPDATE', private.onTransmogCollectionItemUpdate)
end

function ui.isTransmogrifyingSets()
    return WardrobeCollectionFrame:IsVisible()
        and WardrobeCollectionFrame.selectedTab == 2
        and C_Transmog.IsAtTransmogNPC()
end

function ui.refreshSets()
    if not ui.isTransmogrifyingSets() then
        return
    end

    private.clearSetData()
    private.updateSets()
end

function private.onWardrobeShow()
    -- refresh sets after re-opening the transmog sets UI
    if ui.isTransmogrifyingSets() then
        ui.refreshSets()
    end
end

function private.onWardrobeHide()
    -- hide filter dialog when transmog UI is closed
    ui.filter.hide()
end

function private.onWardrobeTabSwitch()
    -- hide filter dialog when tabs are switched
    ui.filter.hide()

    -- refresh sets when switching to transmog sets UI
    if ui.isTransmogrifyingSets() then
        ui.refreshSets()
    end
end

function private.onTransmogCollectionItemUpdate()
    deferredRefreshSets()
end

function private.clearSetData()
    WardrobeCollectionFrame.SetsTransmogFrame:OnEvent('TRANSMOG_COLLECTION_UPDATED')
end

function private.updateSets()
    for _, model in pairs(WardrobeCollectionFrame.SetsTransmogFrame.Models) do
        model.setID = -1 -- clear model set IDs to force an update
    end

    WardrobeCollectionFrame.SetsTransmogFrame:UpdateSets()
end
