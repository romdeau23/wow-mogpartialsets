local _, addon = ...
local helpers, private = addon.module('api', 'helpers')
local overrides = addon.require('api', 'overrides');
local config = addon.require('config')
local validSetCache = {} -- setId => bool
local setAppearanceCache = {} -- setId => TransmogSetPrimaryAppearanceInfo[]
local sourceInfoCache = {} -- sourceId => AppearanceSourceInfo
local usableSourceCache = {} -- appearanceId => AppearanceSourceInfo
local hiddenItemMap = {
    [INVSLOT_HEAD] = 134110,
    [INVSLOT_SHOULDER] = 134112,
    [INVSLOT_BACK] = 134111,
    [INVSLOT_CHEST] = 168659,
    [INVSLOT_BODY] = 142503,
    [INVSLOT_TABARD] = 142504,
    [INVSLOT_WRIST] = 168665,
    [INVSLOT_HAND] = 158329,
    [INVSLOT_WAIST] = 143539,
    [INVSLOT_FEET] = 168664,
}

function helpers.init()
    addon.on('TRANSMOG_COLLECTION_SOURCE_ADDED', private.onSourceAddedOrRemoved)
    addon.on('TRANSMOG_COLLECTION_SOURCE_REMOVED', private.onSourceAddedOrRemoved)
end

function helpers.clearCaches()
    validSetCache = {}
    setAppearanceCache = {}
    sourceInfoCache = {}
    usableSourceCache = {}
end

function helpers.normalizeSearchString(string)
    return string.lower(strtrim(string))
end

function helpers.stringMatchesSearch(string, normalizedSearch)
    return string.find(helpers.normalizeSearchString(string), normalizedSearch, 1, true) ~= nil
end

function helpers.getAvailableSets(filter)
    local sets = {}

    for _, set in ipairs(C_TransmogSets.GetAllSets()) do
        if (filter == nil or filter(set)) and helpers.isValidSet(set.setID) then
            sets[set.setID] = set
        end
    end

    return sets
end

function helpers.isValidSet(setId)
    if validSetCache[setId] == nil then
        local valid = false

        for _, appearanceInfo in ipairs(helpers.getCollectedSetAppearances(setId)) do
            local sourceInfo = overrides.callOriginal('GetSourceInfo', appearanceInfo.appearanceID)

            if sourceInfo then
                local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
                local slotSources = C_TransmogSets.GetSourcesForSlot(setId, slot)
                local index = CollectionWardrobeUtil.GetDefaultSourceIndex(slotSources, appearanceInfo.appearanceID)

                if slotSources[index] then
                    valid = true
                end
            end

            if not valid then
                break
            end
        end

        validSetCache[setId] = valid
    end

    return validSetCache[setId]
end

function helpers.getSetProgress(setId)
    local collectedSlots
    local totalSlots
    local appearances = helpers.getSetPrimaryAppearancesCached(setId)

    if appearances then
        collectedSlots = 0
        totalSlots = 0

        for _, appearanceInfo in ipairs(appearances) do
            local sourceInfo = helpers.getCachedSourceInfo(appearanceInfo.appearanceID)

            if sourceInfo then
                local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)

                if
                    not config.isIgnoredSlot(slot)
                    and not config.isHiddenSlot(slot)
                then
                    totalSlots = totalSlots + 1

                    if appearanceInfo.collected or helpers.getUsableSource(appearanceInfo.appearanceID) ~= nil then
                        collectedSlots = collectedSlots + 1
                    end
                end
            end
        end
    end

    return collectedSlots, totalSlots
end

function helpers.getSetProgressColor(current, max)
    if current >= max then
        return 'ff008000'
    elseif max > 0 and current / max >= 0.49 then
        return 'fffea000'
    else
        return 'ff800000'
    end
end

function helpers.getSetSlots(setId)
    local slotMap = {}

    for _, appearanceInfo in ipairs(helpers.getSetPrimaryAppearancesCached(setId)) do
        local sourceInfo = helpers.getCachedSourceInfo(appearanceInfo.appearanceID)

        if sourceInfo then
            slotMap[C_Transmog.GetSlotForInventoryType(sourceInfo.invType)] = appearanceInfo.collected or helpers.getUsableSource(appearanceInfo.appearanceID) ~= nil
        end
    end

    return slotMap
end

