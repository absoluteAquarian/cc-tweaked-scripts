require "util.class"
require "util.string"

--- @alias Tier_WithinTier fun(self: Tier, eu: number) : boolean
--- @alias Tier_Amps fun(self: Tier, eu: number) : number
--- @alias Tier_MatchesPeripheral fun(self: Tier, p: string) : boolean
--- @alias Tier_ConversionFactorTo fun(self: Tier, other: Tier) : number
--- @alias Tier { name: string, volts_per_amp: number, color: number, index: number, within_tier: Tier_WithinTier, amps: Tier_Amps, matches_peripheral: Tier_MatchesPeripheral, conversion_factor_to: Tier_ConversionFactorTo }

Tier = class(
    nil,
    function(klass)
        -- Redefine the constructor to take named parameters

        --- @param instance Tier
        --- @param name string  The name of this tier
        --- @param volts number  The voltage per amp for this tier
        --- @param color number  The color corresponding to this tier
        function klass:ctor(instance, name, volts, color)
            instance.name = name
            instance.volts_per_amp = volts
            instance.color = color
            instance.index = 0

            --- Returns whether the given EU is within this tier
            --- @param self Tier  The tier to check
            --- @param eu number  The EU to check
            --- @return boolean
            function instance:within_tier(eu)
                if self.name == "MAX" then return true end
                local low = self.volts_per_amp
                return eu <= low and eu < 4 * low
            end

            --- Returns how many amps of this tier are needed to send the given EU
            --- @param self Tier  The tier to check
            --- @param eu number  The EU to convert
            --- @return number
            function instance:amps(eu)
                return eu / self.volts_per_amp
            end

            --- Returns whether the given peripheral name matches this tier (e.g. "gtceu:ulv_assembler" matches the "ULV" tier)
            --- @param self Tier  The tier to check
            --- @param p string  The name of the peripheral to check
            --- @return boolean
            function instance:matches_peripheral(p)
                return contains(p, ":" .. string.lower(self.name))
            end

            --- Returns the conversion factor to convert voltage from this tier to another tier
            --- @param self Tier  The tier to convert from
            --- @param other Tier  The tier to convert to
            --- @return number
            function instance:conversion_factor_to(other)
                if self.index == 0 or other.index == 0 then return 1 end
                return math.pow(4, self.index - other.index)
            end
        end
    end
)

--- @type Tier[]
local def = {
    Tier:new("ULV", 8, colors.gray),
    Tier:new("LV", 32, colors.lightGray),
    Tier:new("MV", 128, colors.cyan),
    Tier:new("HV", 512, colors.orange),
    Tier:new("EV", 2048, colors.purple),
    Tier:new("IV", 8192, colors.blue),
    Tier:new("LuV", 32768, colors.magenta),
    Tier:new("ZPM", 131072, colors.red),
    Tier:new("UV", 524288, colors.green),
    Tier:new("UHV", 2097152, colors.purple),
    Tier:new("UEV", 8388608, colors.lime),
    Tier:new("MAX", 2147483648, colors.red)
}

for index, tier in ipairs(def) do
   tier.index = index
end

--- Gets the table representing the tier with the given name, or nil if no such tier exists
--- @param name string  The name of the tier to get
--- @return Tier?
local function __internal_get_tier(name)
    for _, tier in ipairs(def) do
        if tier.name == name then return tier end
    end
    return nil
end

local tier_max = __internal_get_tier("MAX") or def[#def]

--- Gets the tier corresponding to the given EU
--- @param eu number  The EU to get the tier for
--- @return Tier
local function __internal_eu_tier(eu)
    for _, tier in ipairs(def) do
        if tier:within_tier(eu) then return tier end
    end
    return tier_max
end

--- Gets the name of the EU tier corresponding to the given peripheral name, or nil if no matching tier is found
--- @param name string  The name of the peripheral to get the tier for
--- @return string?
function peripheral_tier(name)
    for _, tier in ipairs(def) do
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