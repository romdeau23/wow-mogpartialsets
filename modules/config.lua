---@class Addon
local addon = select(2, ...)
---@class ConfigModule
local config, private = addon.module('config'), {}
---@type ConfigModule.Config
local configVar
---@type ConfigModule.Profile
local profileVar
---@type ConfigModule.Slots
local effectiveSlots

---@class (exact) ConfigModule.Config
---@field showExtraSets boolean
---@field maxMissingPieces integer
---@field onlyFavorite boolean
---@field favoriteVariants boolean
---@field hideItemsNotInSet boolean
---@field slots ConfigModule.Slots

---@class (exact) ConfigModule.Profile
---@field enabled boolean
---@field slots ConfigModule.Slots?

---@class (exact) ConfigModule.Slots
---@field ignored table<number, true>
---@field skipped table<number, true>
---@field hidden table<number, true>

---@type ConfigModule.Slots
local DEFAULT_SLOTS = {
    ignored = {
        [INVSLOT_BACK] = true,
        [INVSLOT_WRIST] = true,
    },
    skipped = {},
    hidden = {},
}

---@type ConfigModule.Config
local DEFAULT_CONFIG = {
    showExtraSets = true,
    onlyFavorite = false,
    favoriteVariants = false,
    hideItemsNotInSet = true,
    maxMissingPieces = 2,
    slots = DEFAULT_SLOTS,
}

---@type ConfigModule.Profile
local DEFAULT_PROFILE = {
    enabled = false,
    slots = nil,
}

function config.init()
    configVar = addon.loadSavedVar(
        'MogPartialSetsAddonConfig',
        11,
        DEFAULT_CONFIG,
        private.configMigrations
    )

    profileVar = addon.loadSavedVar(
        'MogPartialSetsAddonProfile',
        1,
        DEFAULT_PROFILE,
        private.profileMigrations
    )

    private.setEffectiveSlots()

    config.ignoredSlots = private.createSlotMap('ignored')
    config.skippedSlots = private.createSlotMap('skipped')
    config.hiddenSlots = private.createSlotMap('hidden')
end

---@return boolean
function config.showExtraSets()
    return configVar.showExtraSets
end

---@param value boolean
function config.setShowExtraSets(value)
    configVar.showExtraSets = value
    private.dispatchUpdate()
end

---@return boolean
function config.onlyFavorite()
    return configVar.onlyFavorite
end

---@param value boolean
function config.setOnlyFavorite(value)
    configVar.onlyFavorite = value
    private.dispatchUpdate()
end

---@return boolean
function config.favoriteVariants()
    return configVar.favoriteVariants
end

---@param value boolean
function config.setFavoriteVariants(value)
    configVar.favoriteVariants = value
    private.dispatchUpdate()
end

---@return boolean
function config.hideItemsNotInSet()
    return configVar.hideItemsNotInSet
end

---@param value boolean
function config.setHideItemsNotInSet(value)
    configVar.hideItemsNotInSet = value
    private.dispatchUpdate()
end

---@return integer
function config.maxMissingPieces()
    return configVar.maxMissingPieces
end

---@param value integer
function config.setMaxMissingPieces(value)
    configVar.maxMissingPieces = value
    private.dispatchUpdate()
end

---@return boolean
function config.characterProfileEnabled()
    return profileVar.enabled
end

---@param value boolean
function config.setCharacterProfileEnabled(value)
    profileVar.enabled = value
    private.setEffectiveSlots()
    private.dispatchUpdate()
end

function private.setEffectiveSlots()
    if profileVar.enabled then
        if not profileVar.slots then
            profileVar.slots = CopyTable(configVar.slots)
        end

        effectiveSlots = profileVar.slots
    else
        effectiveSlots = configVar.slots
    end
end

---@param key string
---@return ConfigModule.SlotMap
function private.createSlotMap(key)
    ---@class ConfigModule.SlotMap
    local map = {}

    ---@param invSlotId number
    ---@return boolean
    function map.has(invSlotId)
        return effectiveSlots[key][invSlotId] ~= nil
    end

    ---@return table<number, true> (copy)
    function map.getMap()
        return CopyTable(effectiveSlots[key])
    end

    ---@param invSlotId number
    ---@param enabled boolean
    function map.set(invSlotId, enabled)
        effectiveSlots[key][invSlotId] = enabled and true or nil
        private.dispatchUpdate()
    end

    function map.clear()
        effectiveSlots[key] = {}
        private.dispatchUpdate()
    end

    return map
end

---@type table<integer, fun(data: table)>
private.configMigrations = {
    -- pre-v7 not supported anymore
    [7] = function (data)
        data.splash = true
    end,

    [8] = function (data)
        data.splash = nil
    end,

    [9] = function (data)
        data.showExtraSets = data.enabled
        data.enabled = nil
        data.useHiddenIfMissing = true
        data.hiddenSlotMap = {}

        -- convert ignored slots from Enum.InventoryType to inventory slots
        local newIgnoredSlotMap = {}

        for invTypeEnumValue in pairs(data.ignoredSlotMap) do
            newIgnoredSlotMap[C_Transmog.GetSlotForInventoryType(invTypeEnumValue + 1)] = true
        end

        data.ignoredSlotMap = newIgnoredSlotMap
    end,

    [10] = function (data)
        data.hideItemsNotInSet = data.useHiddenIfMissing
    end,

    [11] = function (data)
        data.slots = {
            ignored = data.ignoredSlotMap,
            skipped = {},
            hidden = data.hiddenSlotMap,
        } --[[@as ConfigModule.Slots]]

        data.useHiddenIfMissing = nil
        data.ignoredSlotMap = nil
        data.hiddenSlotMap = nil
    end
}

---@type table<integer, fun(data: table)>
private.profileMigrations = {
    -- none yet
}

private.dispatchUpdate = addon.debounce(0.1, function ()
    addon.event.dispatch('config.update')
end)