function helpers.setHasFavoriteVariant(set, availableSets)
    local baseSetId

    if set.baseSetID then
        -- this is a variant set
        baseSetId = set.baseSetID

        -- check whether the base set is favorited
        if availableSets[set.baseSetID] and availableSets[set.baseSetID].favorite then
            return true
        end
    else
        -- this is a base set
        baseSetId = set.setID
    end

    -- check variants of the base set
    local variants = C_TransmogSets.GetVariantSets(baseSetId)

    if type(variants) == 'table' then
        for _, variant in ipairs(variants) do
            if variant.favorite then
                return true
            end
        end
    end

    return false
end

function helpers.getSetPrimaryAppearancesCached(setId)
    if setAppearanceCache[setId] == nil then
        setAppearanceCache[setId] = overrides.callOriginal('GetSetPrimaryAppearances', setId)
    end

    return setAppearanceCache[setId]
end

function helpers.getCollectedSetAppearances(setId)
    local appearances = {}

    for _, appearanceInfo in ipairs(helpers.getSetPrimaryAppearancesCached(setId)) do
        if appearanceInfo.collected then
            table.insert(appearances, appearanceInfo)
        else
            local usableAppearance = helpers.getUsableSource(appearanceInfo.appearanceID)

            if usableAppearance ~= nil then
                table.insert(appearances, {collected = true, appearanceID = usableAppearance.sourceID})
            end
        end
    end

    return appearances
end

function helpers.getApplicableSetAppearances(setId)
    local appearances = {}

    -- add collected appearances
    for _, appearanceInfo in ipairs(helpers.getCollectedSetAppearances(setId)) do
        local sourceInfo = helpers.getCachedSourceInfo(appearanceInfo.appearanceID)

        if sourceInfo then
            local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)

            if not config.isHiddenSlot(slot) then
                table.insert(appearances, appearanceInfo)
            end
        end
    end

    -- add hidden appearances
    local setSlots = helpers.getSetSlots(setId)

    for slot in pairs(hiddenItemMap) do
        if
            config.isHiddenSlot(slot) -- always hidden slot
            or config.db.useHiddenIfMissing and not setSlots[slot] -- missing or nonexistent set slot
        then
            table.insert(appearances, {collected = true, appearanceID = helpers.getSourceIdForHiddenSlot(slot)})
        end
    end

    return appearances
end

function helpers.getCachedSourceInfo(sourceId)
    if sourceInfoCache[sourceId] == nil then
        sourceInfoCache[sourceId] = overrides.callOriginal('GetSourceInfo', sourceId)
    end

    return sourceInfoCache[sourceId]
end

function helpers.getSourceIdForHiddenSlot(slot)
    return helpers.getSourceIdForItem(hiddenItemMap[slot])
end

function helpers.getSourceIdForItem(itemId)
    local _, sourceId = C_TransmogCollection.GetItemInfo(itemId)

    return sourceId
end

function helpers.getUsableSource(appearanceId)
    if usableSourceCache[appearanceId] == nil then
        local usableSource
        local loaded = false
        local baseSourceInfo = helpers.getCachedSourceInfo(appearanceId)

        if baseSourceInfo then
            local appearanceSources = C_TransmogCollection.GetAppearanceSources(
                baseSourceInfo.visualID,
                C_TransmogCollection.GetCategoryForItem(appearanceId),
                TransmogUtil.GetTransmogLocation(
                    C_Transmog.GetSlotForInventoryType(baseSourceInfo.invType),
                    Enum.TransmogType.Appearance,
                    Enum.TransmogModification.Main
                )
            )

            if appearanceSources then
                for _, sourceInfo in pairs(appearanceSources) do
                    -- check isCollected, useError and make sure the item is loaded
                    -- (useError may only be available after the item has been loaded)
                    if sourceInfo.isCollected and sourceInfo.useError == nil then
                        usableSource = sourceInfo
                        loaded = GetItemInfo(sourceInfo.itemID) ~= nil
                        break
                    end
                end
            end
        end

        if not loaded then
            -- don't cache items that aren't fully loaded
            return usableSource
        end

        usableSourceCache[appearanceId] = {source = usableSource}
    end

    return usableSourceCache[appearanceId].source
end

function helpers.canHideSlot(slot)
    return hiddenItemMap[slot] ~= nil
end

function private.onSourceAddedOrRemoved(sourceId)
    sourceInfoCache[sourceId] = nil

    local sourceInfo = overrides.callOriginal('GetSourceInfo', sourceId)

    if sourceInfo then
        usableSourceCache[sourceInfo.visualID] = nil
    end

    local sets = C_TransmogSets.GetSetsContainingSourceID(sourceId)

    if sets then
        for _, setId in pairs(sets) do
            validSetCache[setId] = nil
            setAppearanceCache[setId] = nil
        end
    end
end
