local R_table = require "lib.table"

--- Creates a read-only proxy for a table
--- @param tbl table  The table to create a read-only proxy for
--- @return table
local function proxy(tbl)
    return setmetatable({}, {
        __index = function(self, key) return tbl[key] end,
        __newindex = function(self, key, value) error("Attempted to modify read-only table", 2) end,
        __pairs = function(self) return pairs(tbl) end,
        __ipairs = R_table.create_ipairs(tbl),
        __len = function(self) return #tbl end
    })
end

return {
    proxy = proxy
}