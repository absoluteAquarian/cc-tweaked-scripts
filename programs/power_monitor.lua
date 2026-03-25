local comms_api = require "lib.api.comms"

local fmt = require "lib.cc.fmt"
local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"

local canvas = require "lib.dr.canvas"
local paint = require "lib.dr.paint"

local machine = require "lib.gt.machine"
local tiers = require "lib.gt.tiers"

local average_value = require "lib.average_value"
local config = require "lib.config"
local exec = require "lib.exec"
local R_math = require "lib.math"
local R_table = require "lib.table"

local cfg_file = config.class.ConfigFile:new("power_monitor")

local CHARGE_THRESHOLD = cfg_file:getNumber("CHARGE_THRESHOLD") or 0.6
local ALARM_THRESHOLD = cfg_file:getNumber("ALARM_THRESHOLD") or 0.3
local PRECISION_DISPLAYED = cfg_file:getNumber("PRECISION_DISPLAYED") or 2
local RENDER_TICK_DELAY = cfg_file:getNumber("RENDER_TICK_DELAY") or 5
local MACHINE = cfg_file:getString("MACHINE") or "power_substation"
local POWER_OVERRIDE = cfg_file:getString("POWER_OVERRIDE") or "IV"

local function __force_config_values()
    cfg_file:setNumber("CHARGE_THRESHOLD", CHARGE_THRESHOLD)
    cfg_file:setNumber("ALARM_THRESHOLD", ALARM_THRESHOLD)
    cfg_file:setNumber("PRECISION_DISPLAYED", PRECISION_DISPLAYED)
    cfg_file:setNumber("RENDER_TICK_DELAY", RENDER_TICK_DELAY)
    cfg_file:setString("MACHINE", MACHINE)
    cfg_file:setString("POWER_OVERRIDE", POWER_OVERRIDE)
    cfg_file:save()
end

__force_config_values()

local PRECISION_PERCENTS
local TREND_MINIMUM
local TREND_MINIMUM_AT_100
local LOAD_MINIMUM
local MAX_LOAD_DISPLAYED
local PRECISION_AMPS
local AMPS_MINIMUM
local MAX_AMPS_DISPLAYED

local function __set_display_consts()
    -- The displays have a fixed max length, so the precision has to be limited to prevent overdraw
    PRECISION_PERCENTS = math.min(2, PRECISION_DISPLAYED)  -- ex. "--.--%"

    TREND_MINIMUM = math.pow(10, -PRECISION_PERCENTS)  -- ex. 0.01 for PRECISION_PERCENTS = 2
    TREND_MINIMUM_AT_100 = PRECISION_DISPLAYED > 0 and math.pow(10, -PRECISION_DISPLAYED + 1) or TREND_MINIMUM

    LOAD_MINIMUM = math.pow(10, -PRECISION_PERCENTS)  -- ex. 0.01% for PRECISION_PERCENTS = 2
    MAX_LOAD_DISPLAYED = 1000 - math.pow(10, -PRECISION_PERCENTS)  -- ex. 999.99% for PRECISION_PERCENTS = 2

    PRECISION_AMPS = math.min(3, PRECISION_DISPLAYED)  -- ex. "---.--- A"

    AMPS_MINIMUM = math.pow(10, -PRECISION_AMPS)  -- ex. 0.001 A for PRECISION_AMPS = 3
    MAX_AMPS_DISPLAYED = math.pow(10, 6 - PRECISION_AMPS) - math.pow(10, -PRECISION_AMPS)  -- ex. "999.999 A" for PRECISION_AMPS = 3
end

__set_display_consts()

local eu_out = average_value.class.AverageValue:new(20)

local painter_template_monitor
local painter_state_monitor
local painter_template_pocket
local painter_state_pocket

