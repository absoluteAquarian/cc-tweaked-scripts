-- Included for debugging purposes
local inject = require "lib.inject"

-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/simple_energy_monitor.lua

local comms_api = require "lib.api.comms"

local fmt = require "lib.cc.fmt"
local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"

local canvas = require "lib.dr.canvas"
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
local GRAPH_MAX_AMPS = cfg_file:getInt("GRAPH_MAX_AMPS") or 64
local GRAPH_MAX_AMPS_NET = cfg_file:getInt("GRAPH_MAX_AMPS_NET") or 32

local function __force_config_values()
    cfg_file:setNumber("CHARGE_THRESHOLD", CHARGE_THRESHOLD)
    cfg_file:setNumber("ALARM_THRESHOLD", ALARM_THRESHOLD)
    cfg_file:setNumber("PRECISION_DISPLAYED", PRECISION_DISPLAYED)
    cfg_file:setNumber("RENDER_TICK_DELAY", RENDER_TICK_DELAY)
    cfg_file:setString("MACHINE", MACHINE)
    cfg_file:setString("POWER_OVERRIDE", POWER_OVERRIDE)
    cfg_file:setInt("GRAPH_MAX_AMPS", GRAPH_MAX_AMPS)
    cfg_file:setInt("GRAPH_MAX_AMPS_NET", GRAPH_MAX_AMPS_NET)
    cfg_file:save()
end

__force_config_values()

local PRECISION_PERCENTS
local TREND_MINIMUM
local TREND_MINIMUM_AT_100
local PRECISION_AMPS
local MAX_AMPS_DISPLAYED

local function __set_display_consts()
    -- The displays have a fixed max length, so the precision has to be limited to prevent overdraw
    PRECISION_PERCENTS = math.min(2, PRECISION_DISPLAYED)  -- ex. "--.--%"

    TREND_MINIMUM = math.pow(10, -PRECISION_PERCENTS)  -- ex. 0.01 for PRECISION_PERCENTS = 2
    TREND_MINIMUM_AT_100 = PRECISION_DISPLAYED > 0 and math.pow(10, -PRECISION_DISPLAYED + 1) or TREND_MINIMUM

    PRECISION_AMPS = math.min(3, PRECISION_DISPLAYED)  -- ex. "---.--- A"

    MAX_AMPS_DISPLAYED = math.pow(10, 6 - PRECISION_AMPS) - math.pow(10, -PRECISION_AMPS)  -- ex. "999.999 A" for PRECISION_AMPS = 3
end

__set_display_consts()

-- Ensure that the defaults get properly saved
cfg_file:save()

local eu_in = average_value.class.AverageValue:new(20)
local eu_out = average_value.class.AverageValue:new(20)
--- @type number
local eu_net = 0.0

local monitor_template_painter = paint.class.DeferredPixelPainter:new(15 * 2, 10 * 3, nil, nil, colors.white, colors.black, true)
monitor_template_painter
    :move({ x = 1, y = 1 })
    :text("Current: --.--%")
    :move({ x = 1, y = 2 })
    :text("Trend:  +--.--%")
    :move({ x = 1, y = 3 })
    :text("Input:")
    :move({ x = 1, y = 4 })
    :text(" ---.--- A  ---")
    :move({ x = 1, y = 5 })
    :text("Output:")
    :move({ x = 1, y = 6 })
    :text(" ---.--- A  ---")
    :move({ x = 1, y = 7 })
    :text("Net:")
    :move({ x = 1, y = 8 })
    :text("+---.--- A  ---")

