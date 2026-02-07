---@class Addon
local addon = select(2, ...)
---@class UI.SetsTabModule
local setsTab, private = addon.module('ui', 'setsTab'), {}
---@type SetLoaderModule
local setLoader = addon.namespace('setLoader')
---@type ConfigModule
local config = addon.namespace('config')
local setsFrameRef
---@type table<number, Enum.TransmogOutfitSlot[]>?
local outflitSlotCache
---@type table<number, number|false>
local hiddenSourceCache = {}
---@type UI.SetsTabModule.SetListInfo?
local currentSetListInfo
local lastTooltipModel
---@type table
local loadingIndicator

---@class (exact) UI.SetsTabModule.Filter
---@field searchQuery string
---@field maxMissingPieces integer
---@field onlyFavorite boolean
---@field favoriteVariants boolean
---@field ignoredSlots table<number, true>
---@field hiddenSlots table<number, true>
---@field classMask integer

---@class (exact) UI.SetsTabModule.SetListInfo
---@field count integer
---@field stats table<number, UI.SetsTabModule.SetStats>
---@field classMask integer
---@field hiddenSlotsKey string

---@class (exact) UI.SetsTabModule.SetStats
---@field collected integer
---@field total integer
---@field missingSlotsKey string
---@field favorite boolean

---@param setsFrame table
---@diagnostic disable: duplicate-set-field
function setsTab.hook(setsFrame)
    -- override set frame methods
    setsFrame.RefreshCollectionEntries = private.refreshCollectionEntries
    setsFrame.GetFirstMatchingSetID = private.getFirstMatchingSetId

    -- override model mixin methods
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
        private.updateTooltip(self)
    end

    function TransmogSetModelMixin:OnMouseDown(button)
        if button == 'LeftButton' and self.elementData then
            PlaySound(SOUNDKIT.UI_TRANSMOG_ITEM_CLICK)
            private.applySet(self.elementData.set.setID)
        else
            originalOnMouseDown(self, button)
        end
    end

    -- store set frame reference
    setsFrameRef = setsFrame

    -- create loading indicator
    loadingIndicator = CreateFrame('Frame', nil, setsFrameRef.PagedContent, 'BackdropTemplate')
    loadingIndicator:SetFrameStrata('HIGH')
    loadingIndicator:SetPoint('CENTER')
    loadingIndicator:SetSize(220, 48)
    loadingIndicator:SetBackdrop({
        bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background',
        edgeFile = 'Interface\\DialogFrame\\UI-DialogBox-Border',
        edgeSize = 16,
        insets = {left = 6, right = 6, top = 6, bottom = 6},
    })
    loadingIndicator:SetBackdropColor(0, 0, 0, 0.6)
    loadingIndicator:Hide()

    local text = loadingIndicator:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    text:SetPoint('CENTER', 8, 0)
    text:SetText(SEARCH_LOADING_TEXT)

    local spinner = CreateFrame('Frame', nil, loadingIndicator, 'SpinnerTemplate')
    spinner:SetSize(20, 20)
    spinner:SetPoint('RIGHT', text, 'LEFT', -5, 0)

    -- refresh the UI when new data is loaded or config changes
    addon.event.on('setLoader.update', setsTab.refreshIfVisible)
    addon.event.on('config.update', setsTab.refreshIfVisible)
    addon.on('TRANSMOG_COLLECTION_ITEM_UPDATE', private.refreshSetTooltip)
end

function setsTab.refreshIfVisible()
    if setsFrameRef and private.isVisible() then
        setsFrameRef:RefreshCollectionEntries()
    end
end

---@return boolean
function setsTab.isPveOrPvpFiltered()
    return (
        not C_TransmogSets.GetSetsFilter(LE_TRANSMOG_SET_FILTER_PVE)
        or not C_TransmogSets.GetSetsFilter(LE_TRANSMOG_SET_FILTER_PVP)
    )
end

function private.isVisible()
    if TransmogFrame and TransmogFrame:IsVisible() then
        local collection = TransmogFrame.WardrobeCollection

        return collection:GetTab() == collection.setsTabID
    end

    return false
end

