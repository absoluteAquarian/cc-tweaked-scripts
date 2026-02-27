local R_table = require "lib.table"
local trace = require "lib.trace"

--- Creates a read-only proxy for a table
--- @param tbl table  The table to create a read-only proxy for
--- @return table
local function proxy(tbl)
    --- @type table
    return setmetatable({}, {
        __index = trace.wrap(function(self, key) return tbl[key] end),
        __newindex = trace.wrap(function(self, key, value) error("Attempted to modify read-only table", 2) end),
        __pairs = trace.wrap(function(self) return pairs(tbl) end),
        __ipairs = trace.wrap(R_table.create_ipairs(tbl)),
        __len = trace.wrap(function(self) return #tbl end)
    })
end

return {
    proxy = proxy
}