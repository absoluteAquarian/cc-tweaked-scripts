--- Writes a string of text to the monitor with the specified color
--- @param self table  The monitor to write to
--- @param color number  The color to write with (see: colors)
--- @param text string  The text to write
local function write(self, color, text)
    local prev = self.getTextColor()
    self.setTextColor(color)
    self.write(text)
    self.setTextColor(prev)
end

--- Performs the given function on all connected monitors
--- @param func function  The function to perform on each monitor.  This function should take a monitor as its only argument.
local function foreach_monitor(func)
    for _, monitor in pairs({ peripheral.find("monitor") }) do
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