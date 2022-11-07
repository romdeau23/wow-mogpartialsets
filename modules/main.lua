local _, addon = ...
local main, private = addon.module('main')
local initialized = false

function main.init()
    addon.api.overrides.prepareGlobal()
    addon.on('TRANSMOGRIFY_UPDATE', private.onTransmogrifyAction)
    addon.on('TRANSMOGRIFY_OPEN', private.onTransmogrifyAction)
end

function private.onTransmogrifyAction()
    if not initialized and WardrobeCollectionFrame then
        addon.api.overrides.prepareWardrobe()
        addon.api.overrides.enable()
        addon.ui.attach()
        initialized = true
    end

    return not initialized
end
