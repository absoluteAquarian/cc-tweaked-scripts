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
--- @field report string
--- @field tail boolean
--- @field func function

--- @type DebugStackEntry[]
local __stack = {}

local __file

module_table.MAX_DEPTH = 2000

local function __debug_hook(event)
    if __ignoring then return end

    __ignoring = true

    local info = debug.getinfo(2, "nSlf")

    -- Indicate in the stack whether a call is a tail call, for future reference
    if event == "call" or event == "tail call" then
        local src = info.short_src
        local after = src:match(".*/()")
        if after then src = src:sub(after) end
        local line = info.currentline
        local name = info.name or "?"

        local depth = #__stack + 1

        table.insert(
            __stack,
            {
                report = line > 0
                    and string.format("%d: %s:L%d (%s)", depth, src, line, name)
                    or string.format("%d: %s (%s)", depth, src, name),
                tail = event == "tail call",
                func = info.func
            }
        )

        if #__stack >= module_table.MAX_DEPTH then
            __file.writeLine(string.format("Function call depth exceeded %d:", module_table.MAX_DEPTH))
            __file.writeLine(debug.traceback(nil, 2))
            __file.writeLine("")
            __file.writeLine("")

            for _, entry in ipairs(__stack) do
                __file.write(entry.report)
                if entry.tail then __file.write(" [tail call]") end
                __file.writeLine("")
            end

            debug.sethook(nil)
        end
    -- Return event will clear any "tail returns" in the call stack as well
    elseif event == "return" then
        --- @type DebugStackEntry
        local current

        -- First remove any tail calls leading up to this return
        repeat
            current = table.remove(__stack)--[[@as DebugStackEntry]]
        until current == nil or current.func == info.func

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