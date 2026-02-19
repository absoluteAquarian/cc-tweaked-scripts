--- Returns the given value formatted with a sign and the color corresponding to whether it's positive, negative, or zero
--- @param value number  The value to format
--- @return string, number
local function signed_and_color(value)
    if value > 0 then
        return "+" .. value, colors.green
    elseif value == 0 then
        return " " .. value, colors.white
    else
        return "" .. value, colors.red
    end
end

return {
    signed_and_color = signed_and_color
}