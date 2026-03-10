local native = {
    math = {
        ceil = math.ceil,
        floor = math.floor,
        huge = math.huge,
        pow = math.pow
    }
}

--- Returns the integer part of a number via truncation
--- @param num number  The number to truncate
--- @return integer
local function integer(num)
    if num == native.math.huge or num == -native.math.huge or num ~= num then return num end
    if num >= 0 then
        return native.math.floor(num)
    else
        return native.math.ceil(num)
    end
end

--- Rounds a number to the specified number of decimal places (0 by default)
--- @param num number  The number to round
--- @param numDecimalPlaces number?  The number of decimal places to round to (defaults to 0)
--- @return number
local function round(num, numDecimalPlaces)
    if num == native.math.huge or num == -native.math.huge or num ~= num then return num end
    local mult = native.math.pow(10, numDecimalPlaces or 0)
    return num >= 0 and native.math.floor(num * mult + 0.5) / mult or native.math.ceil(num * mult - 0.5) / mult
end

return {
    integer = integer,
    round = round
}