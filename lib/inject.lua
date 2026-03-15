--- Defines a set of functions for tracking function call stacks and writing them to a file.<br/>
--- <b>Repeated initialization of the module will overwrite the log file from previous uses.</b>
--- <p/>
--- Example usage:
--- ```lua
--- local inject = require "lib.inject"
--- 
--- inject.prepare()
--- 
--- pcall(
---     function()
---         -- The code to track goes here
---         -- This could be one function call, or the entirety of the program
---     end
--- )
--- 
--- inject.cleanup()
--- ```
local module_table = {}

local __ignoring = false

--- @class DebugStackEntry
--- @field depth integer
--- @field src string
--- @field line integer
--- @field name string
--- @field func function
--- @field tail boolean

--- @type DebugStackEntry[]
local __stack = {}

local __file

module_table.MAX_DEPTH = 2000

local function __debug_hook(event)
    if __ignoring then return end

    __ignoring = true

    -- Indicate in the stack whether a call is a tail call, for future reference
    if event == "call" or event == "tail call" then
        local caller = debug.getinfo(3, "Sl")
        local info = debug.getinfo(2, "nf")

        table.insert(
            __stack,
            {
                depth = #__stack + 1,
                src = caller.short_src,
                line = caller.currentline,
                name = info.name or "?",
                func = info.func,
                tail = event == "tail call"
            }
        )

        if #__stack >= module_table.MAX_DEPTH then
            __file.writeLine(string.format("Function call depth exceeded %d:", module_table.MAX_DEPTH))
            __file.writeLine(debug.traceback(nil, 2))
            __file.writeLine("")
            __file.writeLine("")

            for _, entry in ipairs(__stack) do
                local src = entry.src
                local after = src:match(".*/()")
                if after then src = src:sub(after) end

                local report = entry.line > 0
                    and string.format("%d: %s:L%d (%s)", entry.depth, src, entry.line, entry.name)
                    or string.format("%d: %s (%s)", entry.depth, src, entry.name)

                __file.write(report)

                if entry.tail then __file.write(" [tail call]") end

                __file.writeLine("")
            end

            debug.sethook(nil)
        end
    -- Return event will clear any "tail returns" in the call stack as well
    elseif event == "return" then
        local caller = debug.getinfo(3, "f")

        --- @type DebugStackEntry
        local current

        -- First remove any tail calls leading up to this return
        repeat
            current = table.remove(__stack)--[[@as DebugStackEntry]]
        until current == nil or current.func == caller.func

        -- Then any tail calls after it
        while current and current.tail do
            current = table.remove(__stack)--[[@as DebugStackEntry]]
        end
    end

    __ignoring = false
end

--- Prepares the module for tracking functions
function module_table.prepare()
    local FILE = "report.log"
    if fs.exists(FILE) then fs.delete(FILE) end
    __file = fs.open(FILE, "w")
    debug.sethook(__debug_hook, "cr")
end

function module_table.cleanup()
    debug.sethook(nil)
    pcall(__file.close)
end

return module_table