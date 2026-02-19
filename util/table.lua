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

return {
    has_any_value = has_any_value,
    has_value = has_value,
    remove_values = remove_values
}