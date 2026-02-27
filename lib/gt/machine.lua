local tiers = require "lib.gt.tiers"

local R_string = require "lib.string"

-- Information for the following was found at:  https://github.com/GregTechCEu/GregTech-Modern/blob/1.20.1/src/main/java/com/gregtechceu/gtceu/integration/cctweaked/peripherals

--- @class __GTCEu_Peripheral

--- @class GTCEu_ControllablePeripheral : __GTCEu_Peripheral
--- @field isWorkingEnabled fun() : boolean
--- @field setWorkingEnabled fun(enabled: boolean)
--- @field setSuspendAfterFinish fun(suspendAfterFinish: boolean)

--- @class GTCEu_CoverHolderPeripheral : __GTCEu_Peripheral
--- @field setBufferedText fun(face: string, line: integer, text: string) : boolean, string
--- @field parsePlaceholders fun(face: string, text: string) : boolean, string

--- @class GTCEu_EnergyInfoPeripheral : __GTCEu_Peripheral
--- @field getEnergyStored fun() : integer
--- @field getEnergyCapacity fun() : integer
--- @field getInputPerSec fun() : integer
--- @field getOutputPerSec fun() : integer

--- @class GTCEu_TurbineMachinePeripheral : __GTCEu_Peripheral
--- @field hasRotor fun() : boolean
--- @field getRotorSpeped fun() : integer
--- @field getMaxRotorHolderSpeed fun() : integer
--- @field getTotalEfficiency fun() : integer
--- @field getCurrentProduction fun() : integer
--- @field getOverclockVoltage fun() : integer
--- @field getRotorDurabilityPercent fun() : integer

--- @class GTCEu_WorkablePeripheral : __GTCEu_Peripheral
--- @field getProgress fun() : integer
--- @field getMaxProgress fun() : integer
--- @field isActive fun() : boolean

--- Finds a GTCE machine matching the given name and returns it along with its tier, or nil for both if no matching machine is found
--- @param machine string  The name of the machine to find.  Can be a whole name or substring (e.g. "assembler" will match "gtceu:ulv_assembler" and "gtceu:mv_assembler")
--- @param allow_null_tier boolean?  If true, machines that don't have a tier will be returned with a tier of nil instead of being ignored.
--- @return table?
--- @return string?
local function find_machine(machine, allow_null_tier)
    for _, p in pairs(peripheral.getNames()) do
        if (R_string.starts_with(p, "gtceu:") and R_string.contains(p, machine)) then
            local tier = tiers.peripheral_tier(p)
            if (allow_null_tier == true) or tier then return peripheral.wrap(p), tier end
        end
    end
    return nil, nil
end

--- Finds all GTCE machines matching the given name and returns them along with their tiers
--- @param machine string  The name of the machines to find.  Can be a whole name or substring (e.g. "assembler" will match "gtceu:ulv_assembler" and "gtceu:mv_assembler")
--- @param allow_null_tier boolean?  If true, machines that don't have a tier will be returned with a tier of nil instead of being ignored.
--- @return { [1]: table, [2]: string }[]
local function find_machines(machine, allow_null_tier)
    local machines = {}
    for _, p in pairs(peripheral.getNames()) do
        if (R_string.starts_with(p, "gtceu:") and R_string.contains(p, machine)) then
            local tier = tiers.peripheral_tier(p)
            if (allow_null_tier == true) or tier then table.insert(machines, { peripheral.wrap(p), tier }) end
        end
    end
    return machines
end

return {
    find_machine = find_machine,
    find_machines = find_machines
}