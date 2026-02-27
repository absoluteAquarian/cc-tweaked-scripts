--- Performs the same logic as blit(), but can include "-" to indicate using the current colors for a character
--- @param terminal table  The terminal to write to
--- @param text string  The text to write
--- @param hex_fg string  A hex string representing the foreground color for each character.  Use '-' to use the current foreground color for a character.
--- @param hex_bg string  A hex string representing the background color for each character.  Use '-' to use the current background color for a character.
local function blit_infer(terminal, text, hex_fg, hex_bg)
    local fg_blit = colors.toBlit(terminal.getTextColor())
    local bg_blit = colors.toBlit(terminal.getBackgroundColor())

    local fg = hex_fg:gsub("%-", fg_blit)
    local bg = hex_bg:gsub("%-", bg_blit)

    terminal.blit(text, fg, bg)
end

--- Writes a string of text to the terminal with the specified color
--- @param terminal table  The terminal to write to
--- @param color number  The color to write with (see: colors)
--- @param text string  The text to write
local function write(terminal, color, text)
    local prev = terminal.getTextColor()
    terminal.setTextColor(color)
    terminal.write(text)
    terminal.setTextColor(prev)
end

--- Resets the terminal by clearing it and setting the cursor position to the top left corner
local function reset_terminal()
    term.clear()
    term.setCursorPos(1, 1)
end

--- Resets the provided terminal by clearing it and setting the cursor position to the top left corner
--- @param terminal table  The terminal to reset
local function clear_terminal(terminal)
    terminal.clear()
    terminal.setCursorPos(1, 1)
end

return {
    blit_infer = blit_infer,
    write = write,
    reset_terminal = reset_terminal,
    clear_terminal = clear_terminal
}