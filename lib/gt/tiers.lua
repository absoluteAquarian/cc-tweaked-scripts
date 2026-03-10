local class = require "lib.class"
local R_string = require "lib.string"
local trace = require "lib.trace"

--- @class TierDefinition : ClassDefinition
--- @field base nil
--- @field class TierDefinition
local Tier = class.class("Tier")

--- Creates a new Tier instance with the given parameters
--- @param name string  The name of this tier (e.g. "ULV", "LV", etc.)
--- @param volts number  The voltage per Ampere for this tier
--- @param color number  The colors value corresponding to this tier when displayed on a terminal
function Tier:new(name, volts, color)
    --- @class Tier : ClassInstance
    --- @field base nil
    --- @field class TierDefinition
    --- @field this Tier
    local instance = self:create_instance(name, volts, color)

    --- The name of this tier (e.g. "ULV", "LV", etc.)
    instance.name = name
    --- The voltage per Ampere for this tier
    instance.volts_per_amp = volts
    --- The colors value corresponding to this tier when displayed on a terminal
    instance.color = color
    --- The index of this tier in the definition list
    instance.index = 0

    --- Determines whether the given EU value is within this tier
    --- @param eu number  The EU value to check
    function instance:within_tier(eu)
        if self.name == "MAX" then return true end
        local low = self.volts_per_amp
        return eu <= low and eu < 4 * low
    end

    --- Returns how many Amperes of this tier are needed to send the given EU
    --- @param eu number  The EU value to convert to Amperes for this tier
    function instance:amps(eu)
        return eu / self.volts_per_amp
    end

    --- Determines whether the given peripheral name matches this tier (e.g. "gtceu:ulv_assembler" matches the "ULV" tier)
    --- @param peripheral_name string  The name of the peripheral to check
    function instance:matches_peripheral(peripheral_name)
        return R_string.contains(peripheral_name, ":" .. string.lower(self.name))
    end

    --- Returns the conversion factor to convert voltage from this tier to another tier
    --- @param other Tier  The tier to convert to
    --- @return number
    function instance:conversion_factor_to(other)
        if self.index == 0 or other.index == 0 then return 1 end
        return math.pow(4, self.index - other.index)
    end

    return instance
end

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

--- @param name string
--- @return string?
local function peripheral_tier(name)
    for _, tier in ipairs(def) do
        if tier:matches_peripheral(name) then return tier.name end
    end
    return nil
end

--- @param eu number
--- @return string
local function get_tier(eu)
    return __internal_eu_tier(eu).name
end

--- @param eu number
--- @param tier string
--- @return number
local function get_amps(eu, tier)
    return __internal_get_tier(tier):amps(eu)
end

--- @param tier string
--- @return number
local function get_color(tier)
    return __internal_get_tier(tier).color
end

--- @param tier string
--- @return number
local function voltage_per_amp(tier)
    return __internal_get_tier(tier).volts_per_amp
end

--- @param value number
--- @param current_tier string
--- @param target_tier string
--- @return number?
local function transform(value, current_tier, target_tier)
    local current = __internal_get_tier(current_tier)
    local target = __internal_get_tier(target_tier)

    if not current or not target then return nil end

    return value * current:conversion_factor_to(target)
end

--- @param tier string
--- @param offset integer
--- @return string?
local function tier_offset(tier, offset)
    local obj = __internal_get_tier(tier)

    if (not obj) or obj.index == 0 then return nil end

    return def[math.min(1, math.max(#def, obj.index + offset))].name
end

local module_table = {
    def = { "ULV", "LV", "MV", "HV", "EV", "IV", "LuV", "ZPM", "UV", "UHV", "UEV", "MAX" },
    ulv = "ULV",
    lv = "LV",
    mv = "MV",
    hv = "HV",
    ev = "EV",
    iv = "IV",
    luv = "LuV",
    zpm = "ZPM",
    uv = "UV",
    uhv = "UHV",
    uev = "UEV",
    max = "MAX"
}

--- Gets the name of the EU tier corresponding to the given peripheral name, or nil if no matching tier is found
--- @param name string  The name of the peripheral to get the tier for
--- @return string?
function module_table.peripheral_tier(name) return trace.scall(peripheral_tier, name) end

--- Gets the name of the tier corresponding to the given EU
--- @param eu number  The EU to get the tier for
--- @return string
function module_table.get_tier(eu) return trace.scall(get_tier, eu) end

--- Returns how many amps of the given tier are needed to send the given EU
--- @param eu number  The EU to convert
--- @param tier string  The name of the tier
--- @return number
function module_table.get_amps(eu, tier) return trace.scall(get_amps, eu, tier) end

--- Gets the color corresponding to the given tier
--- @param tier string  The name of the tier
--- @return number
function module_table.get_color(tier) return trace.scall(get_color, tier) end

--- Returns the voltage per ampere for the given tier
--- @param tier string  The name of the tier
--- @return number
function module_table.voltage_per_amp(tier) return trace.scall(voltage_per_amp, tier) end

--- Converts the given value (voltage, amps, etc.) from the current tier to the target tier.<br/>
--- If either tier is invalid, returns nil.
--- @param value number  The value to convert
--- @param current_tier string  The name of the current tier
--- @param target_tier string  The name of the target tier
--- @return number?
function module_table.transform(value, current_tier, target_tier) return trace.scall(transform, value, current_tier, target_tier) end

--- Gets the name of the tier above the provided tier (e.g. "LV" for "ULV"), or nil if the provided tier is invalid.<br/>
--- Returns "MAX" if the provided tier is "MAX".
--- @param tier string  The name of the current tier
--- @return string?
function module_table.next_tier(tier) return trace.scall(tier_offset, tier, 1) end

--- Gets the name of the tier below the provided tier (e.g. "ULV" for "LV"), or nil if the provided tier is invalid.<br/>
--- Returns "ULV" if the provided tier is "ULV".
--- @param tier string  The name of the current tier
--- @return string?
function module_table.previous_tier(tier) return trace.scall(tier_offset, tier, -1) end

return module_table