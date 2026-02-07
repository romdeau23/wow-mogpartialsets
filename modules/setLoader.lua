---@class Addon
local addon = select(2, ...)
---@class SetLoaderModule
local setLoader, private = addon.module('setLoader'), {}

---@type SetLoaderModule.SetMap
local loadedSets = {}

---@type QueueWorkerLib.Worker
local loadSetWorker
local loadSetWorkerFrameTimeLimit = 0.005
local loadSetWorkerUpdateFreq = 0.25
---@type number?
local loadSetWorkerBusySince

---@type table<number, SetLoaderModule.PendingSourceInfo>
local pendingSourceMap = {}
local pendingSourceTimeoutSecs = 10.0

local updateDebounce = 0.5
---@type number?
local lastUpdate

---@class SetLoaderModule.Set
---@field info TransmogSetInfo
---@field slots SetLoaderModule.SlotMap

---@class SetLoaderModule.Slot
---@field invSlotId number
---@field sources SetLoaderModule.SourceMap
---@field primarySourceId number
---@field usableSourceId number?

---@class SetLoaderModule.Source
---@field sourceId number
---@field usable boolean
---@field pending boolean

---@class SetLoaderModule.PendingSourceInfo
---@field sourceId number
---@field invSlotId number
---@field firstFetchedAt number
---@field sets table<number, true>

---@alias SetLoaderModule.SetMap table<number, SetLoaderModule.Set>
---@alias SetLoaderModule.SlotMap table<number, SetLoaderModule.Slot>
---@alias SetLoaderModule.SourceMap table<number, SetLoaderModule.Source>

function setLoader.init()
    loadSetWorker = addon.createQueueWorker(
        private.loadSet,
        private.onLoadSetWorkerUpdate,
        loadSetWorkerFrameTimeLimit,
        loadSetWorkerUpdateFreq
    )
end

function setLoader.hook()
    addon.on('TRANSMOG_COLLECTION_ITEM_UPDATE', private.onItemUpdate)
    addon.on('TRANSMOG_COLLECTION_SOURCE_ADDED', private.onSourceAddedOrRemoved)
    addon.on('TRANSMOG_COLLECTION_SOURCE_REMOVED', private.onSourceAddedOrRemoved)
    addon.on('TRANSMOG_SETS_UPDATE_FAVORITE', private.onFavoritesUpdated)
end

--- @param setId number
--- @return SetLoaderModule.Set?
function setLoader.getSet(setId)
    if not loadedSets[setId] then
        local setInfo = C_TransmogSets.GetSetInfo(setId)

        if not setInfo then
            return nil
        end

        return private.loadSet(setInfo)
    end

    return loadedSets[setId]
end

---@param classMask integer
---@return SetLoaderModule.SetMap
function setLoader.getAllSets(classMask)
    local sets = {}
    local faction = UnitFactionGroup('player')

    for _, setInfo in ipairs(C_TransmogSets.GetAllSets()) do
        if
            -- match class
            (setInfo.classMask == 0 or bit.band(setInfo.classMask, classMask) ~= 0)
            -- match faction
            and (not setInfo.requiredFaction or setInfo.requiredFaction == faction)
        then
            local setId = setInfo.setID
            sets[setId] = loadedSets[setId] or loadSetWorker.add(setId, setInfo)
        end
    end

    return sets
end

---@return SetLoaderModule.SetMap
function setLoader.getAvailableSets()
    local sets = {}

    for _, setInfo in ipairs(C_TransmogSets.GetAvailableSets()) do
        local setId = setInfo.setID
        sets[setId] = loadedSets[setId] or loadSetWorker.add(setId, setInfo)
    end

    return sets
end

function setLoader.clearSetData()
    loadedSets = {}
    pendingSourceMap = {}
end

function setLoader.isLoading()
    return loadSetWorker.busy()
end

function setLoader.updatePerformance()
    local frameTimeLimit
    local fps = GetFramerate()

    if fps >= 90 then
        frameTimeLimit = 0.008
    elseif fps >= 60 then
        frameTimeLimit = 0.005
    else
        frameTimeLimit = 0.003
    end

    loadSetWorker.setFrameTimeLimit(frameTimeLimit)
end

---@param setInfo TransmogSetInfo
---@return SetLoaderModule.Set
function private.loadSet(setInfo)
    local set = private.createSet(setInfo)
    loadedSets[setInfo.setID] = set

    return set
end

