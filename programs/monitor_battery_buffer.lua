-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/simple_energy_monitor.lua

local fmt = require "lib.cc.fmt"
local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"

local paint = require "lib.dr.paint"

local machine = require "lib.gt.machine"
local tiers = require "lib.gt.tiers"

local average_value = require "lib.average_value"
local class = require "lib.class"
local exec = require "lib.exec"
local R_math = require "lib.math"

local CHARGE_THRESHOLD = 0.6
local ALARM_THRESHOLD = 0.3
local PRECISION_DISPLAYED = 3
local UPDATE_INTERVAL_TICKS = 5

local eu_in = average_value.create(20)
local eu_out = average_value.create(20)
--- @type number
local eu_net = 0.0

--- @type Painter
local painter = nil

--- @class MetricsDefinition : ClassDefinition
local Metrics = class.class("Metrics")

--- [override] Creates a new Metrics instance with the given parameters
--- @param get_energy fun() : number  The function from which to get the measured EU
--- @param tier string?  The tier of the machine being tracked, or nil to not rescale measured EU values
--- @return Metrics
function Metrics:new(get_energy, tier)
    --- @class Metrics : ClassInstance
    local instance = Metrics:create_instance()

    --- @private
    --- The object from which to get the measured EU
    instance.get_energy = get_energy
    --- The tier of the machine being tracked, or nil to not rescale measured EU values
    instance.tier = tier

    --- Gets the Amperes and energy tier from the measured EU.<br/>
    --- If self:tier is set, the Amperes are rescaled to that tier.
    --- @return number
    --- @return string
    function instance:amps()
        local eu = self.get_energy()
        local amps, amps_tier

        if self.tier then
            amps, amps_tier = tiers.get_amps(eu, self.tier), self.tier --[[@as string]]
        else
            -- The tier needs to be calculated from the EU
            local required_tier = tiers.get_tier(eu)
            amps, amps_tier = tiers.get_amps(eu, required_tier), required_tier
        end

        amps = R_math.round(amps, PRECISION_DISPLAYED)

        return amps, amps_tier
    end

    --- Gets a string reporting the Amperes and energy tier
    function instance:report()
        local amps, amps_tier = self:amps()
        return amps .. " A (" .. amps_tier .. ")"
    end

    return instance
end

--- @type Metrics
local metrics_incoming
--- @type Metrics
local metrics_outgoing
--- @type Metrics
local metrics_net

