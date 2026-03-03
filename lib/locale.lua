---@class Addon
local addon = select(2, ...)

---@class LocaleModule
local locale = addon.module()
addon.locale = locale

local translations = {}
local currentLocale = GetLocale()

---@param localeCode string the locale code (e.g., 'enUS', 'zhCN')
---@param strings table<string, string> the translation strings
function locale.register(localeCode, strings)
    translations[localeCode] = strings
end

---@param key string the translation key
---@return string # the localized string or the key if not found
function locale.get(key)
    return (
        translations[currentLocale] and translations[currentLocale][key]
        or translations['enUS'][key] -- fallback to enUS
        or key -- translation not found
    )
end

-- shortcut
addon.L = locale.get