---@param setInfo TransmogSetInfo
---@return SetLoaderModule.Set
function private.createSet(setInfo)
    local set = {
        info = setInfo,
        slots = private.loadSlots(setInfo.setID),
    }

    for invSlotId, slot in pairs(set.slots) do
        if not slot.usableSourceId then
            -- unusable slot, keep track of any pending sources
            for sourceId, source in pairs(slot.sources) do
                if source.pending then
                    if pendingSourceMap[sourceId] then
                        pendingSourceMap[sourceId].sets[setInfo.setID] = true
                    else
                        pendingSourceMap[sourceId] = {
                            sourceId = sourceId,
                            invSlotId = invSlotId,
                            firstFetchedAt = GetTime(),
                            sets = {[setInfo.setID] = true},
                        }
                    end
                end
            end
        end
    end

    return set
end

---@param setId number
---@return SetLoaderModule.SlotMap
function private.loadSlots(setId)
    ---@type SetLoaderModule.SlotMap
    local slots = {}

    for _, appearance in ipairs(C_TransmogSets.GetSetPrimaryAppearances(setId) or {}) do
        local sourceInfo = C_TransmogCollection.GetSourceInfo(appearance.appearanceID)

        if sourceInfo then
            local invSlotId = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)

            if invSlotId then
                if not slots[invSlotId] then
                    local sources = private.loadSources(setId, invSlotId, sourceInfo)
                    local usableSourceId

                    for sourceId, source in pairs(sources) do
                        if source.usable then
                            usableSourceId = sourceId
                            break
                        end
                    end

                    slots[invSlotId] = {
                        invSlotId = invSlotId,
                        sources = sources,
                        primarySourceId = appearance.appearanceID,
                        usableSourceId = usableSourceId,
                    }
                else
                    -- sets with multiple primary apperances per slot exist, but are rare
                    -- append any new sources from that appearance in this case
                    local slot = slots[invSlotId]

                    for sourceId, source in pairs(private.loadSources(setId, invSlotId, sourceInfo)) do
                        if not slot.sources[sourceId] then
                            slot.sources[sourceId] = source

                            if source.usable and not slot.usableSourceId then
                                slot.usableSourceId = source.sourceId
                            end
                        end
                    end
                end
            end
        end
    end

    return slots
end

---@param setId number
---@param invSlotId number
---@param primarySourceInfo AppearanceSourceInfo
---@return SetLoaderModule.SourceMap
function private.loadSources(setId, invSlotId, primarySourceInfo)
    local sources = {}

    -- add primary source
    if primarySourceInfo.isCollected then
        sources[primarySourceInfo.sourceID] = private.createSource(primarySourceInfo)
    end

    -- add "official" sources
    for _, sourceInfo in ipairs(C_TransmogSets.GetSourcesForSlot(setId, invSlotId) or {}) do
        if sourceInfo.isCollected and not sources[sourceInfo.sourceID] then
            sources[sourceInfo.sourceID] = private.createSource(sourceInfo)
        end
    end

    -- add "lookalikes"
    local lookalikes = C_TransmogCollection.GetAppearanceSources(
        primarySourceInfo.visualID,
        C_TransmogCollection.GetCategoryForItem(primarySourceInfo.sourceID),
        TransmogUtil.GetTransmogLocation(
            invSlotId,
            Enum.TransmogType.Appearance,
            Enum.TransmogModification.Main
        )
    )

    for _, sourceInfo in ipairs(lookalikes or {}) do
        if sourceInfo.isCollected and not sources[sourceInfo.sourceID] then
            sources[sourceInfo.sourceID] = private.createSource(sourceInfo)
        end
    end

    return sources
end

---@param sourceInfo AppearanceSourceInfo
---@return SetLoaderModule.Source
function private.createSource(sourceInfo)
    local pending = (sourceInfo.name == nil)

    return {
        sourceId = sourceInfo.sourceID,
        usable = not pending and private.isUsableSource(sourceInfo),
        pending = pending,
    }
end

---@param source AppearanceSourceInfo
---@return boolean
function private.isUsableSource(source)
    return (
        (source.useErrorType == Enum.TransmogUseErrorType.None or source.useErrorType == nil)
        and source.isValidSourceForPlayer ~= false
        and source.canDisplayOnPlayer ~= false
        and source.meetsTransmogPlayerCondition ~= false
    )
end

