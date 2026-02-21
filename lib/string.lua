--- Returns whether 'str' contains 'text'
--- @param str string  The string to search through
--- @param text string  The text to search for
--- @param plain boolean?  Whether to treat 'text' as a plain string (defaults to true)
--- @return boolean
local function contains(str, text, plain)
    return string.find(str, text, 1, plain or true) ~= nil
end

--- Returns whether 'str' starts with 'text'
--- @param str string  The string to search through
--- @param text string  The text to search for
--- @return boolean
local function starts_with(str, text)
    return text == "" or string.sub(str, 1, #text) == text
end

--- Returns whether 'str' ends with 'text'
--- @param str string  The string to search through
--- @param text string  The text to search for
--- @return boolean
local function ends_with(str, text)
    return text == "" or string.sub(str, -#text) == text
end

return {
    contains = contains,
    starts_with = starts_with,
    ends_with = ends_with,
}