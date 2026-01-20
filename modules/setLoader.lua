local _, addon = ...
local setLoader, private = addon.module('setLoader'), {}
local sourceLoader = addon.namespace('sourceLoader')
local config = addon.namespace('config')
local validSetCache = {} -- setId => bool
local primarySetAppearanceCache = {} -- setId => TransmogSetPrimaryAppearanceInfo[]
local setSlotSourceIdCache = {} -- setId => slot => sourceId[]
local usableSetSlotSourceCache = {} -- setId => slot => AppearanceSourceInfo

function setLoader.init()
    addon.on('TRANSMOG_COLLECTION_SOURCE_ADDED', private.onSourceAddedOrRemoved)
    addon.on('TRANSMOG_COLLECTION_SOURCE_REMOVED', private.onSourceAddedOrRemoved)
end

function setLoader.clearCaches()
    validSetCache = {}
    primarySetAppearanceCache = {}
    setSlotSourceIdCache = {}
    usableSetSlotSourceCache = {}
end

function setLoader.getUsableSets()
    local sets = {}
    local classMask = private.getCurrentClassMask()
    local faction = UnitFactionGroup('player')

    for _, set in ipairs(C_TransmogSets.GetAllSets()) do
        if
            -- match class
            (set.classMask == 0 or bit.band(set.classMask, classMask) ~= 0)
            -- match faction
            and (set.requiredFaction == nil or set.requiredFaction == faction)
            -- validate set
            and private.validateSet(set.setID)
        then
            sets[set.setID] = set
        end
    end

    return sets
end

function setLoader.getSetProgress(setId)
    local collectedSlots = 0
    local totalSlots = 0

    private.iterateSetApperances(setId, function (slot)
        if
            not config.isIgnoredSlot(slot)
            and not config.isHiddenSlot(slot)
        then
            totalSlots = totalSlots + 1

            if setLoader.getUsableSetSlotSource(setId, slot) then
                collectedSlots = collectedSlots + 1
            end
        end
    end)

    return collectedSlots, totalSlots
end

function setLoader.getRealSetProgress(setId)
    local collectedSlots = 0
    local totalSlots = 0

    private.iterateSetApperances(setId, function (slot)
        totalSlots = totalSlots + 1

        if setLoader.getUsableSetSlotSource(setId, slot) then
            collectedSlots = collectedSlots + 1
        end
    end)

    return collectedSlots, totalSlots
end

function setLoader.setHasFavoriteVariant(set, availableSets)
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

-- this is used when a set is being applied in the transmog UI
function setLoader.getSetAppearancesForLoadSet(setId)
    local appearances = {}
    local slotSourceIds = {}
    local skippedSlots = {}

    -- add collected appearances
    private.iterateSetApperances(setId, function (slot)
        local sourceId

        if config.isHiddenSlot(slot) then
            -- always hidden slot
            sourceId = sourceLoader.getSourceIdForHiddenSlot(slot)
        else
            local usableSource = setLoader.getUsableSetSlotSource(setId, slot)

            if usableSource then
                -- usable source
                sourceId = usableSource.sourceID
            elseif config.db.useHiddenIfMissing then
                -- hidden item
                sourceId = sourceLoader.getSourceIdForHiddenSlot(slot)
            else
                skippedSlots[slot] = true
                return
            end

            table.insert(appearances, {collected = true, appearanceID = sourceId})
            slotSourceIds[slot] = sourceId
        end
    end)

    -- add other slots as hidden, if enabled
    if config.db.hideItemsNotInSet then
        for slot in pairs(addon.const.hiddenItemMap) do
            if not slotSourceIds[slot] and not skippedSlots[slot] then
                local sourceId = sourceLoader.getSourceIdForHiddenSlot(slot)
                table.insert(appearances, {collected = true, appearanceID = sourceId})
                slotSourceIds[slot] = sourceId
            end
        end
    end

    return appearances, slotSourceIds
end

function setLoader.getUsableSetSlotSource(setId, slot)
    if usableSetSlotSourceCache[setId] and usableSetSlotSourceCache[setId][slot] then
        return usableSetSlotSourceCache[setId][slot]
    end

    for _, sourceId in ipairs(private.getSetSlotSourceIds(setId, slot)) do
        local sourceInfo, isPending = sourceLoader.getInfo(sourceId, true)

        if
            sourceInfo
            and sourceInfo.useErrorType == nil
            and sourceInfo.isValidSourceForPlayer ~= false
            and sourceInfo.canDisplayOnPlayer ~= false
            and sourceInfo.meetsTransmogPlayerCondition ~= false
        then
            if isPending then
                sourceInfo = CopyTable(sourceInfo, true)
                sourceInfo.name = '' -- avoid nil during pending item info
            else
                assert(sourceInfo.name)
                if not usableSetSlotSourceCache[setId] then
                    usableSetSlotSourceCache[setId] = {}
                end

                usableSetSlotSourceCache[setId][slot] = sourceInfo
            end

            return sourceInfo
        end
    end
