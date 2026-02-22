---@class Addon
local addon = select(2, ...)
addon.event = addon.createObservable()
