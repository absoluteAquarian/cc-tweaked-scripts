--- @private
--- @class TracedError
--- @field __scall_message string

--- Calls the specified function with the given arguments, throwing an error with the full stacktrace if the function throws an error<br/>
--- This function effectively acts as a wrapper around xpcall()
--- @param func fun(...) : ...  The function to call with the given arguments
--- @param ... any  The arguments to call the function with
--- @return ...  The return values of the function, if the call was successful
local function scall(func, ...)
    --- @param err any
    --- @return TracedError
    local function __handler(err)
        -- Forward the error message through nested scall() calls
        if type(err) == "table" and rawget(err, "__scall_message") then return err end

        local message = debug.traceback(err or "Caught unspecified error via lib.trace.scall()", 3)

        pcall(
            function(msg)
                -- Save the stacktrace to a file since the terminal likely won't be large enough to display it
                local program = shell.getRunningProgram()
                local path = fs.getDir(program) .. "/logs/" .. fs.getName(program) .. "-" .. os.time()

                local tries = 1
                while fs.exists(path .. ".log") do
                    tries = tries + 1
                    path = path .. "-" .. tries
                end

                local handle = fs.open(path .. ".log", "w")
                handle.write(msg)
                handle.flush()
                handle.close()
            end,
            message
        )

        return setmetatable(
            {
                __scall_message = message
            },
            {
                --- @param self TracedError
                --- @return string
                __tostring = function(self) return self.__scall_message end
            }
        )
    end

    local results = { xpcall(func, __handler, ...) }

    if not results[1] then
        error(results[2], 0)
    end

    return table.unpack(results, 2)
end

--- Wraps the function call in a call to scall()
--- @param func function  The function to wrap
--- @return function
local function wrap(func)
    return function(...) return scall(func, ...) end
end

return {
    scall = scall,
    wrap = wrap
}