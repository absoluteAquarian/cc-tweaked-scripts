local SHOW_TRACE_LINES = false

--- Trims the provided error message to include only relevant functions for errors
--- @param msg any  The error message to trim<br/>If not a string, the message will be returned as-is
--- @param max_lines integer?  If not <code>nil</code>, the maximum number of lines to include in the trimmed message
--- @param max_width integer?  If not <code>nil</code>, the maximum width of each line in the trimmed message
--- @return any
local function trim_error_message(msg, max_lines, max_width)
    local trimmed = msg

    if type(trimmed) == "string" then
        --- @cast trimmed string

        local filtered = {}
        local count = 0
        local found_stacktrace_message = false

        for line in trimmed:gmatch("[^\r\n]+") do
            if max_lines and count >= max_lines then
                table[#table] = " ... (truncated)"
                break
            end

            if not found_stacktrace_message then
                if line:find("stack traceback:", nil, true) then
                    found_stacktrace_message = true
                end
            end

            if SHOW_TRACE_LINES or (not found_stacktrace_message) or not (line:find("pcall", nil, true) or line:find("lib/trace.lua", nil, true)) then
                if max_width and found_stacktrace_message and #line > max_width then
                    line = line:sub(1, max_width) .. " ... (truncated)"
                end

                table.insert(filtered, line)
                count = count + 1
            end
        end

        trimmed = table.concat(filtered, "\n")
    end

    return trimmed
end

--- Writes the provided error message to a log file whose name is based on the currently running program<br/>
--- Log files are written to a <code>logs</code> subdirectory of the currently running program's directory
--- @param msg any  The error to log
local function record_error_message(msg)
    -- Remove any lines that mention scall or xpcall

    msg = trim_error_message(msg)

    -- Save the stacktrace to a file since the terminal likely won't be large enough to display it

    local program = shell.getRunningProgram()
    local name = fs.getName(program)
    local extension = name:match(".*%.()")
    if extension then name = string.format("%s.log", name:sub(1, extension - 2)) end

    local path = string.format("%s/logs/%s", fs.getDir(program), name)

    --[[
    local tries = 1
    while fs.exists(path .. ".log") do
        tries = tries + 1
        path = path .. "-" .. tries
    end
    --]]

    if fs.exists(path) then fs.delete(path) end

    local handle = fs.open(path, "w")
    handle.write(tostring(msg))
    handle.flush()
    handle.close()
end

--- @class TracedError
--- @field root boolean
--- @field message string

--- @param func fun(...) : ...
--- @param ... any
--- @return table<boolean, ...>
local function scall(func, ...)
    --- @param err any
    --- @return TracedError
    local function __handler(err)
        -- Forward the error message through nested scall() calls
        -- Only the source of the error will be missing the stacktrace, so if it's present then this scall() was further up the call stack
        if type(err) == "string" and err:find("stack traceback:", nil, true) then
            return { root = false, message = err }
        end

        return {
            root = true,
            message = debug.traceback(err and tostring(err) or "Caught unspecified error via lib.trace.scall()", 3)
        }
    end

    local results = { xpcall(func, __handler, ...) }

    if not results[1] then
        local traced = results[2]  --[[@as TracedError]]

        if traced.root then
            pcall(record_error_message, traced.message)
        end
    end

    return results
end

local module_table = { }

--- Calls the specified function with the given arguments, returning a table whose first value is a boolean indicating success or failure and whose second value is either the return value of the function (if successful) or an error message with a stacktrace (if an error was thrown)<br/>
--- This function effectively acts as a wrapper around <code>xpcall()</code>
--- @param func fun(...) : ...  The function to call with the given arguments
--- @param ... any  The arguments to call the function with
--- @return table<boolean, ...>
function module_table.scallx(func, ...)
    return scall(func, ...)
end

--- Calls the specified function with the given arguments, throwing an error with the full stacktrace if the function throws an error<br/>
--- This function effectively acts as a wrapper around <code>xpcall()</code>
--- @param func fun(...) : ...  The function to call with the given arguments
--- @param ... any  The arguments to call the function with
--- @return any ...  The return values of the function, if the call was successful
function module_table.scall(func, ...)
    local results = module_table.scallx(func, ...)

    if not results[1] then
        local traced = results[2]  --[[@as TracedError]]
        error(traced.message, 0)
    end

    return table.unpack(results, 2)
end

--- Wraps the function call in a call to scall()
--- @param func function  The function to wrap
--- @return function
function module_table.wrap(func)
    return function(...) return module_table.scall(func, ...) end
end

module_table.trim_error_message = trim_error_message

module_table.record_error_message = record_error_message

return module_table