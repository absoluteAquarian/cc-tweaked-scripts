require "util.class"
require "util.string"

Tier = class(
    --- @param self table  The tier being initialized
    --- @param name string  The name of this tier (e.g. "ULV")
    --- @param volts number  The voltage per amp for this tier
    --- @param color number  The color to use for this tier (see: colors)
    --- @return table
    function(self, name, volts, color)
        self.name = name
        self.volts_per_amp = volts
        self.color = color
        self.index = 0
    end
)

local def = {
    Tier("ULV", 8, colors.gray),
    Tier("LV", 32, colors.lightGray),
    Tier("MV", 128, colors.cyan),
    Tier("HV", 512, colors.orange),
    Tier("EV", 2048, colors.purple),
    Tier("IV", 8192, colors.blue),
    Tier("LuV", 32768, colors.magenta),
    Tier("ZPM", 131072, colors.red),
    Tier("UV", 524288, colors.green),
    Tier("UHV", 2097152, colors.purple),
    Tier("UEV", 8388608, colors.lime),
    Tier("MAX", 2147483648, colors.red)
}

for index, tier in ipairs(def) do
   tier.index = index
end

--- Returns whether the given EU is within this tier
--- @self table  The tier to check
--- @param eu number  The EU to check
--- @return boolean
function Tier:within_tier(eu)
    if self.name == "MAX" then return true end
    local low = self.volts_per_amp
    return eu <= low and eu < 4 * low
end

--- Returns how many amps of this tier are needed to send the given EU
--- @param self table  The tier to check
--- @param eu number  The EU to convert
--- @return number
function Tier:amps(eu)
    return eu / self.volts_per_amp
end

--- Returns whether the given peripheral name matches this tier (e.g. "gtceu:ulv_assembler" matches the "ULV" tier)
--- @param self table  The tier to check
--- @param name string  The name of the peripheral to check
--- @return boolean
function Tier:matches_peripheral(name)
    return contains(name, ":" .. string.lower(self.name))
end

--- Returns the conversion factor to convert voltage from this tier to another tier
--- @param self table  The tier to convert from
--- @param other table  The tier to convert to
--- @return number
function Tier:conversion_factor_to(other)
    if self.index == 0 or other.index == 0 then return 1 end 
    return math.pow(4, self.index - other.index)
end

--- Gets the table representing the tier with the given name, or nil if no such tier exists
--- @param name string  The name of the tier to get
--- @return table?
local function __internal_get_tier(name)
    for _, tier in pairs(def) do
        if tier.name == name then return tier end
    end
    return nil
end

local tier_max = __internal_get_tier("MAX") or def[#def]

--- Gets the tier corresponding to the given EU
--- @param eu number  The EU to get the tier for
--- @return table
local function __internal_eu_tier(eu)
    for _, tier in pairs(def) do
        if tier.within_tier(eu) then return tier end
    end
    return tier_max
end

--- Gets the name of the EU tier corresponding to the given peripheral name, or nil if no matching tier is found
--- @param name string  The name of the peripheral to get the tier for
--- @return string?
function peripheral_tier(name)
    for _, tier in pairs(def) do
        if tier:matches_peripheral(name) then return tier.name end
    end
    return nil
end

--- Gets the name of the tier corresponding to the given EU
--- @param eu number  The EU to get the tier for
--- @return string
function get_tier(eu)
    return __internal_eu_tier(eu).name
end

--- Returns how many amps of the given tier are needed to send the given EU
--- @param eu number  The EU to convert
--- @param tier string  The name of the tier
--- @return number
function get_amps(eu, tier)
    return __internal_get_tier(tier):amps(eu)
end

--- Gets the color corresponding to the given tier
--- @param tier string  The name of the tier
--- @return number
function get_color(tier)
    return __internal_get_tier(tier).color
end

--- Returns the voltage per amp for the given tier
--- @param tier string  The name of the tier
--- @return number
function voltage_per_amp(tier)
    return __internal_get_tier(tier).volts_per_amp
end

--- Converts the given value (voltage, amps, etc.) from the current tier to the target tier
--- @param value number  The value to convert
--- @param current_tier string  The name of the current tier
--- @param target_tier string  The name of the target tier
--- @return number?
function transform(value, current_tier, target_tier)
    local current = __internal_get_tier(current_tier)
    local target = __internal_get_tier(target_tier)

    if not current or not target then return nil end

    return value * current:conversion_factor_to(target)
end

return {
    class = Tier,
    def = def,
    max = tier_max,
    peripheral_tier = peripheral_tier,
    get_tier = get_tier,
    get_amps = get_amps,
    get_color = get_color,
    voltage_per_amp = voltage_per_amp,
    transform = transform
}