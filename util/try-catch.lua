-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/try-catch.lua

--- @class TryBlock
--- @field [1] fun(...) : ...  The function to be called as the "try" block
--- @field [2] (fun(error: any) : ...)?  An optional function to be called as the "catch" block if an error occurs, with the error passed as an argument
local TryBlock = {}

--- Implements try-catch functionality by wrapping a call to pcall and invoking the appropriate function based on success or failure
--- @param what TryBlock
--- @return ...
--- <br/>
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