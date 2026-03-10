-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/simple_energy_monitor.lua

local fmt = require "lib.cc.fmt"
local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"

local paint = require "lib.dr.paint"

local machine = require "lib.gt.machine"
local tiers = require "lib.gt.tiers"

local average_value = require "lib.average_value"
local class = require "lib.class"
local config = require "lib.config"
local exec = require "lib.exec"
local R_math = require "lib.math"
local R_table = require "lib.table"

local cfg_file = config.class.ConfigFile:new("monitor_battery_buffer")

local CHARGE_THRESHOLD = cfg_file:getNumber("CHARGE_THRESHOLD") or 0.6
local ALARM_THRESHOLD = cfg_file:getNumber("ALARM_THRESHOLD") or 0.3
local PRECISION_DISPLAYED = cfg_file:getNumber("PRECISION_DISPLAYED") or 2
local RENDER_TICK_DELAY = cfg_file:getNumber("RENDER_TICK_DELAY") or 5
local MACHINE = cfg_file:getString("MACHINE") or "battery_buffer"
local POWER_OVERRIDE = cfg_file:getString("POWER_OVERRIDE") or ""

-- The displays have a fixed max length, so the precision has to be limited to prevent overdraw
local PRECISION_PERCENTS = math.min(3, PRECISION_DISPLAYED)  -- ex. "--.---%"
local PRECISION_AMPS = math.min(3, PRECISION_DISPLAYED)  -- ex. "---.--- A"

local MAX_AMPS_DISPLAYED = math.pow(10, 6 - PRECISION_AMPS) - math.pow(10, -PRECISION_AMPS)  -- ex. "999.999 A" for PRECISION_AMPS = 3

-- Ensure that the defaults get properly saved
cfg_file:save()

local eu_in = average_value.class.AverageValue:new(20)
local eu_out = average_value.class.AverageValue:new(20)
--- @type number
local eu_net = 0.0

--- @type Painter
local painter = nil

local monitor_template_painter = paint.class.DeferredPixelPainter:new(14 * 2, 14 * 3, nil, nil, colors.white, colors.black)
monitor_template_painter
    :move({ x = 1, y = 1 })
    :text("Current: --.---%")
    :move({ x = 1, y = 2 })
    :text("Trend:  +--.---%")
    :move({ x = 1, y = 3 })
    :text("Input:")
    :move({ x = 1, y = 4 })
    :text(" ---.--- A | ---")
    :move({ x = 1, y = 5 })
    :text("Output:")
    :move({ x = 1, y = 6 })
    :text(" ---.--- A | ---")
    :move({ x = 1, y = 7 })
    :text("Net:")
    :move({ x = 1, y = 8 })
    :text("+---.--- A | ---")

