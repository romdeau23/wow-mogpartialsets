---@class Addon
local addon = select(2, ...)

---@generic T
---@alias Packed<T> {n: integer, [integer]: T}

---@generic T
---@param ... T
---@return Packed<T>
function addon.pack(...)
    return {n = select('#', ...), ...}
end