if not pocket then
    painter_template_monitor = paint.class.DeferredPixelPainter:new(15 * 2, 10 * 3, colors.white, colors.black, colors.white, colors.black, false)
    painter_template_monitor
        :move({ x = 1, y = 1 })
        :text("Stored:  --.--%")
        :move({ x = 1, y = 2 })
        :color(nil, colors.brown)
        :fill({ left = 2, right = -2, top = 1 * 3 + 1, bottom = 2 * 3 }, true)
        :color(nil, "reset")
        :move({ x = 1, y = 3 })
        :text("Trend:  +--.--%")
        :move({ x = 1, y = 4 })
        :text("Load:   ---.--%")
        :move({ x = 1, y = 5 })
        :color(nil, colors.brown)
        :fill({ left = 2, right = -2, top = 4 * 3 + 1, bottom = 5 * 3 }, true)
        :color(nil, "reset")
        :move({ x = 1, y = 6 })
        :text(" ---.--- A  ---")

    painter_state_monitor = paint.class.DeferredPixelPainter:new(15 * 2, 10 * 3, nil, nil, colors.white, colors.black, true)
    painter_state_monitor
        :move({ x = 1 + #"Stored:  ", y = 1 })
        :clear({ count = #"--.--%" })
        :offset(painter_state_monitor:recall("OFFSET_STORED"))
        :color(painter_state_monitor:recall("COLOR_STORED"), nil)
        :obj(painter_state_monitor:recall("STORED"))
        :text("%")
        :color(nil, colors.brown)
        :fill(painter_state_monitor:recall("FILL_AREA_STORED"), false)
        :color("reset", "reset")
        :move({ x = 1 + #"Trend: ", y = 3 })
        :clear({ count = #"+--.--%" })
        :offset(painter_state_monitor:recall("OFFSET_TREND"))
        :color(painter_state_monitor:recall("COLOR_TREND"), nil)
        :text(painter_state_monitor:recall("VERYSMALL_TREND"))
        :text(painter_state_monitor:recall("SIGN_TREND"))
        :obj(painter_state_monitor:recall("TREND"))
        :text("%")
        :color("reset", nil)
        :move({ x = 1 + #"Load:  ", y = 4 })
        :clear({ count = #"---.--%" })
        :offset(painter_state_monitor:recall("OFFSET_LOAD"))
        :color(painter_state_monitor:recall("COLOR_LOAD"), nil)
        :text(painter_state_monitor:recall("LOAD_EXTREME"))
        :obj(painter_state_monitor:recall("LOAD"))
        :text("%")
        :color(nil, colors.brown)
        :fill(painter_state_monitor:recall("FILL_AREA_LOAD"), false)
        :color("reset", "reset")
        :move({ x = 1, y = 6 })
        :clear({ count = #" ---.---" })
        :offset(painter_state_monitor:recall("OFFSET_AMPS"))
        :color(painter_state_monitor:recall("COLOR_AMPS"), nil)
        :text(painter_state_monitor:recall("AMPS_EXTREME"))
        :obj(painter_state_monitor:recall("AMPS"))
        :move({ x = 1 + #" ---.--- A  ", y = 6 })
        :color(painter_state_monitor:recall("COLOR_AMPS_TIER"), nil)
        :text(painter_state_monitor:recall("TIER_AMPS"))
else
    painter_template_pocket = paint.class.DeferredPixelPainter:new(26 * 3, 19 * 3, colors.white, colors.black, colors.white, colors.black, false)
    painter_template_pocket
        :move({ x = 1, y = 1 })
        :text("Stored:             --.--%")
        :move({ x = 1, y = 2 })
        :color(nil, colors.brown)
        :fill({ left = 2, right = -2, top = 1 * 3 + 1, bottom = 2 * 3 }, true)
        :color(nil, "reset")
        :move({ x = 1, y = 3 })
        :text("Trend:             +--.--%")
        :move({ x = 1, y = 4 })
        :text("Load:              ---.--%")
        :move({ x = 1, y = 5 })
        :color(nil, colors.brown)
        :fill({ left = 2, right = -2, top = 4 * 3 + 1, bottom = 5 * 3 }, true)
        :color(nil, "reset")
        :move({ x = 1, y = 6 })
        :text("            ---.--- A  ---")

    painter_state_pocket = paint.class.DeferredPixelPainter:new(26 * 3, 19 * 3, nil, nil, colors.white, colors.black, true)
    painter_state_pocket
        :move({ x = 1 + #"Stored:  ", y = 1 })
        :clear({ count = #"--.--%" })
        :offset(painter_state_pocket:recall("OFFSET_STORED"))
        :color(painter_state_pocket:recall("COLOR_STORED"), nil)
        :obj(painter_state_pocket:recall("STORED"))
        :text("%")
        :color(nil, colors.brown)
        :fill(painter_state_pocket:recall("FILL_AREA_STORED"), false)
        :color("reset", "reset")
        :move({ x = 1 + #"Trend: ", y = 3 })
        :clear({ count = #"+--.--%" })
        :offset(painter_state_pocket:recall("OFFSET_TREND"))
        :color(painter_state_pocket:recall("COLOR_TREND"), nil)
        :text(painter_state_pocket:recall("VERYSMALL_TREND"))
        :text(painter_state_pocket:recall("SIGN_TREND"))
        :obj(painter_state_pocket:recall("TREND"))
        :text("%")
        :color("reset", nil)
        :move({ x = 1 + #"Load:  ", y = 4 })
        :clear({ count = #"---.--%" })
        :offset(painter_state_pocket:recall("OFFSET_LOAD"))
        :color(painter_state_pocket:recall("COLOR_LOAD"), nil)
        :text(painter_state_pocket:recall("LOAD_EXTREME"))
        :obj(painter_state_pocket:recall("LOAD"))
        :text("%")
        :color(nil, colors.brown)
        :fill(painter_state_pocket:recall("FILL_AREA_LOAD"), false)
        :color("reset", "reset")
        :move({ x = 1, y = 6 })
        :clear({ count = #" ---.---" })
        :offset(painter_state_pocket:recall("OFFSET_AMPS"))
        :color(painter_state_pocket:recall("COLOR_AMPS"), nil)
        :text(painter_state_pocket:recall("AMPS_EXTREME"))
        :obj(painter_state_pocket:recall("AMPS"))
        :move({ x = 1 + #" ---.--- A  ", y = 6 })
        :color(painter_state_pocket:recall("COLOR_AMPS_TIER"), nil)
        :text(painter_state_pocket:recall("TIER_AMPS"))
end

--- @type Metrics
local metrics_outgoing

--- @param amps number
--- @return integer offset
--- @return any formatted
--- @return boolean extreme
local function process_amps_text(amps)
    if amps > MAX_AMPS_DISPLAYED then
        return 0, MAX_AMPS_DISPLAYED, true
    elseif amps < AMPS_MINIMUM then
        return 6 - PRECISION_AMPS, AMPS_MINIMUM, true
    end

    local num = 10
    local max_decimals = 6 - PRECISION_AMPS
    local decimals = 0

    for i = 1, max_decimals do
        if amps < num then
            decimals = i
            break
        end

        num = num * 10
    end

    return max_decimals - decimals, amps, false
end

--- @type GTCEu_EnergyInfoPeripheral
local SUBSTATION
--- @type string
local SUBSTATION_TIER
local LAST_PERCENTAGE = 0.0
local TREND_SIGN = 0
local LOAD_SIGN = 0

--- @param target table
--- @param state_painter DeferredPixelPainter
--- @param current number
--- @param trend number
--- @param load number
--- @param inner_space integer
local function display(target, state_painter, current, trend, load, inner_space)
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

    local color_trend = TREND_SIGN > 0 and colors.green or (TREND_SIGN < 0 and colors.red or colors.white)

    local out_amps, out_tier = metrics_outgoing:amps(PRECISION_AMPS)

    state_painter:store("OFFSET_STORED", { x = offset_current + inner_space })
    state_painter:store("COLOR_STORED", color_current)
    state_painter:store("STORED", current)

    local state_canvas = state_painter.canvas
    local w = state_canvas.pixel_width
    local h = state_canvas.pixel_height

    --- @type CanvasArea
    local area = {
        left = 2,
        right = -2 - math.ceil((current / 100) * (w - 4)),
        top = 1 * 3 + 1,
        bottom = 2 * 3
    }

    state_painter:store("FILL_AREA_STORED", area)

    state_painter:store("OFFSET_TREND", { x = offset_trend + inner_space })
    state_painter:store("COLOR_TREND", color_trend)
    state_painter:store("VERYSMALL_TREND", too_small and "<" or " ")
    state_painter:store("SIGN_TREND", TREND_SIGN > 0 and "+" or (TREND_SIGN < 0 and "" or " "))
    state_painter:store("TREND", trend)

    local color_load

    if load < 50 then
        color_load = colors.green
    elseif load < 85 then
        color_load = colors.yellow
    else
        color_load = colors.red
    end

    local offset_load
    local load_extreme = false

    if load < 10 then
        offset_load = 2

        if LOAD_SIGN ~= 0 then
            -- Not actually zero, just too small
            load = LOAD_MINIMUM
            offset_load = offset_load - 1
            load_extreme = true
        end
    elseif load < 100 then
        offset_load = 1
    else
        offset_load = 0

        if load > MAX_LOAD_DISPLAYED then
            load = MAX_LOAD_DISPLAYED
            load_extreme = true
        end
    end

    state_painter:store("OFFSET_LOAD", { x = offset_load + inner_space })
    state_painter:store("COLOR_LOAD", color_load)
    state_painter:store("LOAD_EXTREME", load_extreme and (load >= 100 and ">" or "<") or " ")
    state_painter:store("LOAD", load)

    area = {
        left = 2,
        right = -2 - math.ceil((1 - math.min(100, load) / 100) * (w - 4)),
        top = 4 * 3 + 1,
        bottom = 5 * 3
    }

    state_painter:store("FILL_AREA_LOAD", area)

    local amps_offset, amps_value, extreme = process_amps_text(out_amps)

    state_painter:store("OFFSET_AMPS", { x = amps_offset + inner_space })
    state_painter:store("COLOR_AMPS", out_amps > 0 and colors.green or (out_amps < 0 and colors.red or colors.white))
    state_painter:store("AMPS_EXTREME", extreme and (out_amps < 1 and "<" or ">") or " ")
    state_painter:store("AMPS", amps_value)
    state_painter:store("COLOR_AMPS_TIER", tiers.get_color(out_tier))
    state_painter:store("TIER_AMPS", out_tier)

    state_painter:repaint(target)
end

--- @return GTCEu_EnergyInfoPeripheral
local function wait_for_substation()
    --- @type GTCEu_EnergyInfoPeripheral
    local substation

    while substation == nil do
        --- @type GTCEu_EnergyInfoPeripheral?, string?
        local temp_substation, _ = machine.find_machine(MACHINE, true)

        if temp_substation ~= nil and pcall(temp_substation.getEnergyStored) then
            substation = temp_substation
        else
            R_terminal.reset_terminal()

            write("Detecting substation .")
            sleep(1)
            write(".")
            sleep(1)
            write(".")
            sleep(1)
        end
    end

    return substation
end

local COMMS_CONFIG_REQUEST = "pm:config_request"
local COMMS_CONFIG_RESPONSE = "pm:config_response"
local COMMS_SUBSTATION_VALUES = "pm:values"
local COMMS_SUBSTATION_DISCONNECT = "pm:disconnect"
local COMMS_GENERATED_POWER = "tr:report"

--- @type integer, integer
local eu_in_value, eu_out_value = 0, 0

if pocket then
    --- @type integer
    local target_id
    local painted_template = false

    local function __on_target_disconnected()
        R_terminal.reset_terminal()
        painted_template = false

        print("Substation disconnected.")
        write(string.format("Waiting for computer %d...", target_id))
    end

    -- Use the comms API to get the data for the buffer
    comms_api.register_data_callback(
        function(sender, ...)
            if sender ~= target_id then return end

            local msg = select(1, ...)

            if msg == COMMS_CONFIG_RESPONSE then
                -- Force the config on this program to match the sender's config
                local temp_charge_threshold, temp_alarm_threshold, temp_precision_displayed, temp_render_tick_delay, temp_machine, temp_power_override = select(2, ...)

                if temp_charge_threshold then CHARGE_THRESHOLD = temp_charge_threshold end
                if temp_alarm_threshold then ALARM_THRESHOLD = temp_alarm_threshold end
                if temp_precision_displayed then PRECISION_DISPLAYED = temp_precision_displayed end
                if temp_render_tick_delay then RENDER_TICK_DELAY = temp_render_tick_delay end
                if temp_machine then MACHINE = temp_machine end
                if temp_power_override then POWER_OVERRIDE = temp_power_override end

                __force_config_values()
                __set_display_consts()

                if POWER_OVERRIDE and #POWER_OVERRIDE > 0 and R_table.has_value(tiers.def, POWER_OVERRIDE) then
                    SUBSTATION_TIER = POWER_OVERRIDE
                end

                metrics_outgoing.tier = SUBSTATION_TIER
            elseif msg == COMMS_SUBSTATION_VALUES then
                -- Update the display with the received values

                --- @type number, number
                local percentage, trend

                local temp_percentage, temp_trend, temp_eu_in, temp_eu_out = select(2, ...)

                percentage = temp_percentage or 0
                trend = temp_trend or 0
                eu_in_value = temp_eu_in or 0
                eu_out_value = temp_eu_out or 0

                TREND_SIGN = trend > 0 and 1 or (trend < 0 and -1 or 0)

                metrics_outgoing.tier = SUBSTATION_TIER

                local current_terminal = term.current()

                if not painted_template then
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.white)
                    R_terminal.reset_terminal()

                    painter_template_pocket:repaint(current_terminal)
                    painted_template = true
                end

                display(
                    current_terminal,
                    painter_state_pocket,
                    R_math.round(percentage * 100, PRECISION_PERCENTS),
                    R_math.round(trend * 100, PRECISION_PERCENTS),
                    (eu_out_value == 0 and 0 or eu_in_value / eu_out_value) * 100,
                    26 - 15
                )
            elseif msg == COMMS_SUBSTATION_DISCONNECT then
                __on_target_disconnected()
            end
        end
    )

    comms_api.register_disconnect_callback(
        function(id)
            if id == target_id then
                __on_target_disconnected()
            end
        end
    )

    comms_api.register_connect_callback(
        function(id)
            if id == target_id then
                comms_api.send(target_id, COMMS_CONFIG_REQUEST)
                painted_template = false
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

            metrics_outgoing = tiers.class.Metrics:new(function() return eu_out_value end)

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
else
    if (not POWER_OVERRIDE) or #POWER_OVERRIDE < 2 or (not R_table.has_value(tiers.def, POWER_OVERRIDE)) then
        SUBSTATION_TIER = "IV"
        __force_config_values()
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
                    POWER_OVERRIDE
                )
            elseif msg == COMMS_GENERATED_POWER then
                local temp_eu_in = select(2, ...)

                if temp_eu_in then eu_in_value = temp_eu_in end
            end
        end
    )

    local tick = 1

    exec.loop_forever(
        -- wait_interval
        1,
        -- init
        function()
            SUBSTATION = wait_for_substation()

            eu_out:clear()

            metrics_outgoing = tiers.class.Metrics:new(function() return eu_out:get() end, SUBSTATION_TIER)

            -- Initialize the monitors with the base template

            R_monitor.foreach_monitor(
                function(monitor)
                    monitor.setBackgroundColor(colors.black)
                    monitor.setTextColor(colors.white)
                    monitor.setTextScale(0.5)
                    monitor.clear()

                    painter_template_monitor:paint(monitor)
                end
            )

            term.clear()
            print("Substation detected.")
            print("This program doesn't render anything here yet.")
            print("View results via a monitor or connected pocket computer.")
        end,
        -- body
        function()
            eu_out:measure(SUBSTATION.getOutputPerSec() / 20)

            if tick == 1 then
                eu_out_value = eu_out:get()

                local percentage = SUBSTATION.getEnergyStored() / SUBSTATION.getEnergyCapacity()
                local trend = percentage - LAST_PERCENTAGE

                TREND_SIGN = trend > 0 and 1 or (trend < 0 and -1 or 0)

                local rounded_current = R_math.round(percentage * 100, PRECISION_PERCENTS)
                local rounded_trend = R_math.round(trend * 100, PRECISION_PERCENTS)
                local load_value = (eu_out_value == 0 and 0 or eu_in_value / eu_out_value) * 100

                R_monitor.foreach_monitor(
                    function(monitor)
                        display(
                            monitor,
                            painter_state_monitor,
                            rounded_current,
                            rounded_trend,
                            load_value,
                            0
                        )
                    end
                )

                -- comms API
                comms_api.broadcast(COMMS_SUBSTATION_VALUES, percentage, trend, eu_in_value, eu_out_value)

                LAST_PERCENTAGE = percentage
            end

            tick = tick == RENDER_TICK_DELAY and 1 or tick + 1
        end,
        -- sleep_watcher
        exec.class.EventWatcher:new()
            :add(comms_api.get_event_contexts())
        ,
        -- quit
        nil
    )
end