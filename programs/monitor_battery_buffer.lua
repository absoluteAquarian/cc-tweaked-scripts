-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/simple_energy_monitor.lua

require "util.cc.fmt"
local monitor_ex = require "util.cc.monitor"
require "util.cc.terminal"

require "util.gt.machine"
local tiers = require "util.gt.tiers"

require "util.class"
require "util.exec"
require "util.math"
require "util.string"
require "util.try-catch"

local CHARGE_THRESHOLD = 0.6
local ALARM_THRESHOLD = 0.3
local PRECISION_DISPLAYED = 3
local UPDATE_INTERVAL_TICKS = 5

local Metrics = class(
    --- @param self table  The Metrics object to initialize
    --- @param eu number  The amount of EU this Metrics object should represent
    function(self, eu)
        self.eu = eu
        self.tier = tiers.get_tier(eu)
        self.amps = tiers.get_amps(eu, self.tier)
    end
)

--- Returns the amps and EU tier for the given Metrics table
function Metrics:report()
    return self.amps .. " A (" .. self.tier .. " )"
end

--- Adjusts the amps and EU tier of this Metrics object to match the given target tier, keeping the same total EU
--- @param target_tier string  The name of the tier to convert to
function Metrics:rescale(target_tier)
    self.amps = tiers.get_amps(self.eu, target_tier)
    self.tier = target_tier
end

local function display_to_monitors(current, trend, in_metrics, out_metrics, net_metrics)
    foreach_monitor(
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

            local trend_fmt, color_trend = signed_and_color(trend)
            local net_fmt, color_net = signed_and_color(net_metrics.amps)

            local tier_in = tiers.get_color(in_metrics.tier)
            local tier_out = tiers.get_color(out_metrics.tier)
            local tier_net = tiers.get_color(net_metrics.tier)

            monitor.setTextScale(0.5)

            monitor.setCursorPos(1, 1)
            monitor.write("Current:")
            monitor_ex.write(monitor, color_current, current .. "%")

            monitor.setCursorPos(1, 2)
            monitor.write("Trend:")
            monitor_ex.write(monitor, color_trend, trend_fmt .. "%")

            monitor.setCursorPos(1, 3)
            monitor.write("Input:")

            monitor.setCursorPos(1, 4)
            monitor.write(in_metrics.amps .. " A (")
            monitor_ex.write(monitor, tier_in, in_metrics.tier)
            monitor.write(")")

            monitor.setCursorPos(1, 5)
            monitor.write("Output:")

            monitor.setCursorPos(1, 6)
            monitor.write(out_metrics.amps .. " A (")
            monitor_ex.write(monitor, tier_out, out_metrics.tier)
            monitor.write(")")
            
            monitor.setCursorPos(1, 7)
            monitor.write("Net:")

            monitor.setCursorPos(1, 8)
            monitor_ex.write(monitor, color_net, net_fmt)
            monitor.write(" A (")
            monitor_ex.write(monitor, tier_net, net_metrics.tier)
            monitor.write(")")
        end
    )
end

local function display_to_terminal(current, trend, in_metrics, out_metrics, net_metrics, max_hint)
    reset_terminal()

    local trend_fmt, _ = signed_and_color(trend)

    print("Current percentage: " .. current .. "%")
    print("Trend: " .. trend_fmt .. "%")
    print()
    print("Input: " .. in_metrics:report())
    print("Output: " .. out_metrics:report())
    print("Net: " .. net_metrics:report())

    if max_hint then
        print()
        print("The max energy capacity is MAX_INT!")
        print("There might be more energy left as it can be displayed")
    end
end

local function wait_for_battery()
    local battery, battery_tier

    while battery == nil do
        local temp_battery, temp_tier = find_machine("battery_buffer")

        if temp_battery ~= nil and pcall(temp_battery.getEnergyStored) then
            battery = temp_battery
            battery_tier = temp_tier
        else
            reset_terminal()

            io.stdout:write("Detecting battery .")
            sleep(1)
            io.stdout:write(".")
            sleep(1)
            io.stdout:write(".")
            sleep(1)
        end
    end

    return battery, battery_tier
end

-- Check for connection (for example on server startup)

local BATTERY, BATTERY_TYPE = wait_for_battery()
local LAST_PERCENTAGE = 0

loop_forever(
    UPDATE_INTERVAL_TICKS,
    -- body
    function()
        local percentage = BATTERY.getEnergyStored() / BATTERY.getEnergyCapacity()
        local trend = percentage - LAST_PERCENTAGE

        local eu_in = BATTERY.getInputPerSec() / 20.0
        local eu_out = BATTERY.getOutputPerSec() / 20.0
        local eu_net = eu_in - eu_out

        local in_metrics = Metrics(eu_in)
        local out_metrics = Metrics(eu_out)
        local net_metrics = Metrics(eu_net)

        in_metrics:rescale(BATTERY_TYPE)
        out_metrics:rescale(BATTERY_TYPE)
        net_metrics:rescale(BATTERY_TYPE)

        local rounded_current = round(percentage * 100, PRECISION_DISPLAYED)
        local rounded_trend = round(trend * 100, PRECISION_DISPLAYED)

        in_metrics.amps = round(in_metrics.amps, PRECISION_DISPLAYED)
        out_metrics.amps = round(out_metrics.amps, PRECISION_DISPLAYED)
        net_metrics.amps = round(net_metrics.amps, PRECISION_DISPLAYED)

        display_to_monitors(rounded_current, rounded_trend, in_metrics, out_metrics, net_metrics)
        display_to_terminal(rounded_current, rounded_trend, in_metrics, out_metrics, net_metrics, BATTERY.getEnergyCapacity() == 2147483647)

        LAST_PERCENTAGE = percentage
    end,
    -- quit
    nil,
    -- restart
    function()
        BATTERY, BATTERY_TYPE = wait_for_battery()
    end
)