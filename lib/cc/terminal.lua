local trace = require "lib.trace"

local native = {
    colors = {
        --- @type fun(color: number) : string
        toBlit = colors.toBlit,
        --- @type fun(blit: string) : number
        fromBlit = colors.fromBlit
    }
}

--- @param terminal table
--- @param text string
--- @param hex_fg string
--- @param hex_bg string
local function blit_infer(terminal, text, hex_fg, hex_bg)
    local fg_blit = native.colors.toBlit(terminal.getTextColor())
    local bg_blit = native.colors.toBlit(terminal.getBackgroundColor())

    local fg = hex_fg:gsub("%-", fg_blit)
    local bg = hex_bg:gsub("%-", bg_blit)

    terminal.blit(text, fg, bg)
end

--- @param terminal table
--- @param color number
--- @param text string
local function write(terminal, color, text)
    local prev = terminal.getTextColor()
    terminal.setTextColor(color)
    terminal.write(text)
    terminal.setTextColor(prev)
end

local function reset_terminal()
    term.clear()
    term.setCursorPos(1, 1)
end

--- @param terminal table
local function clear_terminal(terminal)
    terminal.clear()
    terminal.setCursorPos(1, 1)
end

local module_table = {}

--- Performs the same logic as <code>blit()</code>, but can include <code>"-"</code> to indicate using the current colors for a character
--- @param terminal table  The terminal to write to
--- @param text string  The text to write
--- @param hex_fg string  A hex string representing the foreground color for each character.  Use <code>"-"</code> to use the current terminal foreground color.
--- @param hex_bg string  A hex string representing the background color for each character.  Use <code>"-"</code> to use the current terminal background color.
function module_table.blit_infer(terminal, text, hex_fg, hex_bg) return trace.scall(blit_infer, terminal, text, hex_fg, hex_bg) end

--- Writes a string of text to the terminal with the specified color
--- @param terminal table  The terminal to write to
--- @param color number  The color to write with (see: <code>colors</code>)
--- @param text string  The text to write
function module_table.write(terminal, color, text) return trace.scall(write, terminal, color, text) end

--- Resets the current terminal by clearing it and setting the cursor position to the top left corner
function module_table.reset_terminal() return trace.scall(reset_terminal) end

--- Resets the provided terminal by clearing it and setting the cursor position to the top left corner
--- @param terminal table  The terminal to reset
function module_table.clear_terminal(terminal) return trace.scall(clear_terminal, terminal) end

return module_table