local monitor_state_painter = paint.class.DeferredPixelPainter:new(14 * 2, 14 * 3, nil, nil, colors.white, colors.black)
monitor_state_painter
    :move({ x = 1 + #"Current: ", y = 1 })
    :clear({ count = PRECISION_PERCENTS + 4 })  -- count = #"--." + precision + #"%"
    :color(monitor_state_painter:recall("COLOR_CURRENT"), nil)
    :obj(monitor_state_painter:recall("CURRENT"))
    :move({ x = 1 + #"Trend:  ", y = 2 })
    :clear({ count = PRECISION_PERCENTS + 5 })  -- count = #"+--." + precision + #"%"
    :color(monitor_state_painter:recall("COLOR_TREND"), nil)
    :obj(monitor_state_painter:recall("TREND"))
    :move({ x = 2, y = 4 })
    :color("reset", nil)
    :clear({ count = PRECISION_AMPS + 4 })  -- count = #"---." + precision
    :offset(monitor_state_painter:recall("OFFSET_AMPS_IN"))
    :obj(monitor_state_painter:recall("AMPS_IN"))
    :move({ x = 2 + #"---.--- A | ", y = 4 })
    :clear({ count = 3 })
    :color(monitor_state_painter:recall("COLOR_IN_TIER"), nil)
    :text(monitor_state_painter:recall("IN_TIER"))
    :move({ x = 2, y = 6 })
    :color("reset", nil)
    :clear({ count = PRECISION_AMPS + 4 })  -- count = #"---." + precision
    :offset(monitor_state_painter:recall("OFFSET_AMPS_OUT"))
    :obj(monitor_state_painter:recall("AMPS_OUT"))
    :move({ x = 2 + #"---.--- A | ", y = 6 })
    :clear({ count = 3 })
    :color(monitor_state_painter:recall("COLOR_OUT_TIER"), nil)
    :text(monitor_state_painter:recall("OUT_TIER"))
    :move({ x = 1, y = 8 })
    :color("reset", nil)
    :clear({ count = PRECISION_AMPS + 5 })  -- count = #"+---." + precision
    :offset(monitor_state_painter:recall("OFFSET_AMPS_NET"))
    :color(monitor_state_painter:recall("COLOR_NET"), nil)
    :obj(monitor_state_painter:recall("AMPS_NET"))
    :move({ x = 1 + #"+---.--- A | ", y = 8 })
    :clear({ count = 3 })
    :color(monitor_state_painter:recall("COLOR_NET_TIER"), nil)
    :text(monitor_state_painter:recall("NET_TIER"))

--- @class MetricsDefinition : ClassDefinition
--- @field base nil
--- @field class MetricsDefinition
local Metrics = class.class("Metrics")

--- [override] Creates a new Metrics instance with the given parameters
--- @param get_energy fun() : number  The function from which to get the measured EU
--- @param tier string?  The tier of the machine being tracked, or nil to not rescale measured EU values
--- @return Metrics
function Metrics:new(get_energy, tier)
    --- @class Metrics : ClassInstance
    --- @field base nil
    --- @field class MetricsDefinition
    --- @field this Metrics
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
            --- @param amps number
            --- @param signed boolean
            --- @param colored boolean
            --- @return integer offset
            --- @return any formatted
            --- @return number color
            local function process_amps_text(amps, signed, colored)
                local abs_amps = math.abs(amps)

                if abs_amps > MAX_AMPS_DISPLAYED then
                    return 0, (amps > 0 and ">" or "<") .. MAX_AMPS_DISPLAYED, colors.orange
                end

                local num = 10
                local max_decimals = 6 - PRECISION_AMPS
                local decimals = 0

                for i = 1, max_decimals do
                    if abs_amps < num then
                        decimals = i
                        break
                    end

                    num = num * 10
                end

                -- Display with an offset

                local offset, value, color

                offset = max_decimals - decimals

                if signed then
                    value, color = fmt.signed_and_color(amps)
                else
                    value = amps
                    color = value > 0 and colors.green or (value < 0 and colors.red or colors.white)
                end

                return offset, value, colored and color or colors.white
            end

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

            monitor_state_painter:store("COLOR_CURRENT", color_current)
            monitor_state_painter:store("CURRENT", current)

            monitor_state_painter:store("COLOR_TREND", color_trend)
            monitor_state_painter:store("TREND", trend_fmt)

            local offset, formatted, color
            offset, formatted, _ = process_amps_text(in_amps, false, false)
            monitor_state_painter:store("OFFSET_AMPS_IN", { x = offset })
            monitor_state_painter:store("AMPS_IN", formatted)
            monitor_state_painter:store("COLOR_IN_TIER", tiers.get_color(in_tier))
            monitor_state_painter:store("IN_TIER", in_tier)

            offset, formatted, _ = process_amps_text(out_amps, false, false)
            monitor_state_painter:store("OFFSET_AMPS_OUT", { x = offset })
            monitor_state_painter:store("AMPS_OUT", formatted)
            monitor_state_painter:store("COLOR_OUT_TIER", tiers.get_color(out_tier))
            monitor_state_painter:store("OUT_TIER", out_tier)

            offset, formatted, color = process_amps_text(net_amps, true, true)
            monitor_state_painter:store("OFFSET_AMPS_NET", { x = offset })
            monitor_state_painter:store("AMPS_NET", formatted)
            monitor_state_painter:store("COLOR_NET", color)
            monitor_state_painter:store("COLOR_NET_TIER", tiers.get_color(net_tier))
            monitor_state_painter:store("NET_TIER", net_tier)

            monitor_template_painter:paint(monitor)
            monitor_state_painter:repaint(monitor)
        end
    )
end

--- @type GTCEu_EnergyInfoPeripheral
local BATTERY
--- @type string
local BATTERY_TIER
local LAST_PERCENTAGE = 0.0

--- @param current number
--- @param trend number
local function display_to_terminal(current, trend)
    R_terminal.reset_terminal()

    if not BATTERY_TIER then
        print("WARNING: Could not determine tier for connected battery")
        print("Set the default tier by running \"launcher config\" and modifying the \"POWER_OVERRIDE\" setting")
        print()
    end

    local net, net_tier = metrics_net:amps()

    print("Current percentage: " .. current .. "%")
    print("Trend: " .. fmt.signed(trend) .. "%")
    print()
    print("Input: " .. metrics_incoming:report())
    print("Output: " .. metrics_outgoing:report())
    print("Net: " .. fmt.signed(net) .. " A (" .. net_tier .. ")")
end

--- @return GTCEu_EnergyInfoPeripheral
--- @return string
local function wait_for_battery()
    --- @type GTCEu_EnergyInfoPeripheral?
    local battery
    --- @type string?
    local battery_tier

    while battery == nil do
        --- @type GTCEu_EnergyInfoPeripheral?, string?
        local temp_battery, temp_tier = machine.find_machine(MACHINE, true)

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

local tick = 1

exec.loop_forever(
    -- wait_interval
    1,
    -- init
    function()
        BATTERY, BATTERY_TIER = wait_for_battery()

        if POWER_OVERRIDE and #POWER_OVERRIDE > 0 and R_table.has_value(tiers.def, POWER_OVERRIDE) then
            BATTERY_TIER = POWER_OVERRIDE
        end

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
                    painter = paint.class.Painter:new(monitor)
                    new_painter = true
                end

                painter.terminal = monitor

                painter:begin()
                    :clean()
                    :reset()
                    :text("Current: --.")
                    :text("-", { count = PRECISION_DISPLAYED })
                    :text("%")
                    :nextline()
                    :text("Trend: +--.")
                    :text("-", { count = PRECISION_DISPLAYED })
                    :text("%")
                    :nextline()
                    :text("Input:")
                    :nextline()
                    :offset(1, nil)
                    :text("---.")
                    :text("-", { count = PRECISION_DISPLAYED })
                    :text(" A (---)")
                    :nextline()
                    :text("Output:")
                    :nextline()
                    :offset(1, nil)
                    :text("---.")
                    :text("-", { count = PRECISION_DISPLAYED })
                    :text(" A (---)")
                    :nextline()
                    :text("Net:")
                    :nextline()
                    :text("+---.")
                    :text("-", { count = PRECISION_DISPLAYED })
                    :text(" A (---)")
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

        tick = tick == RENDER_TICK_DELAY and 1 or tick + 1
    end,
    -- sleep_watchers
    nil,
    -- quit
    nil
)