local trace = require "lib.trace"

--- @param tbl table
--- @return function
--- @return table
local function create_ipairs(tbl)
    local function iter(t, i)
        i = i + 1
        local v = t[i]
        if v ~= nil then return i, v end
    end
    return iter, tbl
end

--- @param tbl table
--- @return table copy
local function deep_copy(tbl)
    local copy = {}
    for key, value in pairs(tbl) do
        if type(value) == "table" then
            copy[key] = deep_copy(value)
        else
            copy[key] = value
        end
    end

    -- Bypass "__metatable" protection
    local meta = debug.getmetatable(tbl)
    if meta then debug.setmetatable(copy, meta) end

    return copy
end

--- @param tbl table
--- @param ... any
--- @return boolean
local function has_any_value(tbl, ...)
    for _, value in ipairs(tbl) do
        for _, check in ipairs({...}) do
            if value == check then return true end
        end
    end
    return false
end

--- @param tbl table
--- @param value any
--- @return boolean
local function has_value(tbl, value)
    if not value then return false end
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

--- @param tbl table
--- @param ... any
local function remove_keys(tbl, ...)
    for key, _ in pairs(tbl) do
        for _, remove in ipairs({...}) do
            if key == remove then
                tbl[key] = nil
                break
            end
        end
    end
end

--- @param tbl table
--- @param predicate fun(key: any) : boolean
local function remove_keys_where(tbl, predicate)
    for key, _ in pairs(tbl) do
        if predicate(key) then tbl[key] = nil end
    end
end

--- @param tbl table
--- @param ... any
local function remove_values(tbl, ...)
    local removing = {}
    for index, value in ipairs(tbl) do
        for _, remove in ipairs({...}) do
            if value == remove then
                table.insert(removing, index)
                break
            end
        end
    end

    for i = #removing, 1, -1 do
        table.remove(tbl, removing[i])
    end
end

--- @param tbl table
--- @param predicate fun(value: any) : boolean
local function remove_values_where(tbl, predicate)
    local removing = {}
    for index, value in ipairs(tbl) do
        if predicate(value) then table.insert(removing, index) end
    end

    for i = #removing, 1, -1 do
        table.remove(tbl, removing[i])
    end
end

--- @param tbl table
--- @param transform fun(value: any) : any
local function transform_values(tbl, transform)
    for key, value in pairs(tbl) do
        tbl[key] = transform(value)
    end
end

--- @param tbl table
--- @return function
local function yield_pairs(tbl)
    local key, value = next(tbl)

    if not key then return function() return nil end end

    return trace.wrap(
        function()
            local current_key, current_value = key, value
            key, value = next(tbl, key)
            return current_key, current_value
        end
    )
end

--- @param tbl table
--- @return function
local function yield_ipairs(tbl)
    local index = 0
    return trace.wrap(
        function()
            index = index + 1
            local value = tbl[index]
            if value then return index, value end
        end
    )
end

return {
    --- Returns values that can be used for the "__ipairs" metamethod
    --- @param tbl table
    --- @return function
    --- @return table
    create_ipairs = function(tbl) return trace.scall(create_ipairs, tbl) end,
    --- Creates a deep copy of the given table, recursing into any subtables.  Preserves metatables.
    --- @param tbl table  The table to copy
    --- @return table copy  The generated copy of the original table
    deep_copy = function(tbl) return trace.scall(deep_copy, tbl) end,
    --- Returns whether the given table contains any of the given values
    --- @param tbl table  The table to check
    --- @param ... any  The values to check for
    --- @return boolean
    has_any_value = function(tbl, ...) return trace.scall(has_any_value, tbl, ...) end,
    --- Returns whether the given table contains the given value
    --- @param tbl table  The table to check
    --- @param value any  The value to check for
    --- @return boolean
    has_value = function(tbl, value) return trace.scall(has_value, tbl, value) end,
    --- Removes all occurrences of the given keys from the given table.  Modifies the table in-place.
    --- @param tbl table  The table to remove keys from
    --- @param ... any  The keys to remove from the table
    remove_keys = function(tbl, ...) return trace.scall(remove_keys, tbl, ...) end,
    --- Removes all occurrences of keys matching the given predicate from the given table.  Modifies the table in-place.
    --- @param tbl table  The table to remove keys from
    --- @param predicate fun(key: any) : boolean  A function that returns true for keys to remove from the table
    remove_keys_where = function(tbl, predicate) return trace.scall(remove_keys_where, tbl, predicate) end,
    --- Removes all occurrences of the given values from the given table.  Modifies the table in-place.
    --- @param tbl table  The table to remove values from
    --- @param ... any  The values to remove from the table
    remove_values = function(tbl, ...) return trace.scall(remove_values, tbl, ...) end,
    --- Removes all occurrences of values matching the given predicate from the given table.  Modifies the table in-place.
    --- @param tbl table  The table to remove values from
    --- @param predicate fun(value: any) : boolean  A function that returns true for values to remove from the table
    remove_values_where = function(tbl, predicate) return trace.scall(remove_values_where, tbl, predicate) end,
    --- Transform all values in the given table using a transform function.  Modifies the table in-place.
    --- @param tbl table  The table to transform values in
    --- @param transform fun(value: any) : any  A function that takes a value and returns the transformed value
    transform_values = function(tbl, transform) return trace.scall(transform_values, tbl, transform) end,
    --- Returns a function that iterates over all key-value pairs in the given table, once per call
    --- @param tbl table  The table to iterate over
    --- @return function
    yield_pairs = function(tbl) return trace.scall(yield_pairs, tbl) end,
    --- Returns a function that iterates over all index-value pairs in the given table, once per call
    --- @param tbl table  The table to iterate over
    --- @return function
    yield_ipairs = function(tbl) return trace.scall(yield_ipairs, tbl) end,
}