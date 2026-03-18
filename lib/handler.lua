-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/try-catch.lua

local trace = require "lib.trace"

--- @class TryBlock
--- @field [1] fun() : ...  The function to be called as the "try" block
--- @field [2] (fun(error: any) : boolean, ...)?  An optional function to be called as the "catch" block if an error occurs, with the error passed as an argument

--- Implements try-catch functionality by wrapping a call to pcall and invoking the appropriate function based on success or failure
--- @param what TryBlock
--- @return ...
--- <br/>
--- Example usage:
--- ```lua
--- local handler = require "lib.handler"
--- ...
--- handler.try {
---     -- try
---     function()
---         -- code to try goes here
---     end,
---     -- catch
---     function(error)
---        -- error handling code goes here, with the error passed as an argument
---        -- return true to indicate the error should not be re-raised
---     end
--- }
--- ```
local function try(what)
    --- @type { [1]: boolean, [integer]: any }
    local results = trace.scallx(what[1])

    if not results[1] then
        local msg = results[2] --[[@as TracedError]]

        if msg.message == "Terminated" then
            -- Force termination to always pass
            trace.record_error_message(msg.message)
            error(msg.message, 0)
        end

        local catch = what[2]

        if catch then
            results = { catch(msg.message) }
        end

        if not results[1] then
            trace.record_error_message(msg.message)
            error(msg, 2)
        end
    end

    return table.unpack(results, 2)
end

local module_table = {}

module_table.try = try

return module_table