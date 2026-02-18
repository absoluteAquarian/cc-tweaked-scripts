--- Rounds a number to the specified number of decimal places (0 by default)
--- @param num number  The number to round
--- @param numDecimalPlaces number?  The number of decimal places to round to (defaults to 0)
--- @return number
function round(num, numDecimalPlaces)
    local mult = math.pow(10, numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

return {
    round = round
}