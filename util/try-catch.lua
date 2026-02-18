-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/try-catch.lua

-- This is a utility class to add try - catch functionality
-- include it by downloading to your computer and import it with 'require "util.try-catch"'

--- @alias _CatchBody fun(error: any) : ...
--- @alias _TryBody fun() : ...
--- @alias TryBlock { [1]: _TryBody, [2]: _CatchBody? }

--- Implements try-catch functionality by wrapping a call to pcall and invoking the appropriate function based on success or failure
--- @param what TryBlock  A table containing a function to be called as the "try" block and an optional function to be called as the "catch" block if an error occurs
--- @return ...
--- Example usage:
--- ```lua
--- try {
---     -- try
---     function()
---         -- code to try goes here
---     end,
---     -- catch
---     function(error)
---        -- error handling code goes here, with the error passed as an argument
---     end
--- }
--- ```
function try(what)
    --- @type table<boolean, ...>
    local results = { pcall(what[1]) }

    if not results[1] then
        local catch = what[2]
        return catch and catch(results[2]) or nil
    end

    return table.unpack(results, 2)
end

return {
    try = try
}