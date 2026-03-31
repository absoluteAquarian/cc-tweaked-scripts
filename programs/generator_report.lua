local comms_api = require "lib.api.comms"

local R_terminal = require "lib.cc.terminal"

local machine = require "lib.gt.machine"

local exec = require "lib.exec"
local R_string = require "lib.string"

--- @type table<string, GTCEu_EnergyInfoPeripheral>
local generators
--- @type table<string, integer>
local maxgen
--- @type integer
local count = 0

exec.loop_forever(
    -- wait_interval
    1,
    -- init
    function()
        -- Load the initial list of generators
        generators = {}
        count = 0

        for _, p in pairs(peripheral.getNames()) do
            if R_string.starts_with(p, "gtceu:") then
                local wrapped = peripheral.wrap(p)--[[@as GTCEu_EnergyInfoPeripheral]]
                if wrapped.getOutputPerSec and pcall(wrapped.getOutputPerSec) then
                    -- It can output energy, so treat it as a generator
                    generators[p] = wrapped
                    count = count + 1
                end
            end
        end
    end,
    -- body
    function()
        --- @type integer
        local total_eu = 0

        for name, generator in pairs(generators) do
            if not peripheral.isPresent(name) then
                generators[name] = nil
                maxgen[name] = nil
                count = math.max(0, count - 1)
            else
                -- Unlike turbines, "generators" aren't always active
                -- Track the highest output seen for each generator, and treat it as the load capacity
                local max = maxgen[name]
                local generated = generator.getOutputPerSec()
                if not max or max < generated then
                    maxgen[name] = generated
                    max = generated
                end

                total_eu = total_eu + math.ceil(generated / 20)
            end
        end

        R_terminal.reset_terminal()
        print(string.format("# of generators: %d", count))
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
                if R_string.starts_with(side, "gtceu:") then
                    local wrapped = peripheral.wrap(side)--[[@as GTCEu_EnergyInfoPeripheral]]
                    if wrapped.getOutputPerSec and pcall(wrapped.getOutputPerSec) then
                        -- It can output energy, so treat it as a generator
                        generators[side] = wrapped
                        count = count + 1
                    end
                end
            end
        )
        :listen(
            "peripheral_detach",
            function(side)
                generators[side] = nil
                maxgen[side] = nil
                count = math.max(0, count - 1)
            end
        )
    ,
    -- quit
    nil
)