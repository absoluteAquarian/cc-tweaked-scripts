local tiers = require "lib.gt.tiers"
local R_string = require "lib.string"

--- Finds a GTCE machine matching the given name and returns it along with its tier, or nil for both if no matching machine is found
--- @param machine string  The name of the machine to find.  Can be a whole name or substring (e.g. "assembler" will match "gtceu:ulv_assembler" and "gtceu:mv_assembler")
--- @return table?
--- @return string?
local function find_machine(machine)
    for _, p in pairs(peripheral.getNames()) do
        if (R_string.starts_with(p, "gtceu:") and R_string.contains(p, machine)) then
            local tier = tiers.peripheral_tier(p)
            if tier then return peripheral.wrap(p), tier end
        end
    end
    return nil, nil
end

--- Finds all GTCE machines matching the given name and returns them along with their tiers
--- @param machine string  The name of the machines to find.  Can be a whole name or substring (e.g. "assembler" will match "gtceu:ulv_assembler" and "gtceu:mv_assembler")
--- @return table[]
local function find_machines(machine)
    local machines = {}
    for _, p in pairs(peripheral.getNames()) do
        if (R_string.starts_with(p, "gtceu:") and R_string.contains(p, machine)) then
            local tier = tiers.peripheral_tier(p)
            if tier then
                table.insert(machines, {peripheral.wrap(p), tier})
            end
        end
    end
    return machines
end

return {
    find_machine = find_machine,
    find_machines = find_machines
}