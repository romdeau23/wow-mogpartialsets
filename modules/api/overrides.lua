local _, addon = ...
local overrides, private = addon.module('api', 'overrides')
local helpers = addon.require('api', 'helpers')
local config = addon.require('config')
local apis = {}
local gettingUsableSets = false
local updatingSets = false
local loadingSet = false

function overrides.prepareGlobal()
    private.prepare(C_TransmogSets, 'HasUsableSets')
    private.prepare(C_TransmogSets, 'GetUsableSets')
    private.prepare(C_TransmogSets, 'GetSetPrimaryAppearances')
    private.prepare(C_TransmogSets, 'GetSetInfo')
    private.prepare(C_TransmogSets, 'GetSourcesForSlot')
    private.prepare(C_TransmogSets, 'GetSourceIDsForSlot')
    private.prepare(C_TransmogCollection, 'GetSourceInfo')
end

function overrides.prepareWardrobe()
    private.prepare(WardrobeCollectionFrame.SetsTransmogFrame, 'UpdateSets')
    private.prepare(WardrobeCollectionFrame.SetsTransmogFrame, 'LoadSet')
    private.prepare(WardrobeCollectionFrame.SetsTransmogFrame, 'Refresh', 'RefreshSets')
end

function overrides.enable()
    private.override('HasUsableSets', private.hasUsableSets)
    private.override('GetUsableSets', private.getUsableSets)
    private.override('GetSetPrimaryAppearances', private.getSetPrimaryAppearances)
    private.override('GetSetInfo', private.getSetInfo)
    private.override('GetSourcesForSlot', private.getSourcesForSlot)
    private.override('GetSourceIDsForSlot', private.getSourceIdsForSlot)
    private.override('GetSourceInfo', private.getSourceInfo)
    private.override('UpdateSets', private.updateSets)
    private.override('LoadSet', private.loadSet)
    private.override('RefreshSets', private.refreshSets)
end

function overrides.callOriginal(identifier, ...)
    return apis[identifier].original(...)
end

function private.prepare(apiTable, method, identifier)
    apis[identifier or method] = {
        apiTable = apiTable,
        method = method,
        original = apiTable[method],
    }
end

function private.override(identifier, newFunc)
    apis[identifier].apiTable[apis[identifier].method] = newFunc
end

function private.hasUsableSets()
    return overrides.callOriginal('HasUsableSets') or #C_TransmogSets.GetUsableSets() > 0
end

function private.getUsableSets()
    local search
    local hasSearch = false

    if addon.ui.isTransmogrifyingSets() then
        search = helpers.normalizeSearchString(WardrobeCollectionFrameSearchBox:GetText())
        hasSearch = #search > 0
    end

    local usableSets = {}
    gettingUsableSets = true

    addon.tryFinally(
        function ()
            local setFilter

            if not config.db.showExtraSets then
                local currentClassFlag = 2 ^ (select(3, UnitClass('player')) - 1) -- bitmask: 1=Warrior, 2=Paladin, 4=Hunter, 8=Rogue, ...

                setFilter = function (set)
                    return bit.band(set.classMask, currentClassFlag) == currentClassFlag
                end
            end

            local sets = helpers.getAvailableSets(setFilter)

            for _, set in pairs(sets) do
                local collectedSlots, totalSlots = helpers.getSetProgress(set.setID)

                if
                    totalSlots
                    and collectedSlots > 0
                    and (totalSlots - collectedSlots) <= config.db.maxMissingPieces
                    and (
                        not config.db.onlyFavorite
                        or (
                            set.favorite
                            or config.db.favoriteVariants and helpers.setHasFavoriteVariant(set, sets)
                        )
                    )
                    and (
                        not hasSearch
                        or helpers.stringMatchesSearch(set.name, search)
                        or set.label ~= nil and helpers.stringMatchesSearch(set.label, search)
                    )
                then
                    set.collected = true

                    table.insert(usableSets, set)
                else
                    set.collected = false
                end
            end
        end,
        function ()
            gettingUsableSets = false
        end
    )

    return usableSets
