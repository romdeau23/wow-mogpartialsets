local _, addon = ...
local ui, private = addon.module('ui')
local updateTimer
local pendingModelUpdate = false

function ui.attach()
    -- attach filter frames
    ui.filter.attach()

    -- handle transmog UI actions
    hooksecurefunc(WardrobeFrame, 'Show', private.onWardrobeShow)
    hooksecurefunc(WardrobeFrame, 'Hide', private.onWardrobeHide)
    hooksecurefunc(WardrobeCollectionFrame, 'SetTab', private.onWardrobeTabSwitch)

    -- handle some events
    addon.on('GET_ITEM_INFO_RECEIVED', private.onItemInfoReceived)
end

function ui.isTransmogrifyingSets()
    return WardrobeCollectionFrame:IsVisible()
        and WardrobeCollectionFrame.selectedTab == 2
        and C_Transmog.IsAtTransmogNPC()
end

function ui.refreshSets(updateModels)
    if not ui.isTransmogrifyingSets() then
        return
    end

    WardrobeCollectionFrame.SetsTransmogFrame:OnEvent('TRANSMOG_COLLECTION_UPDATED')

    if updateModels then
        for _, model in pairs(WardrobeCollectionFrame.SetsTransmogFrame.Models) do
            model.setID = -1
        end

        WardrobeCollectionFrame.SetsTransmogFrame:UpdateSets()
    end
end

function ui.refreshSetsDelayed(updateModels)
    if updateTimer then
        updateTimer:Cancel()
    end

    if updateModels then
        pendingModelUpdate = true
    end

    updateTimer = C_Timer.NewTimer(1, function ()
        ui.refreshSets(pendingModelUpdate)
        updateTimer = nil
        pendingModelUpdate = false
    end)
end

function private.onWardrobeShow()
    -- refresh sets after re-opening the transmog sets UI
    if ui.isTransmogrifyingSets() then
        ui.refreshSetsDelayed(true)
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
        ui.refreshSetsDelayed(true)
    end
end

function private.onItemInfoReceived(itemId)
    -- refresh sets when receiving item info with transmog sets UI open
    if itemId > 0 and ui.isTransmogrifyingSets() then
        ui.refreshSetsDelayed(true)
    end
end
