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

local __depth = 0
local __ignoring = false
--- @type function[]
local __stack = {}
local __file

module_table.MAX_DEPTH = 2000

local function __debug_hook(event)
    if __ignoring then return end

    __ignoring = true

    if event == "call" then
        __depth = __depth + 1

        local info = debug.getinfo(2, "nSl")
        local src = info.short_src
        local after = src:match(".*/()")
        if after then src = src:sub(after) end
        local line = info.currentline
        local name = info.name or "?"

        table.insert(
            __stack,
            line > 0
                and string.format("%d: %s:L%d (%s)", __depth, src, line, name)
                or string.format("%d: %s (%s)", __depth, src, name)
        )

        if __depth >= module_table.MAX_DEPTH then
            __file.writeLine(string.format("Function call depth exceeded %d:", module_table.MAX_DEPTH))
            __file.writeLine(debug.traceback(nil, 2))
            __file.writeLine("")
            __file.writeLine("")
            __file.writeLine(table.concat(__stack, "\n"))
            debug.sethook(nil)
        end
    elseif event == "return" then
        __depth = __depth - 1
        table.remove(__stack)
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