end

function private.getSetPrimaryAppearances(setId)
    -- return only applicable apperances when loading a set or updating the list
    if private.shouldReturnModifiedSets() then
        return helpers.getApplicableSetAppearances(setId)
    end

    -- return original sources
    return helpers.getSetPrimaryAppearancesCached(setId)
end

function private.getSetInfo(setId)
    local set = overrides.callOriginal('GetSetInfo', setId)

    if set and addon.ui.isTransmogrifyingSets() then
        local collectedSlots, totalSlots = helpers.getSetProgress(setId)

        if totalSlots then
            set.label = string.format(
                '%s\n|cff808080(collected:|r |c%s%d/%d|cff808080)|r',
                set.label or '',
                helpers.getSetProgressColor(collectedSlots, totalSlots),
                collectedSlots,
                totalSlots
             )
        end
    end

    return set
end

function private.getSourcesForSlot(setId, slot)
    -- use hidden item if this slot is always hidden
    if private.shouldReturnModifiedSets() and config.isHiddenSlot(slot) then
        return {overrides.callOriginal('GetSourceInfo', helpers.getSourceIdForHiddenSlot(slot))}
    end

    -- get sources from original API
    local slotSources = overrides.callOriginal('GetSourcesForSlot', setId, slot)

    if not addon.ui.isTransmogrifyingSets() then
        return slotSources
    end

    local hasCollectedSource = false

    for _, sourceInfo in ipairs(slotSources) do
        if sourceInfo.isCollected and sourceInfo.useError == nil then
            hasCollectedSource = true
            break
        end
    end

    -- return if there are any collected sources
    if hasCollectedSource then
        return slotSources
    end

    -- try to add alternative sources
    local hasAltSource = false

    for _, appearance in pairs(helpers.getCollectedSetAppearances(setId)) do
        local sourceInfo =  overrides.callOriginal('GetSourceInfo', appearance.appearanceID)

        if sourceInfo and C_Transmog.GetSlotForInventoryType(sourceInfo.invType) == slot then
            table.insert(slotSources, sourceInfo)
            hasAltSource = true
            break
        end
    end

    -- fallback to hidden item if possible
    if not hasAltSource and helpers.canHideSlot(slot) then
        table.insert(slotSources, overrides.callOriginal('GetSourceInfo', helpers.getSourceIdForHiddenSlot(slot)))
    end

    return slotSources
end

function private.getSourceIdsForSlot(setId, slot)
    local sourceIds = {}

    for _, sourceInfo in ipairs(C_TransmogSets.GetSourcesForSlot(setId, slot)) do
        table.insert(sourceIds, sourceInfo.sourceID)
    end

    return sourceIds
end

function private.getSourceInfo(sourceId)
    local source = overrides.callOriginal('GetSourceInfo', sourceId)

    -- fill in missing quality on few set items so set tooltips don't get stuck on "retrieving item information"
    if source and source.quality == nil and addon.ui.isTransmogrifyingSets() then
        source.quality = 4 -- assume epic
    end

    return source
end

function private.updateSets(frame)
    addon.tryFinally(
        function ()
            updatingSets = true
            overrides.callOriginal('UpdateSets', frame)
        end,
        function ()
            updatingSets = false
        end
    )
end

function private.loadSet(frame, setId)
    addon.tryFinally(
        function ()
            loadingSet = true
            overrides.callOriginal('LoadSet', frame, setId)
        end,
        function ()
            loadingSet = false
        end
    )
end

function private.refreshSets(frame)
    overrides.callOriginal('RefreshSets', frame, false) -- don't reset
end

function private.shouldReturnModifiedSets()
    return not gettingUsableSets and (updatingSets or loadingSet) and addon.ui.isTransmogrifyingSets()
end