---@param frame table
function private.refreshCollectionEntries(frame)
    if not private.isVisible() then
        -- don't refresh when not visible
        -- (loading when the transmog UI is initially open can cause missing items on the character preview because of bad UI code)
        return
    end

    ---@type UI.SetsTabModule.Filter
    local filter = {
        searchQuery = private.normalizeSearchString(frame.SearchBox:GetText()),
        maxMissingPieces = config.maxMissingPieces(),
        onlyFavorite = config.onlyFavorite(),
        favoriteVariants = config.favoriteVariants(),
        ignoredSlots = config.ignoredSlots.getMap(),
        hiddenSlots = config.hiddenSlots.getMap(),
        classMask = private.getCurrentClassMask(),
    }

    local sets

    setLoader.updatePerformance()

    if setsTab.isPveOrPvpFiltered() then
        -- if the built-in PvE or PvP filter is used, we have to show the pre-filtered available sets only
        -- (currently, the data whether a set is PvP or PvE is not present in TransmogSetInfo)
        sets = setLoader.getAvailableSets()
    else
        sets = setLoader.getAllSets(filter.classMask)
    end

    local setList, setListInfo = private.generateSetList(sets, filter)

    loadingIndicator:SetShown(setLoader.isLoading())

    if currentSetListInfo and private.setListInfosEqual(currentSetListInfo, setListInfo) then
        -- no change to set data
        return
    end

    frame.setsDataProvider:ClearSets()
    frame.setsDataProvider:SortSets(setList, false, false, false)

    local collectionElements = {}

    for _, setInfo in ipairs(setList) do
        local set = sets[setInfo.setID]
        local stats = setListInfo.stats[setInfo.setID]

        assert(set)
        assert(stats)

        local sourceData = private.buildSourceData(set, stats, filter)

        table.insert(collectionElements, {
            templateKey = 'COLLECTION_SET',
            set = setInfo,
            sourceData = sourceData,
            collectionFrame = frame,
        })
    end

    local dataProvider = CreateDataProvider({{elements = collectionElements}})
    frame.PagedContent:SetDataProvider(dataProvider, true)

    currentSetListInfo = setListInfo
end

---@param set SetLoaderModule.Set
---@param stats UI.SetsTabModule.SetStats
---@param filter UI.SetsTabModule.Filter
---@return table
function private.buildSourceData(set, stats, filter)
    local primaryAppearances = {}

    for _, slot in pairs(set.slots) do
        local sourceId

        if not slot.usableSourceId or filter.hiddenSlots[slot.invSlotId] then
            -- use a hidden appearance if slot is not collected or always hidden
            sourceId = private.getSourceIdForHiddenSlot(slot.invSlotId)
        else
            sourceId = slot.usableSourceId
        end

        if sourceId then
            table.insert(primaryAppearances, {
                appearanceID = sourceId,
                collected = true,
            })
        end
    end

    return {
        numCollected = stats.collected,
        numTotal = stats.total,
        primaryAppearances = primaryAppearances,
    }
end

---@param frame table
---@return number? appliedSetId
---@return boolean? hasPending
function private.getFirstMatchingSetId(frame)
    ---@type TransmogSetInfo[]
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
                local sourceIDs = C_TransmogOutfitInfo.GetSourceIDsForSlot(usableSet.setID, transmogLocation:GetSlot()) or {}
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

---@return integer
function private.getCurrentClassMask()
    local classId = select(3, UnitClass('player'))

    if config.showExtraSets() then
        return addon.const.armorTypeClassMasks[classId]
    end

    return addon.const.classMasks[classId]
end

---@param sets SetLoaderModule.SetMap
---@param filter UI.SetsTabModule.Filter
---@return TransmogSetInfo[]
---@return UI.SetsTabModule.SetListInfo
function private.generateSetList(sets, filter)
    ---@type TransmogSetInfo[]
    local setList = {}
    ---@type UI.SetsTabModule.SetListInfo
    local setListInfo = {
        count = 0,
        stats = {},
        classMask = filter.classMask,
        hiddenSlotsKey = private.tableKeysToCacheKey(filter.hiddenSlots),
    }

    local isPrefiltered = setsTab.isPveOrPvpFiltered()

    for setId, set in pairs(sets) do
        local collectedSlots, totalSlots, missingSlots = private.getEffectiveSetProgress(set)
        local missingSlotCount = #missingSlots
        local isCollected = totalSlots > 0 and missingSlotCount == 0

        if
            collectedSlots > 0
            and missingSlotCount <= filter.maxMissingPieces
            and private.passesFavoriteFilter(set.info, sets, filter)
            and (isPrefiltered or private.passesCollectedFilter(isCollected))
            and (isPrefiltered or private.matchesSearchQuery(set.info, filter.searchQuery))
        then
            local setInfoCopy = CopyTable(set.info) -- setLoader caches these internally, so don't modify them
            setInfoCopy.collected = isCollected

            setListInfo.count = setListInfo.count + 1
            setListInfo.stats[setId] = {
                collected = collectedSlots,
                total = totalSlots,
                missingSlotsKey = private.tableValuesToCacheKey(missingSlots),
                favorite = set.info.favorite,
            }

            table.insert(setList, setInfoCopy)
        end
    end

    return setList, setListInfo
end

