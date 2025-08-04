local _, addon = ...
local config, private = addon.module('config'), {}
local latestVersion = 10

function config.init()
    if MogPartialSetsAddonConfig then
        -- try to load and migrate existing config
        config.db = MogPartialSetsAddonConfig

        local success, result = pcall(private.migrateConfiguration)

        if not success then
            -- reset config on migration error
            private.loadDefaultConfig()
            CallErrorHandler(result)
        end
    else
        -- no config data yet - load default
        private.loadDefaultConfig()
    end
end

function config.isIgnoredSlot(invType)
    return config.db.ignoredSlotMap[invType] ~= nil
end

function config.setIgnoredSlot(invType, isIgnored)
    if isIgnored then
        config.db.ignoredSlotMap[invType] = true
    else
        config.db.ignoredSlotMap[invType] = nil
    end
end

function config.isHiddenSlot(invType)
    return config.db.hiddenSlotMap[invType] ~= nil
end

function config.setHiddenSlot(invType, isIgnored)
    if isIgnored then
        config.db.hiddenSlotMap[invType] = true
    else
        config.db.hiddenSlotMap[invType] = nil
    end
end

function private.loadDefaultConfig()
    MogPartialSetsAddonConfig = private.getDefaultConfig()
    config.db = MogPartialSetsAddonConfig
end

function private.getDefaultConfig()
    return {
        version = latestVersion,
        showExtraSets = true,
        maxMissingPieces = 2,
        onlyFavorite = false,
        favoriteVariants = false,
        useHiddenIfMissing = true,
        hideItemsNotInSet = true,
        ignoredSlotMap = {
            [INVSLOT_BACK] = true,
            [INVSLOT_WRIST] = true,
        },
        hiddenSlotMap = {},
    }
end

function private.migrateConfiguration()
    for to = config.db.version + 1, latestVersion do
        private.migrations[to]()
    end

    config.db.version = latestVersion
end

private.migrations = {
    -- pre-v7 not supported anymore
    [7] = function ()
        config.db.splash = true
    end,

    [8] = function ()
        config.db.splash = nil
    end,

    [9] = function ()
        config.db.showExtraSets = config.db.enabled
        config.db.enabled = nil
        config.db.useHiddenIfMissing = true
        config.db.hiddenSlotMap = {}

        -- convert ignored slots from Enum.InventoryType to inventory slots
        local newIgnoredSlotMap = {}

        for invTypeEnumValue, flag in pairs(config.db.ignoredSlotMap) do
            newIgnoredSlotMap[C_Transmog.GetSlotForInventoryType(invTypeEnumValue + 1)] = true
        end

        config.db.ignoredSlotMap = newIgnoredSlotMap
    end,

    [10] = function ()
        config.db.hideItemsNotInSet = config.db.useHiddenIfMissing
    end,
}
