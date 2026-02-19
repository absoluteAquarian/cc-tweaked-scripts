local class = require "util.class"
local R_string = require "util.string"

--- @class TierDefinition : ClassDefinition
--- (Overrides)
--- @field __make_instance fun(self: TierDefinition, name: string, volts: number, color: number) : Tier  Creates a new class instance, converted to a Tier object
--- @field new fun(self: TierDefinition, name: string, volts: number, color: number) : Tier  Creates a new Tier instance with the given parameters
local TierClass = {}

--- @class Tier : ClassInstance
--- (Defines)
--- @field name string  The name of this tier (e.g. "ULV", "LV", etc.)
--- @field volts_per_amp number  The voltage per Ampere for this tier
--- @field color number  The color corresponding to this tier when displayed on a monitor
--- @field index number  The index of this tier in the definition list
--- @field within_tier fun(self: Tier, eu: number) : boolean  Whether the given EU value is within this tier
--- @field amps fun(self: Tier, eu: number) : number  How many Amperes of this tier are needed to send the given EU
--- @field matches_peripheral fun(self: Tier, peripheral_name: string) : boolean  Whether the given peripheral name matches this tier (e.g. "gtceu:ulv_assembler" matches the "ULV" tier)
--- @field conversion_factor_to fun(self: Tier, other: Tier) : number  The conversion factor to convert voltage from this tier to another tier
local TierInstance = {}

local Tier = class.class(
    nil,
    --- @param klass TierDefinition
    function(klass)
        function klass:new(name, volts, color)
            local instance = klass:__make_instance(name, volts, color)

            instance.name = name
            instance.volts_per_amp = volts
            instance.color = color
            instance.index = 0

            --- @param eu number  The EU value to check
            function instance:within_tier(eu)
                if self.name == "MAX" then return true end
                local low = self.volts_per_amp
                return eu <= low and eu < 4 * low
            end

            --- @param eu number  The EU value to convert to Amperes for this tier
            function instance:amps(eu)
                return eu / self.volts_per_amp
            end

            --- @param peripheral_name string  The name of the peripheral to check
            function instance:matches_peripheral(peripheral_name)
                return R_string.contains(peripheral_name, ":" .. string.lower(self.name))
            end

            --- @param other Tier  The tier to convert to
            function instance:conversion_factor_to(other)
                if self.index == 0 or other.index == 0 then return 1 end
                return math.pow(4, self.index - other.index)
            end

            return instance
        end
    end
) --[[@as TierDefinition]]

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

local tier_max = def[#def]

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
local function peripheral_tier(name)
    for _, tier in ipairs(def) do
        if tier:matches_peripheral(name) then return tier.name end
    end
    return nil
end

--- Gets the name of the tier corresponding to the given EU
--- @param eu number  The EU to get the tier for
--- @return string
local function get_tier(eu)
    return __internal_eu_tier(eu).name
end

--- Returns how many amps of the given tier are needed to send the given EU
--- @param eu number  The EU to convert
--- @param tier string  The name of the tier
--- @return number
local function get_amps(eu, tier)
    return __internal_get_tier(tier):amps(eu)
end

--- Gets the color corresponding to the given tier
--- @param tier string  The name of the tier
--- @return number
local function get_color(tier)
    return __internal_get_tier(tier).color
end

--- Returns the voltage per amp for the given tier
--- @param tier string  The name of the tier
--- @return number
local function voltage_per_amp(tier)
    return __internal_get_tier(tier).volts_per_amp
end

--- Converts the given value (voltage, amps, etc.) from the current tier to the target tier
--- @param value number  The value to convert
--- @param current_tier string  The name of the current tier
--- @param target_tier string  The name of the target tier
--- @return number?
local function transform(value, current_tier, target_tier)
    local current = __internal_get_tier(current_tier)
    local target = __internal_get_tier(target_tier)

    if not current or not target then return nil end

    return value * current:conversion_factor_to(target)
end

return {
    def = { "ULV", "LV", "MV", "HV", "EV", "IV", "LuV", "ZPM", "UV", "UHV", "UEV", "MAX" },
    peripheral_tier = peripheral_tier,
    get_tier = get_tier,
    get_amps = get_amps,
    get_color = get_color,
    voltage_per_amp = voltage_per_amp,
    transform = transform
}