--- Resets the terminal by clearing it and setting the cursor position to the top left corner
function reset_terminal()
    term.clear()
    term.setCursorPos(1, 1)
end

return {
    reset_terminal = reset_terminal
}