local _, addon = ...
local sourceLoader, private = addon.module('sourceLoader')
local overrides = addon.require('overrides');
local cache = {} -- sourceId => entry
local PENDING_TIMEOUT = 10

function sourceLoader.init()
    addon.on('TRANSMOG_COLLECTION_SOURCE_ADDED', private.onSourceAddedOrRemoved)
    addon.on('TRANSMOG_COLLECTION_SOURCE_REMOVED', private.onSourceAddedOrRemoved)
end

function sourceLoader.getInfo(sourceId, reloadPending)
    local entry = cache[sourceId] or private.createEntry(sourceId)

    if not entry.valid then
        return nil, false
    end

    if reloadPending and entry.pending then
        private.reloadEntry(entry)
    end

    return entry.info, entry.pending
end

function sourceLoader.clearCache()
    cache = {}
end

function private.createEntry(sourceId)
    local info = overrides.callOriginal('GetSourceInfo', sourceId)
    local entry

    if info then
        entry = {
            valid = true,
            info = info,
            firstLoadTime = GetTime(),
            pending = info.name == nil,
        }
    else
        entry = {valid = false}
    end

    cache[sourceId] = entry

    return entry
end

function private.reloadEntry(entry)
    if GetTime() - entry.firstLoadTime >= PENDING_TIMEOUT then
        entry.pending = false
        entry.info.name = '' -- fake a loaded info 🤷
        return
    end

    local info = overrides.callOriginal('GetSourceInfo', entry.info.sourceID)

    if info then
        entry.info = info
        entry.pending = info.name == nil
    end
end

function private.onSourceAddedOrRemoved(sourceId)
    cache[sourceId] = nil
end