---@param infoA UI.SetsTabModule.SetListInfo
---@param infoB UI.SetsTabModule.SetListInfo
---@return boolean
function private.setListInfosEqual(infoA, infoB)
    if infoA.count ~= infoB.count or infoA.hiddenSlotsKey ~= infoB.hiddenSlotsKey then
        return false
    end

    for setId, statsA in pairs(infoA.stats) do
        local statsB = infoB.stats[setId]

        if
            not statsB
            or statsA.collected ~= statsB.collected
            or statsA.total ~= statsB.total
            or statsA.missingSlotsKey ~= statsB.missingSlotsKey
            or statsA.favorite ~= statsB.favorite
        then
            return false
        end
    end

    return true
end

---@param set SetLoaderModule.Set
---@return integer collected
---@return integer total
---@return number[] missing
function private.getSetProgress(set)
    local collected = 0
    local total = 0
    local missing = {}

    for invSlotId, slot in pairs(set.slots) do
        total = total + 1

        if slot.usableSourceId then
            collected = collected + 1
        else
            table.insert(missing, invSlotId)
        end
    end

    return collected, total, missing
end

---@param set SetLoaderModule.Set
---@return integer collected
---@return integer total
---@return number[] missing
function private.getEffectiveSetProgress(set)
    local collected = 0
    local total = 0
    local missing = {}

    for invSlotId, slot in pairs(set.slots) do
        if
            not config.ignoredSlots.has(invSlotId)
            and not config.hiddenSlots.has(invSlotId)
        then
            total = total + 1

            if slot.usableSourceId then
                collected = collected + 1
            else
                table.insert(missing, invSlotId)
            end
        end
    end

    return collected, total, missing
end

---@param str string
---@return string
function private.normalizeSearchString(str)
    return string.lower(strtrim(str))
end

---@param setInfo TransmogSetInfo
---@param query string
---@return boolean
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

---@param haystack string
---@param query string
---@return boolean
function private.matchSearchQuery(haystack, query)
    return string.find(private.normalizeSearchString(haystack), query, 1, true) ~= nil
end

---@param isCollected boolean
---@return boolean
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

---@param setInfo TransmogSetInfo
---@param sets SetLoaderModule.SetMap
---@param filter UI.SetsTabModule.Filter
---@return boolean
function private.passesFavoriteFilter(setInfo, sets, filter)
    if not filter.onlyFavorite then
        return true
    end

    if setInfo.favorite then
        return true
    end

    if filter.favoriteVariants and private.setHasFavoriteVariant(setInfo, sets) then
        return true
    end

    return false
end

---@param setInfo TransmogSetInfo
---@param sets SetLoaderModule.SetMap
---@return boolean
function private.setHasFavoriteVariant(setInfo, sets)
    local baseSetId

    if setInfo.baseSetID then
        -- this is a variant set
        ---@type number
        baseSetId = setInfo.baseSetID

        -- check whether the base set is favorited
        if sets[setInfo.baseSetID] and sets[setInfo.baseSetID].info.favorite then
            return true
        end
    else
        -- this is a base set
        baseSetId = setInfo.setID
    end

    -- check variants of the base set
    local variants = C_TransmogSets.GetVariantSets(baseSetId)

    if variants then
        for _, variant in ipairs(variants) do
            if variant.favorite then
                return true
            end
        end
    end

    return false
end

---@param setId number
function private.applySet(setId)
    local set = setLoader.getSet(setId)

    if not set then
        return
    end

    for invSlotId, slot in pairs(set.slots) do
        if not config.skippedSlots.has(invSlotId) then
            local sourceId

            if not slot.usableSourceId or config.hiddenSlots.has(invSlotId) then
                -- use a hidden appearance if slot is not collected or always hidden
                sourceId = private.getSourceIdForHiddenSlot(invSlotId)
            else
                sourceId = slot.usableSourceId
            end

            if sourceId then
                for _, outfitSlot in ipairs(private.getOutfitSlotsForInventorySlot(invSlotId)) do
                    private.applyPendingTransmog(outfitSlot, sourceId)
                end
            end
        end
    end

    if config.hideItemsNotInSet() then
        for invSlotId in pairs(addon.const.hiddenItemMap) do
            if not config.skippedSlots.has(invSlotId) and not set.slots[invSlotId] then
                local sourceId = private.getSourceIdForHiddenSlot(invSlotId)

                if sourceId then
                    for _, outfitSlot in ipairs(private.getOutfitSlotsForInventorySlot(invSlotId)) do
                        private.applyPendingTransmog(outfitSlot, sourceId)
                    end
                end
            end
        end
    end
end

