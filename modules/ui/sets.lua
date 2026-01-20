local _, addon = ...
local sets, private = addon.module('ui', 'sets'), {}
local setLoader = addon.namespace('setLoader')
local config = addon.namespace('config')
local sourceLoader = addon.namespace('sourceLoader')
local setsFrameRef
local outfitSlotMap = {}
local currentSetListInfo = {count = 0, map = {},  hiddenSlotsKey = ''}
local lastTooltipModel
local maxMissingSlotsInTooltip = 3
local deferredRefresh

function sets.init()
    deferredRefresh = addon.defer(0.5, sets.refresh)
end

function sets.hook(setsFrame)
    setsFrame.RefreshCollectionEntries = private.refreshCollectionEntries
    setsFrame.GetFirstMatchingSetID = private.getFirstMatchingSetID

    local originalUpdateSet = TransmogSetModelMixin.UpdateSet
    local originalRefreshTooltip = TransmogSetModelMixin.RefreshTooltip
    local originalOnMouseDown = TransmogSetModelMixin.OnMouseDown

    function TransmogSetModelMixin:UpdateSet()
        originalUpdateSet(self)

        if self.elementData then
            self.Border:SetAtlas('transmog-setcard-default')
            self.Highlight:SetAtlas('transmog-setcard-default')

            if self.IncompleteOverlay then
                self.IncompleteOverlay:Hide()
            end
        end
    end

    function TransmogSetModelMixin:RefreshTooltip()
        originalRefreshTooltip(self)
        private.appendTooltip(self)
    end

    function TransmogSetModelMixin:OnMouseDown(button)
        if button == 'LeftButton' and self.elementData then
            PlaySound(SOUNDKIT.UI_TRANSMOG_ITEM_CLICK)
            private.applySet(self.elementData.set.setID)
        else
            originalOnMouseDown(self, button)
        end
    end

    setsFrameRef = setsFrame
    addon.on('TRANSMOG_COLLECTION_ITEM_UPDATE', private.onCollectionItemUpdate)
end

function sets.refresh()
    if setsFrameRef then
        setsFrameRef:RefreshCollectionEntries()
    end
end

function sets.isPveOrPveFiltered()
    return (
        not C_TransmogSets.GetSetsFilter(LE_TRANSMOG_SET_FILTER_PVE)
        or not C_TransmogSets.GetSetsFilter(LE_TRANSMOG_SET_FILTER_PVP)
    )
end

function private.onCollectionItemUpdate()
    -- prevent a tooltip stuck on "Retrieving item information" (base UI bug)
    if lastTooltipModel and lastTooltipModel:IsMouseOver() then
        lastTooltipModel:RefreshTooltip()
    end

    -- schedule a refresh
    deferredRefresh()
end

function private.refreshCollectionEntries(frame)
    local searchQuery = private.normalizeSearchString(frame.SearchBox:GetText())
    local setList, newSetListInfo = private.generateSetList(searchQuery)

    if private.setListInfosEqual(currentSetListInfo, newSetListInfo) then
        -- no change to set data
        return
    end

    frame.setsDataProvider:ClearSets()
    frame.setsDataProvider:SortSets(setList, false, false, false)

    local collectionElements = {}

    for _, setInfo in ipairs(setList) do
        local sourceData = private.buildSourceData(
            setInfo.setID,
            setInfo._mogPartialSetsCollectedSlots,
            setInfo._mogPartialSetsTotalSlots
        )

        table.insert(collectionElements, {
            templateKey = 'COLLECTION_SET',
            set = setInfo,
            sourceData = sourceData,
            collectionFrame = frame,
        })
    end

    local dataProvider = CreateDataProvider({{elements = collectionElements}})
    frame.PagedContent:SetDataProvider(dataProvider, true)

    currentSetListInfo = newSetListInfo
end

function private.getFirstMatchingSetID(frame)
    local setsOnPage = {}

    frame.PagedContent:ForEachFrame(function(elementFrame, elementData)
        if elementData and elementData.set then
            table.insert(setsOnPage, elementData.set)
        end
    end)

    local transmogInfo = frame:GetCurrentTransmogInfoCallback()

    for _, usableSet in ipairs(setsOnPage) do
        local setMatched = false
        local hasPending = false

        for transmogLocation, info in pairs(transmogInfo) do
            if transmogLocation:IsAppearance() then
                local sourceIDs = C_TransmogOutfitInfo.GetSourceIDsForSlot(usableSet.setID, transmogLocation:GetSlot())
                local slotMatched = #sourceIDs == 0

                for _, sourceID in ipairs(sourceIDs) do
                    if info.transmogID == sourceID then
                        slotMatched = true

                        if info.hasPending then
                            hasPending = true
                        end

                        break
                    end
                end

                setMatched = slotMatched

                if not slotMatched then
                    break
                end
            end
        end

        if setMatched then
            return usableSet.setID, hasPending
        end
    end

    return nil, nil
