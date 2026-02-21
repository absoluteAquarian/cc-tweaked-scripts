-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/simple_energy_monitor.lua

local fmt = require "lib.cc.fmt"
local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"

local machine = require "lib.gt.machine"
local tiers = require "lib.gt.tiers"

local class = require "lib.class"
local exec = require "lib.exec"
local R_math = require "lib.math"

local CHARGE_THRESHOLD = 0.6
local ALARM_THRESHOLD = 0.3
local PRECISION_DISPLAYED = 3
local UPDATE_INTERVAL_TICKS = 5

--- @class MetricsDefinition : ClassDefinition
--- (Overrides)
--- @field new fun(self: MetricsDefinition, eu: number) : Metrics  Creates a new Metrics instance with the given EU value
local Metrics = class.class(
    nil,
    --- @param klass MetricsDefinition
    function(klass)
        function klass:new(eu)
            --- @class Metrics : ClassInstance
            --- (Defines)
            --- @field eu number  The amount of EU this Metrics instance represents
            --- @field tier string  The tier that supports the provided EU
            --- @field amps number  The number of Amperes needed to send the provided EU at the provided tier
            --- @field report fun(self: Metrics) : string  A function to generate a human-readable report of this Metrics instance
            --- @field rescale fun(self: Metrics, target_tier: string)  A function to adjust the amperage of this Metrics instance to match a different tier
            local instance = klass:__make_instance(eu)

            instance.eu = eu
            instance.tier = tiers.get_tier(eu)
            instance.amps = tiers.get_amps(eu, instance.tier)

            function instance:report()
                return self.amps .. " A (" .. self.tier .. ")"
            end

            function instance:rescale(target_tier)
                self.amps = tiers.get_amps(self.eu, target_tier)
                self.tier = target_tier
            end

            return instance
        end
    end
)

--- @param current number
--- @param trend number
--- @param in_metrics Metrics
--- @param out_metrics Metrics
--- @param net_metrics Metrics
local function display_to_monitors(current, trend, in_metrics, out_metrics, net_metrics)
    R_monitor.foreach_monitor(
        function(monitor)
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.white)

            local color_current

            if current < (ALARM_THRESHOLD * 100) then
                color_current = colors.red
            elseif current < (CHARGE_THRESHOLD * 100) then
                color_current = colors.yellow
            else
                color_current = colors.green
            end

            monitor.clear()
        --    monitor.setTextScale(1)  -- Reset text scale

            local trend_fmt, color_trend = fmt.signed_and_color(trend)
            local net_fmt, color_net = fmt.signed_and_color(net_metrics.amps)

            local tier_in = tiers.get_color(in_metrics.tier)
            local tier_out = tiers.get_color(out_metrics.tier)
            local tier_net = tiers.get_color(net_metrics.tier)

            monitor.setTextScale(0.5)

            monitor.setCursorPos(1, 1)
            monitor.write("Current: ")
            R_monitor.write(monitor, color_current, current .. "%")

            monitor.setCursorPos(1, 2)
            monitor.write("Trend: ")
            R_monitor.write(monitor, color_trend, trend_fmt .. "%")

            monitor.setCursorPos(1, 3)
            monitor.write("Input:")

            monitor.setCursorPos(1, 4)
            monitor.write(in_metrics.amps .. " A (")
            R_monitor.write(monitor, tier_in, in_metrics.tier)
            monitor.write(")")

            monitor.setCursorPos(1, 5)
            monitor.write("Output:")

            monitor.setCursorPos(1, 6)
            monitor.write(out_metrics.amps .. " A (")
            R_monitor.write(monitor, tier_out, out_metrics.tier)
            monitor.write(")")

            monitor.setCursorPos(1, 7)
            monitor.write("Net:")

            monitor.setCursorPos(1, 8)
            R_monitor.write(monitor, color_net, net_fmt)
            monitor.write(" A (")
            R_monitor.write(monitor, tier_net, net_metrics.tier)
            monitor.write(")")
        end
    )
end

--- @param current number
--- @param trend number
--- @param in_metrics Metrics
--- @param out_metrics Metrics
--- @param net_metrics Metrics
local function display_to_terminal(current, trend, in_metrics, out_metrics, net_metrics)
    R_terminal.reset_terminal()

    local trend_fmt, _ = fmt.signed_and_color(trend)

    print("Current percentage: " .. current .. "%")
    print("Trend: " .. trend_fmt .. "%")
    print()
    print("Input: " .. in_metrics:report())
    print("Output: " .. out_metrics:report())
    print("Net: " .. net_metrics:report())
end

--- @class GTCEu_BatteryBuffer : GTCEu_EnergyInfoPeripheral, GTCEu_WorkablePeripheral
local GTCEu_BatteryBuffer = {}

--- @return GTCEu_BatteryBuffer
--- @return string
local function wait_for_battery()
    --- @type GTCEu_BatteryBuffer?
    local battery
    --- @type string?
    local battery_tier

    while battery == nil do
        --- @type GTCEu_BatteryBuffer?, string?
        local temp_battery, temp_tier = machine.find_machine("battery_buffer", GTCEu_BatteryBuffer)

        if temp_battery ~= nil and pcall(temp_battery.getEnergyStored) then
            battery = temp_battery
            battery_tier = temp_tier
        else
            R_terminal.reset_terminal()

            write("Detecting battery .")
            sleep(1)
            write(".")
            sleep(1)
            write(".")
            sleep(1)
        end
    end

    return battery, battery_tier --[[@as string]]
end

-- Check for connection (for example on server startup)

--- @type GTCEu_BatteryBuffer
local BATTERY
--- @type string
local BATTERY_TIER
local LAST_PERCENTAGE = 0.0

exec.loop_forever(
    UPDATE_INTERVAL_TICKS,
    -- init
    function()
        BATTERY, BATTERY_TIER = wait_for_battery()
    end,
    -- body
    function()
        --- @type number
        local percentage = BATTERY.getEnergyStored() / BATTERY.getEnergyCapacity()
        --- @type number
        local trend = percentage - LAST_PERCENTAGE

        local eu_in = BATTERY.getInputPerSec() / 20
        local eu_out = BATTERY.getOutputPerSec() / 20
        local eu_net = eu_in - eu_out

        --- @type Metrics
        local in_metrics = Metrics:new(eu_in)
        --- @type Metrics
        local out_metrics = Metrics:new(eu_out)
        --- @type Metrics
        local net_metrics = Metrics:new(eu_net)

        in_metrics:rescale(BATTERY_TIER)
        out_metrics:rescale(BATTERY_TIER)
        net_metrics:rescale(BATTERY_TIER)

        local rounded_current = R_math.round(percentage * 100, PRECISION_DISPLAYED)
        local rounded_trend = R_math.round(trend * 100, PRECISION_DISPLAYED)

        in_metrics.amps = R_math.round(in_metrics.amps, PRECISION_DISPLAYED)
        out_metrics.amps = R_math.round(out_metrics.amps, PRECISION_DISPLAYED)
        net_metrics.amps = R_math.round(net_metrics.amps, PRECISION_DISPLAYED)

        display_to_monitors(rounded_current, rounded_trend, in_metrics, out_metrics, net_metrics)
        display_to_terminal(rounded_current, rounded_trend, in_metrics, out_metrics, net_metrics)

        LAST_PERCENTAGE = percentage
    end,
    -- quit
    nil
)