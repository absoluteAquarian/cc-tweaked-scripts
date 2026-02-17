--- Returns whether 'str' contains 'text'
--- @param str string  The string to search through
--- @param text string  The text to search for
--- @param plain boolean?  Whether to treat 'text' as a plain string (defaults to true)
function contains(str, text, plain)
    return string.find(str, text, 1, plain or true) ~= nil
end

--- Returns whether 'str' starts with 'text'
--- @param str string  The string to search through
--- @param text string  The text to search for
--- @param plain boolean?  Whether to treat 'text' as a plain string (defaults to true)
function starts_with(str, text, plain)
    return text == "" or string.sub(str, 1, #text) == text
end

return {
    contains = contains,
    starts_with = starts_with
}