--- @param current number
--- @param trend number
local function display_to_monitors(current, trend)
    R_monitor.foreach_monitor(
        function(monitor)
            local color_current

            if current < (ALARM_THRESHOLD * 100) then
                color_current = colors.red
            elseif current < (CHARGE_THRESHOLD * 100) then
                color_current = colors.yellow
            else
                color_current = colors.green
            end

            local trend_fmt, color_trend = fmt.signed_and_color(trend)

            local in_amps, in_tier = metrics_incoming:amps()
            local out_amps, out_tier = metrics_outgoing:amps()
            local net_amps, net_tier = metrics_net:amps()

            local net_fmt, color_net = fmt.signed_and_color(net_amps)

            painter.terminal = monitor

            painter:begin()
                -- Current: --.---%
                :move({ x = 1 + #"Current:" + 1, y = 1 })
                :erase(#"--.---%")
                :color(color_current, nil)
                :text(current .. "%")
                :color("reset", nil)
                -- Trend: +--.---%
                :move({ x = 1 + #"Trend:" + 1, y = 2 })
                :erase(#"+--.---%")
                :color(color_trend, nil)
                :text(trend_fmt .. "%")
                :color("reset", nil)
                -- Input:
                --  ---.--- A (---)
                :move({ x = 2, y = 4 })
                :anchor()
                :erase(#"---.---")
                :offset(in_amps < 10 and 2 or (in_amps < 100 and 1 or 0), nil)
                :obj(in_amps)
                :reset()
                :offset(#"---.--- A (", nil)
                :erase(4)
                :color(tiers.get_color(in_tier), nil)
                :text(in_tier)
                :color("reset", nil)
                :text(")")
                :deanchor()
                -- Output:
                --  ---.--- A (---)
                :move({ x = 2, y = 6 })
                :anchor()
                :erase(#"---.---")
                :offset(out_amps < 10 and 2 or (out_amps < 100 and 1 or 0), nil)
                :obj(out_amps)
                :reset()
                :offset(#"---.--- A (", nil)
                :erase(4)
                :color(tiers.get_color(out_tier), nil)
                :text(out_tier)
                :color("reset", nil)
                :text(")")
                :deanchor()
                -- Net:
                -- +---.--- A (---)
                :move({ x = 1, y = 8 })
                :anchor()
                :erase(#"+---.---")
                :offset(net_amps < 10 and 2 or (net_amps < 100 and 1 or 0), nil)
                :color(color_net, nil)
                :text(net_fmt)
                :color("reset", nil)
                :reset()
                :offset(#"+---.--- A (", nil)
                :color(tiers.get_color(net_tier), nil)
                :text(net_tier)
                :color("reset", nil)
                :text(")")
                :deanchor()
                :paint()
        end
    )
end

--- @param current number
--- @param trend number
local function display_to_terminal(current, trend)
    R_terminal.reset_terminal()

    local net, net_tier = metrics_net:amps()

    print("Current percentage: " .. current .. "%")
    print("Trend: " .. fmt.signed(trend) .. "%")
    print()
    print("Input: " .. metrics_incoming:report())
    print("Output: " .. metrics_outgoing:report())
    print("Net: " .. fmt.signed(net) .. " A (" .. net_tier .. ")")
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

local tick = 1

exec.loop_forever(
    -- wait_interval
    1,
    -- init
    function()
        BATTERY, BATTERY_TIER = wait_for_battery()

        eu_in:clear()
        eu_out:clear()
        eu_net = 0.0

        metrics_incoming = Metrics:new(function() return eu_in:get() end, BATTERY_TIER)
        metrics_outgoing = Metrics:new(function() return eu_out:get() end, BATTERY_TIER)
        metrics_net = Metrics:new(function() return eu_net end, BATTERY_TIER)

        -- Initialize the monitors with the base template

        local new_painter = false

        R_monitor.foreach_monitor(
            function(monitor)
                monitor.setBackgroundColor(colors.black)
                monitor.setTextColor(colors.white)
                monitor.setTextScale(0.5)

                if (not painter) or (not new_painter) then
                    painter = paint.create(monitor)
                    new_painter = true
                end

                painter.terminal = monitor

                painter:begin()
                    :clean()
                    :reset()
                    :text("Current: --.---%")
                    :nextline()
                    :text("Trend: +--.---%")
                    :nextline()
                    :text("Input:")
                    :nextline()
                    :offset(1, nil)
                    :text("---.--- A (---)")
                    :nextline()
                    :text("Output:")
                    :nextline()
                    :offset(1, nil)
                    :text("---.--- A (---)")
                    :nextline()
                    :text("Net:")
                    :nextline()
                    :text("+---.--- A (---)")
                    :paint()
            end
        )
    end,
    -- body
    function()
        eu_in:measure(BATTERY.getInputPerSec() / 20)
        eu_out:measure(BATTERY.getOutputPerSec() / 20)

        if tick == 1 then
            eu_net = eu_in:get() - eu_out:get()

            local percentage = BATTERY.getEnergyStored() / BATTERY.getEnergyCapacity()
            local trend = percentage - LAST_PERCENTAGE

            local rounded_current = R_math.round(percentage * 100, PRECISION_DISPLAYED)
            local rounded_trend = R_math.round(trend * 100, PRECISION_DISPLAYED)

            display_to_monitors(rounded_current, rounded_trend)
            display_to_terminal(rounded_current, rounded_trend)

            LAST_PERCENTAGE = percentage
        end

        tick = tick == UPDATE_INTERVAL_TICKS and 1 or tick + 1
    end,
    -- sleep_watchers
    nil,
    -- quit
    nil
)