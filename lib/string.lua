--- @class __StringRepCache
--- @field [string] string[]  A table mapping a string to an array of that string repeated N times.  For example, cache["abc"][3] == "abcabcabc"
local __rep_cache = {}

--- A wrapper around string.rep() that caches results for better performance.
--- @param str string  The string to repeat
--- @param count integer  The number of times to repeat the string
--- @return string result  The repeated string
local function cached_rep(str, count)
    local cache_tbl = __rep_cache[str]
    if not cache_tbl then
        cache_tbl = {}
        __rep_cache[str] = cache_tbl
    end

    local result = cache_tbl[count]
    if not result then
        result = count < 1 and "" or string.rep(str, count)
        cache_tbl[count] = result
    end

    return result
end

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
    cached_rep = cached_rep,
    contains = contains,
    starts_with = starts_with,
    ends_with = ends_with,
}