---@param outfitSlot Enum.TransmogOutfitSlot
---@param sourceId number
function private.applyPendingTransmog(outfitSlot, sourceId)
    local option = C_TransmogOutfitInfo.GetEquippedSlotOptionFromTransmogSlot(outfitSlot) or Enum.TransmogOutfitSlotOption.None
    local displayType

    if C_TransmogCollection.IsAppearanceHiddenVisual(sourceId) then
        displayType = Enum.TransmogOutfitDisplayType.Hidden
    else
        displayType = Enum.TransmogOutfitDisplayType.Assigned
    end

    C_TransmogOutfitInfo.SetPendingTransmog(
        outfitSlot,
        Enum.TransmogType.Appearance,
        option,
        sourceId,
        displayType
    )
end

---@param invSlotId number
---@return Enum.TransmogOutfitSlot[]
function private.getOutfitSlotsForInventorySlot(invSlotId)
    if not outflitSlotCache then
        outflitSlotCache = {}

        for _, slotInfo in ipairs(C_TransmogOutfitInfo.GetAllSlotLocationInfo() or {}) do
            local slotInvSlotId = GetInventorySlotInfo(slotInfo.slotName)

            if not outflitSlotCache[slotInvSlotId] then
                outflitSlotCache[slotInvSlotId] = {}
            end

            table.insert(outflitSlotCache[slotInvSlotId], slotInfo.slot)
        end
    end

    return outflitSlotCache[invSlotId] or {}
end

---@param invSlotId number
---@return number?
function private.getSourceIdForHiddenSlot(invSlotId)
    local sourceId = hiddenSourceCache[invSlotId]

    if sourceId then
        return sourceId
    end

    if sourceId == false then
        return nil
    end

    local hiddenItemId = addon.const.hiddenItemMap[invSlotId]

    if hiddenItemId then
        sourceId = (select(2, C_TransmogCollection.GetItemInfo(addon.const.hiddenItemMap[invSlotId])))
    end

    hiddenSourceCache[invSlotId] = sourceId or false

    return sourceId
end

function private.refreshSetTooltip()
    -- prevent a tooltip stuck on "Retrieving item information" (base UI bug)
    if setsFrameRef and setsFrameRef:IsVisible() and lastTooltipModel and lastTooltipModel:IsMouseOver() then
        lastTooltipModel:RefreshTooltip()
    end
end

function private.updateTooltip(model)
    if not model.elementData then
        return
    end

    lastTooltipModel = model

    local set = setLoader.getSet(model.elementData.set.setID)

    if not set then
        return
    end

    local collectedSlots, totalSlots, missingSlots = private.getSetProgress(set)

    local numLines = GameTooltip:NumLines()
    local lastLine = _G['GameTooltipTextLeft' .. numLines]
    local lastText = lastLine and lastLine:GetText()

    if lastText == TRANSMOG_SET_COMPLETE or lastText == TRANSMOG_SET_INCOMPLETE then
        local isComplete = (#missingSlots == 0)
        local statusText = isComplete and TRANSMOG_SET_COMPLETE or TRANSMOG_SET_INCOMPLETE
        local color = private.getSetProgressColor(collectedSlots, totalSlots)

        lastLine:SetText(string.format('|c%s%s %d/%d|r', color, statusText, collectedSlots, totalSlots))

        if not isComplete then
            local missingSlotsText = string.format('(Missing: %s)', private.formatSlotList(missingSlots, 3))
            GameTooltip:AddLine(missingSlotsText, 0.5, 0.5, 0.5)
        end
    end

    if IsAltKeyDown() then
        GameTooltip:AddLine(string.format('(Set ID: %d)', set.info.setID), 0.5, 0.5, 0.5)
    end

    GameTooltip:Show()
end

---@param slots number[]
---@param limit integer
---@return string
function private.formatSlotList(slots, limit)
    local slotMap = {}

    for _, invSlotId in ipairs(slots) do
        slotMap[invSlotId] = true
    end

    local slotNames = {}

    for invSlotId, name in pairs(addon.const.slotLabelMap) do
        if slotMap[invSlotId] then
            table.insert(slotNames, name)

            if #slotNames >= limit then
                break
            end
        end
    end

    local suffix = ''

    if #slots > limit then
        suffix = string.format(' and %d more', #slots - limit)
    end

    return string.format('%s%s', table.concat(slotNames, ', '), suffix)
end

---@param collected integer
---@param total integer
---@return string
function private.getSetProgressColor(collected, total)
    if collected >= total then
        return 'ff008000'
    elseif total > 0 and collected / total >= 0.49 then
        return 'fffea000'
    else
        return 'ff800000'
    end
end

---@param values table<any, string|number>
---@return string
function private.tableValuesToCacheKey(values)
    local parts = {}

    for _, value in pairs(values) do
        table.insert(parts, value)
    end

    table.sort(parts)

    return table.concat(parts, ':')
end


---@param values table<string|number, any>
---@return string
function private.tableKeysToCacheKey(values)
    local parts = {}

    for key in pairs(values) do
        table.insert(parts, key)
    end

    table.sort(parts)

    return table.concat(parts, ':')
end