function private.onItemUpdate()
    if next(pendingSourceMap) == nil then
        return -- nothing to do
    end

    local newPendingSourceMap = {}
    local skippedSourceMap = {}
    local setsChanged = false
    local now = GetTime()

    for sourceId, info in pairs(pendingSourceMap) do
        if not skippedSourceMap[sourceId] then
            local result, setUsableSlotsChanged = private.checkPendingSource(info, now)

            if result == 'pending' then
                -- still pending - check again later
                newPendingSourceMap[sourceId] = info
            elseif result == 'timeout' then
                -- timeout - don't try to load again
                -- (some sources are broken and just never load, but trying to triggers TRANSMOG_COLLECTION_ITEM_UPDATE again = loop)
            elseif result == 'loaded' then
                -- loaded
                if setUsableSlotsChanged then
                    setsChanged = true

                    -- given that this source is now loaded and usable, we don't need to check
                    -- any other pending sources for that slot in all affected sets
                    for setId in pairs(info.sets) do
                        local set = loadedSets[setId]
                        assert(set)
                        local slot = set.slots[info.invSlotId]
                        assert(slot)

                        for slotSourceId, source in pairs(slot.sources) do
                            if slotSourceId ~= sourceId and source.pending and pendingSourceMap[slotSourceId] then
                                -- other pending source is in pendingSourceMap, unmap this set from it
                                local hasOtherSets = private.unmapSetFromPendingSource(slotSourceId, setId)

                                if not hasOtherSets then
                                    -- no sets are waiting for this source now, we can safely skip it fully
                                    skippedSourceMap[slotSourceId] = true
                                end
                            end
                        end
                    end
                end
            else
                error('Unexpected result: ' .. result)
            end
        end
    end

    pendingSourceMap = newPendingSourceMap

    if setsChanged then
        private.dispatchUpdateDebounced()
    end
end

---@param info SetLoaderModule.PendingSourceInfo
---@param now number
---@return 'pending'|'timeout'|'loaded' result
---@return boolean? setUsableSlotsChanged
function private.checkPendingSource(info, now)
    if now - info.firstFetchedAt >= pendingSourceTimeoutSecs then
        return 'timeout'
    end

    local sourceInfo = C_TransmogCollection.GetSourceInfo(info.sourceId)

    if not sourceInfo or sourceInfo.name == nil then
        return 'pending'
    end

    local usable = private.isUsableSource(sourceInfo)
    local setUsableSlotsChanged = false

    for setId in pairs(info.sets) do
        local set = loadedSets[setId]
        assert(set)
        local slot = set.slots[info.invSlotId]
        assert(slot)
        local source = slot.sources[info.sourceId]
        assert(source)

        source.usable = usable
        source.pending = false

        if usable and not slot.usableSourceId then
            slot.usableSourceId = info.sourceId
            setUsableSlotsChanged = true
        end
    end

    return 'loaded', setUsableSlotsChanged
end

---@param sourceId number
---@param setId number
---@return boolean hasOtherSets
function private.unmapSetFromPendingSource(sourceId, setId)
    pendingSourceMap[sourceId].sets[setId] = nil

    return next(pendingSourceMap[sourceId].sets) ~= nil
end

---@param sourceId  number
function private.onSourceAddedOrRemoved(sourceId)
    -- clear pending state
    pendingSourceMap[sourceId] = nil

    -- re-load affected sets
    for _, setId in ipairs(C_TransmogSets.GetSetsContainingSourceID(sourceId) or {}) do
        if loadedSets[setId] then
            local setInfo = C_TransmogSets.GetSetInfo(setId)

            if setInfo then
                loadedSets[setId] = loadSetWorker.add(setId, setInfo)
            end
        end
    end
end

function private.onFavoritesUpdated()
    -- no payload, so have to iterate all sets
    for setId, set in pairs(loadedSets) do
        local setInfo = C_TransmogSets.GetSetInfo(setId)

        if setInfo then
            set.info.favorite = setInfo.favorite
        end
    end
end

function private.onLoadSetWorkerUpdate()
    if not loadSetWorker.busy() then
        -- loading just completed, update immediately
        loadSetWorkerBusySince = nil
        private.dispatchUpdate()

        return
    end

    -- still some sets left to load
    local now = GetTime()

    if not loadSetWorkerBusySince then
        loadSetWorkerBusySince = math.max(0, now - loadSetWorkerUpdateFreq)
    end

    -- if the loading process takes more than a second to finish, start updating at least once a second
    if
        now - loadSetWorkerBusySince > 1
        and (
            not lastUpdate
            or now - lastUpdate >= 1
        )
    then
        private.dispatchUpdate()
    end
end

function private.dispatchUpdate()
    lastUpdate = GetTime()
    addon.event.dispatch('setLoader.update')
end

private.dispatchUpdateDebounced = addon.debounce(updateDebounce, function ()
    if not loadSetWorker.busy() then
        private.dispatchUpdate()
    end
end)
