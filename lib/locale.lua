---@class Addon
local addon = select(2, ...)

---@class LocaleModule
local locale = addon.module()
addon.locale = locale

local translations = {}
local currentLocale = GetLocale()

---Register translations for a locale
---@param localeCode string The locale code (e.g., "enUS", "zhCN")
---@param strings table<string, string> The translation strings
function locale.register(localeCode, strings)
    translations[localeCode] = strings
end

---Get a localized string
---@param key string The translation key
---@return string The localized string or the key if not found
function locale.get(key)
    local localeStrings = translations[currentLocale]
    
    if localeStrings and localeStrings[key] then
        return localeStrings[key]
    end
    
    -- Fallback to enUS
    local fallbackStrings = translations["enUS"]
    if fallbackStrings and fallbackStrings[key] then
        return fallbackStrings[key]
    end
    
    -- Return the key if no translation found
    return key
end

-- Shorthand function
local L = locale.get
addon.L = L
