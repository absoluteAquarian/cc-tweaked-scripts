--- Formats the given value to always show its sign<br/>
--- When positive, the return value is "+value"<br/>
--- When zero, the return value is " value"<br/>
--- When negative, the return value is "-value"  (The sign is already present)
--- @param value number  The value to format with a sign
--- @return string
local function signed(value)
    if value > 0 then
        return "+" .. value
    elseif value == 0 then
        return " " .. value
    else
        return "" .. value
    end
end

--- Formats the given value to always show its sign and returns a color corresponding to whether the value is positive, negative, or zero<br/>
--- When positive, the return value is "+value" and colors.green<br/>
--- When zero, the return value is " value" and colors.white<br/>
--- When negative, the return value is "-value" and colors.red  (The sign is already present)
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
    signed = signed,
    signed_and_color = signed_and_color
}