local monitor_state_painter = paint.class.DeferredPixelPainter:new(15 * 2, 10 * 3, nil, nil, colors.white, colors.black, true)
monitor_state_painter
    :move({ x = 1 + #"Current: ", y = 1 })
    :clear({ count = #"--.--%" })
    :offset(monitor_state_painter:recall("OFFSET_CURRENT"))
    :color(monitor_state_painter:recall("COLOR_CURRENT"), nil)
    :obj(monitor_state_painter:recall("CURRENT"))
    :text("%")
    :move({ x = 1 + #"Trend:  ", y = 2 })
    :clear({ count = #"+--.--%" })
    :offset(monitor_state_painter:recall("OFFSET_TREND"))
    :color(monitor_state_painter:recall("COLOR_TREND"), nil)
    :obj(monitor_state_painter:recall("TREND"))
    :text("%")
    :move({ x = 2, y = 4 })
    :color("reset", nil)
    :clear({ count = #"---.---" })
    :offset(monitor_state_painter:recall("OFFSET_AMPS_IN"))
    :obj(monitor_state_painter:recall("AMPS_IN"))
    :move({ x = 2 + #"---.--- A  ", y = 4 })
    :clear({ count = 3 })
    :color(monitor_state_painter:recall("COLOR_IN_TIER"), nil)
    :text(monitor_state_painter:recall("IN_TIER"))
    :move({ x = 2, y = 6 })
    :color("reset", nil)
    :clear({ count = #"---.---" })
    :offset(monitor_state_painter:recall("OFFSET_AMPS_OUT"))
    :obj(monitor_state_painter:recall("AMPS_OUT"))
    :move({ x = 2 + #"---.--- A  ", y = 6 })
    :clear({ count = 3 })
    :color(monitor_state_painter:recall("COLOR_OUT_TIER"), nil)
    :text(monitor_state_painter:recall("OUT_TIER"))
    :move({ x = 1, y = 8 })
    :color("reset", nil)
    :clear({ count = #"+---.---" })
    :offset(monitor_state_painter:recall("OFFSET_AMPS_NET"))
    :color(monitor_state_painter:recall("COLOR_NET"), nil)
    :obj(monitor_state_painter:recall("AMPS_NET"))
    :move({ x = 1 + #"+---.--- A  ", y = 8 })
    :clear({ count = 3 })
    :color(monitor_state_painter:recall("COLOR_NET_TIER"), nil)
    :text(monitor_state_painter:recall("NET_TIER"))

local current_terminal = term.current()
--- @type integer, integer
local w, h = current_terminal.getSize()
w = w * 2
h = h * 3

local GRAPH_LEFT = 3
local GRAPH_RIGHT = w - 13
local GRAPH_TOP = 14 * 3 + 1
local GRAPH_BOTTOM = h - 1 * 3 - 2
local GRAPH_WIDTH = GRAPH_RIGHT - GRAPH_LEFT + 1
local GRAPH_HEIGHT = GRAPH_BOTTOM - GRAPH_TOP + 1
local GRAPH_MIDPOINT = math.ceil(GRAPH_TOP + GRAPH_HEIGHT / 2)
local GRAPH_HALFHEIGHT_TOP = GRAPH_MIDPOINT - GRAPH_TOP
local GRAPH_HALFHEIGHT_BOTTOM = GRAPH_BOTTOM - GRAPH_MIDPOINT

local terminal_template_painter = paint.class.DeferredPixelPainter:new(w, h, nil, nil, colors.white, colors.black, true)
terminal_template_painter
    -- Large energy bar
    :color(colors.blue, nil)
    :box({ left = -11, top = 3, right = -8, bottom = -6 })
    :move({ x = -1, y = -1 })
    :color("reset", nil)
    :text("--.--%", { tail_align = true })
    -- Reports
    :move({ x = 1, y = 1 })
    :text("     |   Amps   | Tier")
    :move({ x = 1, y = 2 })
    :text("Out: |  ---.--- |  ---")
    :move({ x = 1, y = 3 })
    :text("In:  |  ---.--- |  ---")
    :move({ x = 1, y = 4 })
    :text("Net: | +---.--- |  ---")
    -- Value graph
    :group()
    :fill({ x = GRAPH_LEFT, y = GRAPH_TOP, width = GRAPH_WIDTH, height = GRAPH_HEIGHT }, true)
    :line({ x = GRAPH_LEFT, y = GRAPH_TOP }, { x = GRAPH_LEFT, y = GRAPH_BOTTOM })
    :end_group()

--- @return DeferredPixelPainter
local function create_graph_slice_painter()
    local slice_painter = paint.class.DeferredPixelPainter:new(2, GRAPH_HEIGHT, colors.white, colors.gray, colors.white, colors.black, false)
    slice_painter
        :color(slice_painter:recall("COLOR"), nil)
        :line(slice_painter:recall("MEASURE_PREV"), slice_painter:recall("MEASURE"))
    return slice_painter
end

local NUM_GRAPH_SLICES = math.ceil(GRAPH_WIDTH / 2)
--- @type DeferredPixelPainter[]
local terminal_graph_slices = {}
--- @type integer[]
local graph_measure_locations = {}
local front_slice_index = 0

local terminal_state_painter = paint.class.DeferredPixelPainter:new(w, h, nil, nil, colors.white, colors.black, true)
terminal_state_painter
    -- Large energy bar
    :color(nil, colors.brown)
    :fill({ left = -10, top = 4, right = -9, bottom = -7 }, true)
    :color(terminal_state_painter:recall("CHARGE_COLOR"), nil)
    :fill(terminal_state_painter:recall("CHARGE_AREA"), true)
    :move({ x = -#"--.--%", y = -1 })
    :color(nil, "reset")
    :clear({ count = #"--.--%" })
    :offset(terminal_state_painter:recall("OFFSET_CURRENT"))
    :text(terminal_state_painter:recall("CURRENT_TEXT"))
    -- Reports
    :color("reset", "reset")
    :move({ x = 1 + #"Out: |  ", y = 2 })
    :clear({ count = #"---.---" })
    :offset(terminal_state_painter:recall("OFFSET_AMPS_OUT"))
    :obj(terminal_state_painter:recall("AMPS_OUT"))
    :move({ x = 1 + #"Out: |  ---.--- |  ", y = 2 })
    :clear({ count = 3 })
    :color(terminal_state_painter:recall("COLOR_OUT_TIER"), nil)
    :text(terminal_state_painter:recall("OUT_TIER"))
    :move({ x = 1 + #"In:  |  ", y = 3 })
    :color("reset", "reset")
    :clear({ count = #"---.---" })
    :offset(terminal_state_painter:recall("OFFSET_AMPS_IN"))
    :obj(terminal_state_painter:recall("AMPS_IN"))
    :move({ x = 1 + #"In:  |  ---.--- |  ", y = 3 })
    :clear({ count = 3 })
    :color(terminal_state_painter:recall("COLOR_IN_TIER"), nil)
    :text(terminal_state_painter:recall("IN_TIER"))
    :move({ x = 1 + #"Net: | ", y = 4 })
    :color("reset", "reset")
    :clear({ count = #"+---.---" })
    :offset(terminal_state_painter:recall("OFFSET_AMPS_NET"))
    :color(terminal_state_painter:recall("COLOR_NET"), nil)
    :obj(terminal_state_painter:recall("AMPS_NET"))
    :move({ x = 1 + #"Net: | +---.--- |  ", y = 4 })
    :color("reset", nil)
    :clear({ count = 3 })
    :color(terminal_state_painter:recall("COLOR_NET_TIER"), nil)
    :text(terminal_state_painter:recall("NET_TIER"))

local function build_charged_bar_area(percent, canvas_height)
    return
    {
        left = -10,
        top = 4 + math.floor((1 - (percent / 100)) * (canvas_height - 10)),
        right = -9,
        bottom = -7
    }
end

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

--- @param amps number
--- @param signed boolean
--- @param colored boolean
--- @return integer offset
--- @return any formatted
--- @return number color
local function process_amps_text(amps, signed, colored)
    local abs_amps = math.abs(amps)

    if abs_amps > MAX_AMPS_DISPLAYED then
        return 0, (amps > 0 and 1 or -1) * MAX_AMPS_DISPLAYED, colors.orange
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

--- @type GTCEu_EnergyInfoPeripheral
local BATTERY
--- @type string
local BATTERY_TIER
local LAST_PERCENTAGE = 0.0
local TREND_SIGN = 0

local function display_to_one_monitor(monitor, current, trend)
    local color_current

    if current < (ALARM_THRESHOLD * 100) then
        color_current = colors.red
    elseif current < (CHARGE_THRESHOLD * 100) then
        color_current = colors.yellow
    else
        color_current = colors.green
    end

    local offset_current

    if current == 100 then
        offset_current = 0

        -- Force the trend to use at most 1 decimal
        if PRECISION_PERCENTS > 1 then
            trend = R_math.round(trend, 1)
        end
    else
        offset_current = current < 10 and 1 or 0
    end

    local offset_trend
    local too_small = false

    if trend == 0 then
        -- Special case
        offset_trend = (current == 100) and 2 or 1

        if TREND_SIGN ~= 0 then
            -- Not actually zero, just too small
            trend = TREND_SIGN * (current == 100 and TREND_MINIMUM_AT_100 or TREND_MINIMUM)
            offset_trend = offset_trend - 1
            too_small = true
        end
    elseif math.abs(trend) < 10 then
        offset_trend = 1
    else
        offset_trend = 0
    end

    local trend_fmt, color_trend = fmt.signed_and_color(trend)

    local in_amps, in_tier = metrics_incoming:amps()
    local out_amps, out_tier = metrics_outgoing:amps()
    local net_amps, net_tier = metrics_net:amps()

    monitor_state_painter:store("OFFSET_CURRENT", { x = offset_current })
    monitor_state_painter:store("COLOR_CURRENT", color_current)
    monitor_state_painter:store("CURRENT", current)

    monitor_state_painter:store("OFFSET_TREND", { x = offset_trend })
    monitor_state_painter:store("COLOR_TREND", color_trend)
    monitor_state_painter:store("TREND", too_small and ("<" .. trend_fmt) or trend_fmt)

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

    monitor_state_painter:repaint(monitor)
end

--- @param current number
--- @param trend number
local function display_to_monitors(current, trend)
    R_monitor.foreach_monitor(
        function(monitor)
            display_to_one_monitor(monitor, current, trend)
        end
    )
end

--- @param current number
--- @param trend number
local function display_to_terminal(current, trend)
    local color_current

    if current < (ALARM_THRESHOLD * 100) then
        color_current = colors.red
    elseif current < (CHARGE_THRESHOLD * 100) then
        color_current = colors.yellow
    else
        color_current = colors.green
    end

    local offset_current = current < 10 and 1 or 0

    terminal_state_painter:store("CHARGE_COLOR", color_current)
    terminal_state_painter:store("CHARGE_AREA", build_charged_bar_area(current, h))
    terminal_state_painter:store("OFFSET_CURRENT", { x = offset_current })
    terminal_state_painter:store("CURRENT_TEXT", current .. "%")

    local in_amps, in_tier = metrics_incoming:amps()
    local out_amps, out_tier = metrics_outgoing:amps()
    local net_amps, net_tier = metrics_net:amps()

    local offset, formatted, color
    offset, formatted, _ = process_amps_text(in_amps, false, false)
    terminal_state_painter:store("OFFSET_AMPS_IN", { x = offset })
    terminal_state_painter:store("AMPS_IN", formatted)
    terminal_state_painter:store("COLOR_IN_TIER", tiers.get_color(in_tier))
    terminal_state_painter:store("IN_TIER", in_tier)

    offset, formatted, _ = process_amps_text(out_amps, false, false)
    terminal_state_painter:store("OFFSET_AMPS_OUT", { x = offset })
    terminal_state_painter:store("AMPS_OUT", formatted)
    terminal_state_painter:store("COLOR_OUT_TIER", tiers.get_color(out_tier))
    terminal_state_painter:store("OUT_TIER", out_tier)

    offset, formatted, color = process_amps_text(net_amps, true, true)
    terminal_state_painter:store("OFFSET_AMPS_NET", { x = offset })
    terminal_state_painter:store("AMPS_NET", formatted)
    terminal_state_painter:store("COLOR_NET", color)
    terminal_state_painter:store("COLOR_NET_TIER", tiers.get_color(net_tier))
    terminal_state_painter:store("NET_TIER", net_tier)

    terminal_state_painter:repaint(current_terminal)

    if #terminal_graph_slices < NUM_GRAPH_SLICES then
        local slice_painter = create_graph_slice_painter()
        table.insert(terminal_graph_slices, slice_painter)
        table.insert(graph_measure_locations, 0)
        front_slice_index = #terminal_graph_slices
    end

    -- Record the measurement

    local slice_painter = terminal_graph_slices[front_slice_index]
    local measurement = math.max(-GRAPH_MAX_AMPS_NET, math.min(GRAPH_MAX_AMPS_NET, net_amps))
    local scaled_measurement = R_math.integer((measurement / GRAPH_MAX_AMPS_NET) * (measurement > 0 and GRAPH_HALFHEIGHT_TOP or GRAPH_HALFHEIGHT_BOTTOM))

    local graph_position = GRAPH_MIDPOINT - GRAPH_TOP - scaled_measurement

    if #terminal_graph_slices == 1 then
        -- First slice should have both measurements at the same height

        slice_painter:store("MEASURE_PREV", { x = 1, y = graph_position })
    else
        -- Use the previous slice's measurement

        local previous_index = front_slice_index == 1 and #terminal_graph_slices or front_slice_index - 1
        local previous_measurement = graph_measure_locations[previous_index]
        slice_painter:store("MEASURE_PREV", { x = 1, y = previous_measurement })
    end

    slice_painter:store("MEASURE", { x = 2, y = graph_position })
    graph_measure_locations[front_slice_index] = graph_position

    local slice_color = measurement > 0 and colors.green or (measurement < 0 and colors.red or colors.white)
    slice_painter:store("COLOR", slice_color)

    local iter_index = front_slice_index
    local position_index = 1

    repeat
        -- Set the position of the slices

        local next_index = iter_index == 1 and #terminal_graph_slices or iter_index - 1

        slice_painter = terminal_graph_slices[iter_index]

        local origin_texel_x, origin_texel_y = canvas.pixel_to_texel(GRAPH_RIGHT - position_index * 2, GRAPH_TOP)
        slice_painter:set_origin(origin_texel_x, origin_texel_y)

        iter_index = next_index
        position_index = position_index + 1
    until iter_index == front_slice_index

    -- Prepare for the next render tick

    front_slice_index = front_slice_index == #terminal_graph_slices and 1 or front_slice_index + 1

    for _, slice in ipairs(terminal_graph_slices) do
        slice:repaint(current_terminal)
    end
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

local COMMS_CONFIG_REQUEST = "mbb:config_request"
local COMMS_CONFIG_RESPONSE = "mbb:config_response"
local COMMS_BATTERY_VALUES = "mbb:values"
local COMMS_BATTERY_DISCONNECT = "mbb:disconnect"

if pocket then
    --- @type integer
    local target_id

    --- @type number, number
    local eu_in_value, eu_out_value = 0, 0

    local painted_template = false

    -- Use the comms API to get the data for the buffer
    comms_api.register_data_callback(
        function(sender, ...)
            if sender ~= target_id then return end

            local msg = select(1, ...)

            if msg == COMMS_CONFIG_RESPONSE then
                -- Force the config on this program to match the sender's config
                local temp_charge_threshold, temp_alarm_threshold, temp_precision_displayed, temp_render_tick_delay, temp_machine, temp_power_override, temp_graph_max_amps, temp_graph_max_amps_net = select(2, ...)

                if temp_charge_threshold then CHARGE_THRESHOLD = temp_charge_threshold end
                if temp_alarm_threshold then ALARM_THRESHOLD = temp_alarm_threshold end
                if temp_precision_displayed then PRECISION_DISPLAYED = temp_precision_displayed end
                if temp_render_tick_delay then RENDER_TICK_DELAY = temp_render_tick_delay end
                if temp_machine then MACHINE = temp_machine end
                if temp_power_override then POWER_OVERRIDE = temp_power_override end
                if temp_graph_max_amps then GRAPH_MAX_AMPS = temp_graph_max_amps end
                if temp_graph_max_amps_net then GRAPH_MAX_AMPS_NET = temp_graph_max_amps_net end

                __force_config_values()
                __set_display_consts()

                if POWER_OVERRIDE and #POWER_OVERRIDE > 0 and R_table.has_value(tiers.def, POWER_OVERRIDE) then
                    BATTERY_TIER = POWER_OVERRIDE
                end

                metrics_incoming.tier = BATTERY_TIER
                metrics_outgoing.tier = BATTERY_TIER
                metrics_net.tier = BATTERY_TIER
            elseif msg == COMMS_BATTERY_VALUES then
                -- Update the display with the received values

                --- @type number, number
                local percentage, trend

                local temp_percentage, temp_trend, temp_eu_in, temp_eu_out = select(2, ...)

                percentage = temp_percentage or 0
                trend = temp_trend or 0
                eu_in_value = temp_eu_in or 0
                eu_out_value = temp_eu_out or 0

                metrics_incoming.tier = BATTERY_TIER
                metrics_outgoing.tier = BATTERY_TIER
                metrics_net.tier = BATTERY_TIER

                if not painted_template then
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.white)
                    term.clear()

                    monitor_template_painter:repaint(current_terminal)
                    painted_template = true
                end

                display_to_one_monitor(
                    current_terminal,
                    R_math.round(percentage * 100, PRECISION_DISPLAYED),
                    R_math.round(trend * 100, PRECISION_DISPLAYED)
                )
            elseif msg == COMMS_BATTERY_DISCONNECT then
                R_terminal.reset_terminal()
                painted_template = false

                print("Battery disconnected.")
                write(string.format("Waiting for computer %d...", target_id))
            end
        end
    )

    exec.loop_forever(
        -- wait_interval
        1,
        -- init
        function()
            ::retry::
            R_terminal.reset_terminal()
            write("Target computer ID: ")

            local temp_id = tonumber(read())
            if not temp_id or temp_id <= 0 or temp_id > 65535 or temp_id % 1 ~= 0 then
                goto retry
            end

            target_id = temp_id
            R_terminal.reset_terminal()
            write(string.format("Waiting for computer %d...", target_id))

            metrics_incoming = Metrics:new(function() return eu_in_value end)
            metrics_outgoing = Metrics:new(function() return eu_out_value end)
            metrics_net = Metrics:new(function() return eu_in_value - eu_out_value end)

            comms_api.send(target_id, COMMS_CONFIG_REQUEST)

            painted_template = false
        end,
        -- body
        function() end,
        -- sleep_watchers
        exec.class.EventWatcher:new()
            :add(comms_api.get_event_contexts())
        ,
        -- quit
        nil
    )

    return
end

comms_api.register_data_callback(
    function(sender, ...)
        local msg = select(1, ...)

        if msg == COMMS_CONFIG_REQUEST then
            -- Send the config to the requester
            comms_api.send(
                sender,
                COMMS_CONFIG_RESPONSE,
                CHARGE_THRESHOLD,
                ALARM_THRESHOLD,
                PRECISION_DISPLAYED,
                RENDER_TICK_DELAY,
                MACHINE,
                POWER_OVERRIDE,
                GRAPH_MAX_AMPS,
                GRAPH_MAX_AMPS_NET
            )
        end
    end
)

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

        R_monitor.foreach_monitor(
            function(monitor)
                monitor.setBackgroundColor(colors.black)
                monitor.setTextColor(colors.white)
                monitor.setTextScale(0.5)
                monitor.clear()

                monitor_template_painter:paint(monitor)
            end
        )

        term.clear()

        terminal_template_painter:paint(current_terminal)

        terminal_graph_slices = {}
        graph_measure_locations = {}
        front_slice_index = 0
    end,
    -- body
    function()
        if (not BATTERY) or (not peripheral.isPresent(peripheral.getName(BATTERY))) then
            -- The battery was removed, reinitialize to wait for it again
            comms_api.broadcast(COMMS_BATTERY_DISCONNECT)
            return false
        end

        eu_in:measure(BATTERY.getInputPerSec() / 20)
        eu_out:measure(BATTERY.getOutputPerSec() / 20)

        if tick == 1 then
            local eu_in_value = eu_in:get()
            local eu_out_value = eu_out:get()
            eu_net = eu_in_value - eu_out_value

            local percentage = BATTERY.getEnergyStored() / BATTERY.getEnergyCapacity()
            local trend = percentage - LAST_PERCENTAGE

            TREND_SIGN = trend > 0 and 1 or (trend < 0 and -1 or 0)

            local rounded_current = R_math.round(percentage * 100, PRECISION_DISPLAYED)
            local rounded_trend = R_math.round(trend * 100, PRECISION_DISPLAYED)

            display_to_monitors(rounded_current, rounded_trend)
            display_to_terminal(rounded_current, rounded_trend)

            -- comms API
            comms_api.broadcast(COMMS_BATTERY_VALUES, percentage, trend, eu_in_value, eu_out_value)

            LAST_PERCENTAGE = percentage
        end

        tick = tick == RENDER_TICK_DELAY and 1 or tick + 1
    end,
    -- sleep_watchers
    exec.class.EventWatcher:new()
        :add(comms_api.get_event_contexts())
    ,
    -- quit
    nil
)