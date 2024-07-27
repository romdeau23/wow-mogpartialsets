local _, addon = ...
local overrides, private = addon.module('overrides')
local setLoader = addon.require('setLoader')
local sourceLoader = addon.require('sourceLoader')
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
        search = setLoader.normalizeSearchString(WardrobeCollectionFrameSearchBox:GetText())
        hasSearch = #search > 0
    end

    local usableSets = {}
    gettingUsableSets = true

    addon.tryFinally(
        function ()
            local sets = setLoader.getAvailableSets()

            for _, set in pairs(sets) do
                local collectedSlots, totalSlots = setLoader.getSetProgress(set.setID)

                if
                    collectedSlots > 0
                    and (totalSlots - collectedSlots) <= config.db.maxMissingPieces
                    and (
                        not config.db.onlyFavorite
                        or (
                            set.favorite
                            or config.db.favoriteVariants and setLoader.setHasFavoriteVariant(set, sets)
                        )
                    )
                    and (
                        not hasSearch
                        or setLoader.stringMatchesSearch(set.name, search)
                        or set.label ~= nil and setLoader.stringMatchesSearch(set.label, search)
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
        return setLoader.getApplicableSetAppearances(setId, updatingSets or loadingSet and config.db.useHiddenIfMissing)
    end

    -- return original sources
    return setLoader.getSetPrimaryAppearancesCached(setId)
end

function private.getSetInfo(setId)
    local set = overrides.callOriginal('GetSetInfo', setId)

    if set and addon.ui.isTransmogrifyingSets() then
        local collectedSlots, totalSlots = setLoader.getSetProgress(setId)

        if totalSlots then
            local parts = {}

            if set.label then
                table.insert(parts, set.label)
            end

            if IsAltKeyDown() then
                if set.label then
                    table.insert(parts, ' ')
                end

                table.insert(parts, string.format('(%d)', setId))
            end

            if #parts > 0 then
                table.insert(parts, '\n')
            end

            if set.description then
                table.insert(parts, string.format('|cff40c040%s|r\n', set.description))
            end

            table.insert(parts, string.format(
                '|cff808080(collected:|r |c%s%d/%d|cff808080)|r',
                setLoader.getSetProgressColor(collectedSlots, totalSlots),
                collectedSlots,
                totalSlots
            ))

            set.label = table.concat(parts)
        end
    end

    return set
end

function private.getSourcesForSlot(setId, slot)
    -- call original API if override should not be active
    if not private.shouldReturnModifiedSets() then
        return overrides.callOriginal('GetSourcesForSlot', setId, slot)
    end

    -- return hidden item if this slot is always hidden
    if config.isHiddenSlot(slot) then
        return {(sourceLoader.getInfo(setLoader.getSourceIdForHiddenSlot(slot)))}
    end

    -- try to find a usable source
    local usableSource = setLoader.getUsableSetSlotSource(setId, slot)

    if usableSource then
        return {usableSource}
    end

    -- fallback to hidden item
    return {(sourceLoader.getInfo(setLoader.getSourceIdForHiddenSlot(slot)))}
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
