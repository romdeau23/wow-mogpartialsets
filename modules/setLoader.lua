local _, addon = ...
local setLoader, private = addon.module('setLoader')
local sourceLoader = addon.require('sourceLoader')
local overrides = addon.require('overrides')
local config = addon.require('config')
local validSetCache = {} -- setId => bool
local primarySetAppearanceCache = {} -- setId => TransmogSetPrimaryAppearanceInfo[]
local setSlotSourceIdCache = {} -- setId => slot => sourceId[]
local usableSetSlotSourceCache = {} -- setId => slot => AppearanceSourceInfo
-- https://warcraft.wiki.gg/wiki/ClassId
local classMasks = {
    [1] = 2 ^ (1 - 1), -- WARRIOR
    [2] = 2 ^ (2 - 1), -- PALADIN
    [3] = 2 ^ (3 - 1), -- HUNTER
    [4] = 2 ^ (4 - 1), -- ROGUE
    [5] = 2 ^ (5 - 1), -- PRIEST
    [6] = 2 ^ (6 - 1), -- DEATHKNIGHT
    [7] = 2 ^ (7 - 1), -- SHAMAN
    [8] = 2 ^ (8 - 1), -- MAGE
    [9] = 2 ^ (9 - 1), -- WARLOCK
    [10] = 2 ^ (10 - 1), -- MONK
    [11] = 2 ^ (11 - 1), -- DRUID
    [12] = 2 ^ (12 - 1), -- DEMONHUNTER
    [13] = 2 ^ (13 - 1), -- EVOKER
}
local armorTypeClassMasks = {
    -- cloth
    [5] = bit.bor(classMasks[5], classMasks[8], classMasks[9]), -- PRIEST
    [8] = bit.bor(classMasks[5], classMasks[8], classMasks[9]), -- MAGE
    [9] = bit.bor(classMasks[5], classMasks[8], classMasks[9]), -- WARLOCK

    -- leather
    [4] = bit.bor(classMasks[4], classMasks[10], classMasks[11], classMasks[12]), -- ROGUE
    [10] = bit.bor(classMasks[4], classMasks[10], classMasks[11], classMasks[12]), -- MONK
    [11] = bit.bor(classMasks[4], classMasks[10], classMasks[11], classMasks[12]), -- DRUID
    [12] = bit.bor(classMasks[4], classMasks[10], classMasks[11], classMasks[12]), -- DEMONHUNTER

    -- mail
    [3] = bit.bor(classMasks[3], classMasks[7], classMasks[13]), -- HUNTER
    [7] = bit.bor(classMasks[3], classMasks[7], classMasks[13]), -- SHAMAN
    [13] = bit.bor(classMasks[3], classMasks[7], classMasks[13]), -- EVOKER

    -- plate
    [1] = bit.bor(classMasks[1], classMasks[2], classMasks[6]), -- WARRIOR
    [2] = bit.bor(classMasks[1], classMasks[2], classMasks[6]), -- PALADIN
    [6] = bit.bor(classMasks[1], classMasks[2], classMasks[6]), -- DEATHKNIGHT
}
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
    [INVSLOT_LEGS] = 216696,
    [INVSLOT_FEET] = 168664,
}

function setLoader.init()
    addon.on('TRANSMOG_COLLECTION_SOURCE_ADDED', private.onSourceAddedOrRemoved)
    addon.on('TRANSMOG_COLLECTION_SOURCE_REMOVED', private.onSourceAddedOrRemoved)
end

function setLoader.clearCaches()
    validSetCache = {}
    primarySetAppearanceCache = {}
end

function setLoader.normalizeSearchString(string)
    return string.lower(strtrim(string))
end

function setLoader.stringMatchesSearch(string, normalizedSearch)
    return string.find(setLoader.normalizeSearchString(string), normalizedSearch, 1, true) ~= nil
end

function setLoader.getAvailableSets()
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

function setLoader.getSetProgressColor(current, max)
    if current >= max then
        return 'ff008000'
    elseif max > 0 and current / max >= 0.49 then
        return 'fffea000'
    else
        return 'ff800000'
    end
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

function setLoader.getSetPrimaryAppearancesCached(setId)
    if primarySetAppearanceCache[setId] == nil then
        primarySetAppearanceCache[setId] = overrides.callOriginal('GetSetPrimaryAppearances', setId)
    end

    return primarySetAppearanceCache[setId]
end

function setLoader.getApplicableSetAppearances(setId, fallbackToHidden)
    local appearances = {}

    -- add collected appearances
    private.iterateSetApperances(setId, function (slot)
        if config.isHiddenSlot(slot) then
            -- always hidden slot
            table.insert(appearances, {collected = true, appearanceID = setLoader.getSourceIdForHiddenSlot(slot)})
        else
            local usableSource = setLoader.getUsableSetSlotSource(setId, slot)

            if usableSource then
                -- got usable source
                table.insert(appearances, {collected = true, appearanceID = usableSource.sourceID})
            elseif fallbackToHidden then
                -- hidden fallback
                table.insert(appearances, {collected = true, appearanceID = setLoader.getSourceIdForHiddenSlot(slot)})
            end
        end
    end)

    return appearances
end

function setLoader.getSourceIdForHiddenSlot(slot)
    return (select(2, C_TransmogCollection.GetItemInfo(hiddenItemMap[slot])))
end

function setLoader.getUsableSetSlotSource(setId, slot)
    if usableSetSlotSourceCache[setId] and usableSetSlotSourceCache[setId][slot] then
        return usableSetSlotSourceCache[setId][slot]
    end

    for _, sourceId in ipairs(private.getSetSlotSourceIds(setId, slot)) do
        local sourceInfo, isPending = sourceLoader.getInfo(sourceId, true)

        if sourceInfo and sourceInfo.useErrorType == nil then
            if isPending then
                sourceInfo = CopyTable(sourceInfo, true)
                sourceInfo.name = '' -- needed to make WardrobeSetsTransmogMixin:LoadSet() happy
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

function private.getCurrentClassMask()
    local classId = select(3, UnitClass('player'))

    if config.db.showExtraSets then
        return armorTypeClassMasks[classId]
    end

    return classMasks[classId]
end

function private.validateSet(setId)
    -- if true then return setId == 2162 end

    if validSetCache[setId] == nil then
        local valid = false

        for _, appearanceInfo in ipairs(setLoader.getSetPrimaryAppearancesCached(setId)) do
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
    for _, appearanceInfo in ipairs(setLoader.getSetPrimaryAppearancesCached(setId)) do
        local sourceInfo = sourceLoader.getInfo(appearanceInfo.appearanceID)

        if sourceInfo then
            local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)

            if (callback(slot, sourceInfo) == false) then
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

            for _, sourceInfo in ipairs(overrides.callOriginal('GetSourcesForSlot', setId, slot)) do
                if sourceInfo.isCollected then
                    sourceMap[sourceInfo.sourceID] = true
                end
            end

            for _, sourceInfo in ipairs(C_TransmogCollection.GetAppearanceSources(
                primarySourceInfo.visualID,
                C_TransmogCollection.GetCategoryForItem(primarySourceInfo.sourceID),
                TransmogUtil.GetTransmogLocation(
                    slot,
                    Enum.TransmogType.Appearance,
                    Enum.TransmogModification.Main
                )
            ) or {}) do
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