end

function private.generateSetList(searchQuery)
    local baseFiltered = sets.isPveOrPveFiltered()
    local availableSets

    if baseFiltered then
        availableSets = {}

        for _, setInfo in ipairs(C_TransmogSets.GetAvailableSets()) do
            availableSets[setInfo.setID] = setInfo
        end
    else
        availableSets = setLoader.getUsableSets()
    end

    local setList = {}
    local setListInfo = {count = 0, map = {}, hiddenSlotsKey = private.getHiddenSlotsKey()}

    for _, setInfo in pairs(availableSets) do
        local collectedSlots, totalSlots = setLoader.getSetProgress(setInfo.setID)
        local isCollected = totalSlots > 0 and collectedSlots >= totalSlots

        if
            collectedSlots > 0
            and (totalSlots - collectedSlots) <= config.db.maxMissingPieces
            and private.passesFavoriteFilter(setInfo, availableSets)
            and private.passesCollectedFilter(isCollected)
            and (baseFiltered or private.matchesSearchQuery(setInfo, searchQuery))
        then
            setInfo.collected = isCollected
            setInfo._mogPartialSetsCollectedSlots = collectedSlots
            setInfo._mogPartialSetsTotalSlots = totalSlots

            setListInfo.count = setListInfo.count + 1
            setListInfo.map[setInfo.setID] = {collected = collectedSlots, total = totalSlots}

            table.insert(setList, setInfo)
        end
    end

    return setList, setListInfo
end

function private.getHiddenSlotsKey()
    local hiddenSlots = {}

    for slot in pairs(config.db.hiddenSlotMap) do
        table.insert(hiddenSlots, slot)
    end

    table.sort(hiddenSlots)

    return table.concat(hiddenSlots, ':')
end

function private.setListInfosEqual(infoA, infoB)
    if infoA.count ~= infoB.count or infoA.hiddenSlotsKey ~= infoB.hiddenSlotsKey then
        return false
    end

    for setId, setMetaA in pairs(infoA.map) do
        local setMetaB = infoB.map[setId]

        if
            setMetaB == nil
            or setMetaA.collected ~= setMetaB.collected
            or setMetaA.total ~= setMetaB.total
        then
            return false
        end
    end

    return true
end

function private.normalizeSearchString(str)
    return string.lower(strtrim(str))
end

function private.matchesSearchQuery(setInfo, query)
    if query == '' then
        return true
    end

    if private.matchSearchQuery(setInfo.name, query) then
        return true
    end

    if setInfo.label and private.matchSearchQuery(setInfo.label, query) then
        return true
    end

    return false
end

function private.matchSearchQuery(haystack, query)
    return string.find(private.normalizeSearchString(haystack), query, 1, true) ~= nil
end

function private.passesCollectedFilter(isCollected)
    local collectedEnabled = C_TransmogSets.GetSetsFilter(LE_TRANSMOG_SET_FILTER_COLLECTED)
    local uncollectedEnabled = C_TransmogSets.GetSetsFilter(LE_TRANSMOG_SET_FILTER_UNCOLLECTED)

    if isCollected and not collectedEnabled then
        return false
    end

    if not isCollected and not uncollectedEnabled then
        return false
    end

    return true
end

function private.passesFavoriteFilter(setInfo, availableSets)
    if not config.db.onlyFavorite then
        return true
    end

    if setInfo.favorite then
        return true
    end

    if config.db.favoriteVariants and setLoader.setHasFavoriteVariant(setInfo, availableSets) then
        return true
    end

    return false
end

function private.applySet(setId)
    local _, slotSourceIds = setLoader.getSetAppearancesForLoadSet(setId)

    for slot, sourceId in pairs(slotSourceIds) do
        if sourceId then
            local transmogSlots = private.getOutfitSlotsForInventorySlot(slot)

            if transmogSlots then
                for _, transmogSlot in ipairs(transmogSlots) do
                    private.applyPendingTransmog(transmogSlot, sourceId)
                end
            end
        end
    end
