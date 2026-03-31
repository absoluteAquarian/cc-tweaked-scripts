local comms_api = require "lib.api.comms"

local R_terminal = require "lib.cc.terminal"

local machine = require "lib.gt.machine"

local exec = require "lib.exec"
local R_string = require "lib.string"

--- @class TurbineMachine : GTCEu_TurbineMachinePeripheral, GTCEu_WorkablePeripheral, GTCEu_CoverHolderPeripheral

--- @type table<string, TurbineMachine>
local turbines
--- @type integer
local count = 0

exec.loop_forever(
    -- wait_interval
    1,
    -- init
    function()
        -- Load the initial list of turbines
        turbines = {}
        count = 0

        for _, v in pairs(machine.find_machines("turbine", true)) do
            local p = v[1]
            local name = peripheral.getName(p)
            turbines[name] = p
            count = count + 1
        end
    end,
    -- body
    function()
        --- @type integer
        local total_eu = 0

        for name, turbine in pairs(turbines) do
            if not peripheral.isPresent(name) then
                turbines[name] = nil
                count = math.max(0, count - 1)
            else
                total_eu = total_eu + turbine.getCurrentProduction()
            end
        end

        R_terminal.reset_terminal()
        print(string.format("# of turbines: %d", count))
        print(string.format("Total EU/t: %d", total_eu))

        -- Broadcast the total EU/t to the network
        -- Paired program "power_monitor" uses this message string
        comms_api.broadcast("pm:generated", total_eu)
    end,
    -- sleep_watcher
    exec.class.EventWatcher:new()
        :add(comms_api.get_event_contexts())
        :listen(
            "peripheral",
            function(side)
                if R_string.starts_with(side, "gtceu:") and R_string.contains(side, "turbine") then
                    turbines[side] = peripheral.wrap(side)
                    count = count + 1
                end
            end
        )
        :listen(
            "peripheral_detach",
            function(side)
                turbines[side] = nil
                count = math.max(0, count - 1)
            end
        )
    ,
    -- quit
    nil
)