end

function setLoader.iterateSetApperances(setId, callback)
    return private.iterateSetApperances(setId, callback)
end

function setLoader.getMissingSlots(setId)
    local missingSlots = {}

    private.iterateSetApperances(setId, function (slot)
        if not setLoader.getUsableSetSlotSource(setId, slot) then
            table.insert(missingSlots, slot)
        end
    end)

    return missingSlots
end

function private.getSetPrimaryAppearancesCached(setId)
    if primarySetAppearanceCache[setId] == nil then
        primarySetAppearanceCache[setId] = C_TransmogSets.GetSetPrimaryAppearances(setId)
    end

    return primarySetAppearanceCache[setId]
end

function private.getCurrentClassMask()
    local classId = select(3, UnitClass('player'))

    if config.db.showExtraSets then
        return addon.const.armorTypeClassMasks[classId]
    end

    return addon.const.classMasks[classId]
end

function private.validateSet(setId)
    if validSetCache[setId] == nil then
        local valid = false

        for _, appearanceInfo in ipairs(private.getSetPrimaryAppearancesCached(setId)) do
            local sourceInfo = sourceLoader.getInfo(appearanceInfo.appearanceID)

            if sourceInfo then
                local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
                local slotSources = C_TransmogSets.GetSourcesForSlot(setId, slot)
                local index = CollectionWardrobeUtil.GetDefaultSourceIndex(slotSources, appearanceInfo.appearanceID)

                if slotSources[index] then
                    setLoader.getUsableSetSlotSource(setId, slot) -- trigger loading of source data

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

function private.iterateSetApperances(setId, callback)
    for _, appearanceInfo in ipairs(private.getSetPrimaryAppearancesCached(setId)) do
        local sourceInfo = sourceLoader.getInfo(appearanceInfo.appearanceID)

        if sourceInfo then
            local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)

            if callback(slot, sourceInfo) == false then
                break
            end
        end
    end
end

function private.getSetSlotSourceIds(setId, slot)
    if setSlotSourceIdCache[setId] and setSlotSourceIdCache[setId][slot] then
        return setSlotSourceIdCache[setId][slot]
    end

    local sourceMap = {}

    -- map all known collected source IDs
    private.iterateSetApperances(setId, function (appearanceSlot, primarySourceInfo)
        if appearanceSlot == slot then
            if primarySourceInfo.isCollected then
                sourceMap[primarySourceInfo.sourceID] = true
            end

            for _, sourceInfo in ipairs(C_TransmogSets.GetSourcesForSlot(setId, slot)) do
                if sourceInfo.isCollected then
                    sourceMap[sourceInfo.sourceID] = true
                end
            end

            for _, sourceInfo in ipairs(
                C_TransmogCollection.GetAppearanceSources(
                    primarySourceInfo.visualID,
                    C_TransmogCollection.GetCategoryForItem(primarySourceInfo.sourceID),
                    TransmogUtil.GetTransmogLocation(
                        slot,
                        Enum.TransmogType.Appearance,
                        Enum.TransmogModification.Main
                    )
                ) or {}
            ) do
                if sourceInfo.isCollected then
                    sourceMap[sourceInfo.sourceID] = true
                end
            end
        end
    end)

    -- convert to list, cache, return
    local sourceIds = {}

    for sourceId in pairs(sourceMap) do
        table.insert(sourceIds, sourceId)
    end

    if not setSlotSourceIdCache[setId] then
        setSlotSourceIdCache[setId] = {}
    end

    setSlotSourceIdCache[setId][slot] = sourceIds

    return sourceIds
end

function private.onSourceAddedOrRemoved(sourceId)
    local sets = C_TransmogSets.GetSetsContainingSourceID(sourceId)

    if sets then
        for _, setId in pairs(sets) do
            validSetCache[setId] = nil
            primarySetAppearanceCache[setId] = nil
            setSlotSourceIdCache[setId] = nil
            usableSetSlotSourceCache[setId] = nil
        end
    end
end
