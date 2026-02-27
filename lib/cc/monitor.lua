local R_terminal = require "lib.cc.terminal"

--- Writes a string of text to the monitor with the specified color
--- @param monitor table  The monitor to write to
--- @param color number  The color to write with (see: colors)
--- @param text string  The text to write
local function write(monitor, color, text)
    -- Body moved to other module, but the function is kept for backwards compatibility
    R_terminal.write(monitor, color, text)
end

--- Performs the given function on all connected monitors
--- @param func fun(monitor: table)  The function to perform on each monitor.
local function foreach_monitor(func)
    for _, monitor in pairs({ peripheral.find("monitor") } --[[@as table[]=]]) do
        func(monitor)
    end
end

--- Forces all connected monitors to display a blue screen with the given title and description
--- @param title string?  The title to display on the blue screen (defaults to "Error")
--- @param desc string?  The description to display on the blue screen (defaults to "X_x")
local function bsod_external_monitors(title, desc)
    title = title or "Error"
    desc = desc or "X_x"

    foreach_monitor(
        function (monitor)
            monitor.setTextColor(colors.white)
            monitor.setBackgroundColor(colors.blue)
            monitor.clear()
            monitor.setCursorPos(2, 2)
            monitor.write(title)
            monitor.setCursorPos(2, 4)
            monitor.write(desc)
        end
    )
end

return {
    write = write,
    bsod_external_monitors = bsod_external_monitors,
    foreach_monitor = foreach_monitor
}