end

function private.applyPendingTransmog(slot, sourceId)
    local weaponOption = C_TransmogOutfitInfo.GetEquippedSlotOptionFromTransmogSlot(slot) or Enum.TransmogOutfitSlotOption.None
    local displayType = Enum.TransmogOutfitDisplayType.Assigned

    if C_TransmogCollection.IsAppearanceHiddenVisual(sourceId) then
        displayType = Enum.TransmogOutfitDisplayType.Hidden
    end

    C_TransmogOutfitInfo.SetPendingTransmog(
        slot,
        Enum.TransmogType.Appearance,
        weaponOption,
        sourceId,
        displayType
    )
end

function private.buildSourceData(setId, collectedSlots, totalSlots)
    local primaryAppearances = {}

    setLoader.iterateSetApperances(setId, function (slot)
        local sourceInfo = private.getPreviewSourceForSlot(setId, slot)

        if sourceInfo then
            table.insert(primaryAppearances, {
                appearanceID = sourceInfo.sourceID,
                collected = true,
            })
        end
    end)

    return {
        numCollected = collectedSlots,
        numTotal = totalSlots,
        primaryAppearances = primaryAppearances,
    }
end

function private.getPreviewSourceForSlot(setId, slot)
    if config.isHiddenSlot(slot) then
        local hiddenSourceId = sourceLoader.getSourceIdForHiddenSlot(slot)
        local sourceInfo = sourceLoader.getInfo(hiddenSourceId, true)
        if sourceInfo then
            return sourceInfo
        end
    end

    return setLoader.getUsableSetSlotSource(setId, slot)
end

function private.getOutfitSlotsForInventorySlot(invSlot)
    if not outfitSlotMap[invSlot] then
        for _, slotInfo in ipairs(C_TransmogOutfitInfo.GetAllSlotLocationInfo() or {}) do
            local invSlotId = GetInventorySlotInfo(slotInfo.slotName)

            if not outfitSlotMap[invSlotId] then
                outfitSlotMap[invSlotId] = {}
            end

            table.insert(outfitSlotMap[invSlotId], slotInfo.slot)
        end
    end

    return outfitSlotMap[invSlot]
end

function private.appendTooltip(model)
    if not model.elementData then
        return
    end

    lastTooltipModel = model

    local setId = model.elementData.set.setID
    local collectedSlots, totalSlots = setLoader.getRealSetProgress(setId)

    if totalSlots then
        local numLines = GameTooltip:NumLines()
        local lastLine = _G['GameTooltipTextLeft' .. numLines]
        local lastText = lastLine and lastLine:GetText() or nil

        if lastText == TRANSMOG_SET_COMPLETE or lastText == TRANSMOG_SET_INCOMPLETE then
            local isComplete = collectedSlots >= totalSlots
            local statusText = isComplete and TRANSMOG_SET_COMPLETE or TRANSMOG_SET_INCOMPLETE
            local color = private.getSetProgressColor(collectedSlots, totalSlots)

            lastLine:SetText(string.format('|c%s%s %d/%d|r', color, statusText, collectedSlots, totalSlots))

            if not isComplete then
                private.addMissingSlotsToTooltip(setId)
            end
        end
    end

    if IsAltKeyDown() then
        GameTooltip:AddLine(string.format('(Set ID: %d)', setId), 0.5, 0.5, 0.5)
    end

    GameTooltip:Show()
end

function private.addMissingSlotsToTooltip(setId)
    local missingSlots = setLoader.getMissingSlots(setId)

    if #missingSlots == 0 then
        return
    end

    local missingNames = {}

    for i = 1, math.min(#missingSlots, maxMissingSlotsInTooltip) do
        table.insert(missingNames, addon.const.slotLabelMap[missingSlots[i]])
    end

    local suffix = ''

    if #missingSlots > maxMissingSlotsInTooltip then
        suffix = string.format(' and %d more', #missingSlots - maxMissingSlotsInTooltip)
    end

    local line = string.format('(Missing: %s%s)', table.concat(missingNames, ', '), suffix)

    GameTooltip:AddLine(line, 0.5, 0.5, 0.5)
end

function private.getSetProgressColor(current, max)
    if current >= max then
        return 'ff008000'
    elseif max > 0 and current / max >= 0.49 then
        return 'fffea000'
    else
        return 'ff800000'
    end
end
