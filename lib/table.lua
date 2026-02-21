--- Returns whether the given table contains any of the given values
--- @param tbl table  The table to check
--- @param ... any  The values to check for
--- @return boolean
local function has_any_value(tbl, ...)
    for _, value in ipairs(tbl) do
        for _, check in ipairs({...}) do
            if value == check then return true end
        end
    end
    return false
end

--- Returns whether the given table contains the given value
--- @param tbl table  The table to check
--- @param value any  The value to check for
--- @return boolean
local function has_value(tbl, value)
    if not value then return false end
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

--- Removes all occurrences of the given keys from the given table.  Modifies the table in-place.
--- @param tbl table  The table to remove keys from
--- @param ... any  The keys to remove from the table
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

--- Removes all occurrences of keys matching the given predicate from the given table.  Modifies the table in-place.
--- @param tbl table  The table to remove keys from
--- @param predicate fun(key: any) : boolean  A function that returns true for keys to remove from the table
local function remove_keys_where(tbl, predicate)
    for key, _ in pairs(tbl) do
        if predicate(key) then tbl[key] = nil end
    end
end

--- Removes all occurrences of the given values from the given table.  Modifies the table in-place.
--- @param tbl table  The table to remove values from
--- @param ... any  The values to remove from the table
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

--- Removes all occurrences of values matching the given predicate from the given table.  Modifies the table in-place.
--- @param tbl table  The table to remove values from
--- @param predicate fun(value: any) : boolean  A function that returns true for values to remove from the table
local function remove_values_where(tbl, predicate)
    local removing = {}
    for index, value in ipairs(tbl) do
        if predicate(value) then table.insert(removing, index) end
    end

    for i = #removing, 1, -1 do
        table.remove(tbl, removing[i])
    end
end

return {
    has_any_value = has_any_value,
    has_value = has_value,
    remove_keys = remove_keys,
    remove_keys_where = remove_keys_where,
    remove_values = remove_values,
    remove_values_where = remove_values_where,
}