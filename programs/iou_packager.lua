local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"

local config = require "lib.config"
local exec = require "lib.exec"
local R_string = require "lib.string"

local cfg_file = config.class.ConfigFile:new("iou_packager")

local DISK_STORAGE = cfg_file:getString("DISK_STORAGE_TARGET") or "steel_crate"
local CRAFT_ITEMS = cfg_file:getString("SIDE_INPUTS") or "front"  -- NOTE: side is relative to the ME Bridge, not the computer
local AP_MEBRIDGE = cfg_file:getString("SIDE_BRIDGE") or "bottom"
local MODEM_OUTPUT = cfg_file:getString("SIDE_MODEM_TO_OUTPUTS") or "right"

local function __force_config_values()
    cfg_file:setString("DISK_STORAGE_TARGET", DISK_STORAGE)
    cfg_file:setString("SIDE_INPUTS", CRAFT_ITEMS)
    cfg_file:setString("SIDE_BRIDGE", AP_MEBRIDGE)
    cfg_file:setString("SIDE_MODEM_TO_OUTPUTS", MODEM_OUTPUT)
    cfg_file:save()
end

__force_config_values()

--- @class BasicItemDetail
--- @field name string
--- @field count number
--- @field nbt string?

--- @class FullItemDetail : BasicItemDetail
--- @field displayName string
--- @field lore string[]
--- @field maxCount number
--- @field tags { [string]: boolean }
--- @field damage number

--- @class PeripheralInventory
--- @field size fun() : number
--- @field list fun() : { [integer]: BasicItemDetail? }
--- @field getItemDetail fun(slot: number) : FullItemDetail?
--- @field getItemLimit fun(slot: number) : number
--- @field pushItems fun(toName: string, fromSlot: number, limit: number?, toSlot: number?) : number
--- @field pullItems fun(fromName: string, fromSlot: number, limit: number?, toSlot: number?) : number

--- @type PeripheralInventory
local disk_storage
local bridge
--- @type PeripheralInventory
local filling_chest
--- @type PeripheralInventory
local ouput_drive

--- @type integer
local progress_stage = -1
--- @type integer
local last_progress = -1

local function __report_progress()
    if last_progress == progress_stage then return end

    last_progress = progress_stage

    if progress_stage == 0 then
        print("Waiting for a cell to be moved to the subnet ME Chest...")
    elseif progress_stage == 1 then
        print("Filling the cell with the crafting items...")
    elseif progress_stage == 2 then
        print("Moving the filled cell to the output drive...")
    elseif progress_stage == 3 then
        print("Done!")
        print("")

        progress_stage = 0
    end
end

exec.loop_forever(
    -- wait_interval
    1,
    -- init
    function()
        R_terminal.reset_terminal()
        print("Scanning for peripherals...")

        if (not bridge) or (not peripheral.isPresent(AP_MEBRIDGE)) then
            if peripheral.getType(AP_MEBRIDGE) == "meBridge" then
                bridge = peripheral.wrap(AP_MEBRIDGE)
            else
                print(string.format("Error: no Advanced Peripherals ME Bridge peripheral was found on the '%s' side", AP_MEBRIDGE))
            end
        end

        if peripheral.isPresent(MODEM_OUTPUT) then
            local modem = peripheral.wrap(MODEM_OUTPUT)
            local possible_chest, possible_drive, possible_storage
            local too_many_chests, too_many_drives, too_many_disk_storage = false, false, false

            for _, name in ipairs(modem.getNamesRemote()) do
                if R_string.starts_with(name, "ae2:chest") then
                    if possible_chest then
                        if not too_many_chests then
                            too_many_chests = true
                            print(string.format("Error: more than one ME Chest peripheral was found on the '%s' modem network", MODEM_OUTPUT))
                        end
                    else
                        possible_chest = name
                    end
                elseif R_string.contains(name, "drive") then
                    if possible_drive then
                        if not too_many_drives then
                            too_many_drives = true
                            print(string.format("Error: more than one ME Drive peripheral was found on the '%s' modem network", MODEM_OUTPUT))
                        end
                    else
                        possible_drive = name
                    end
                elseif R_string.contains(name, DISK_STORAGE) then
                    if possible_storage then
                        if not too_many_disk_storage then
                            too_many_disk_storage = true
                            print(string.format("Error: more than one '%s' peripheral was found on the '%s' modem network", DISK_STORAGE, MODEM_OUTPUT))
                        end
                    else
                        possible_storage = name
                    end
                end
            end

            if possible_chest then
                filling_chest = peripheral.wrap(possible_chest)
            else
                print(string.format("Error: no ME Chest peripheral was found on the '%s' modem network", MODEM_OUTPUT))
            end

            if possible_drive then
                ouput_drive = peripheral.wrap(possible_drive)
            else
                print(string.format("Error: no ME Drive peripheral was found on the '%s' modem network", MODEM_OUTPUT))
            end

            if possible_storage then
                disk_storage = peripheral.wrap(possible_storage)
            else
                print(string.format("Error: no '%s' peripheral was found on the '%s' modem network", DISK_STORAGE, MODEM_OUTPUT))
            end
        end

        if disk_storage and bridge and filling_chest and ouput_drive then
            print("All peripherals found! Starting IOU Packager...")
            print("")
            progress_stage = 0

            R_monitor.foreach_monitor(
                function(monitor)
                    monitor.setTextScale(0.5)
                    monitor.setTextColor(colors.white)
                    monitor.setBackgroundColor(colors.black)
                    monitor.clear()
                    monitor.setCursorPos(1, 1)
                end
            )
        end
    end,
    -- body
    function()
        if (not disk_storage) or (not bridge) or (not filling_chest) or (not ouput_drive) then
            progress_stage = -1
            return false
        end

        if progress_stage == 0 then
            -- Try to move a new cell into the ME Chest

            if filling_chest.list()[2] == nil then
                local slot = 0
                for s, item in pairs(disk_storage.list()) do
                    if item then
                        -- Assume it's a portable storage cell
                        slot = s
                        break
                    end
                end

                if slot > 0 then
                    -- Move the cell to the chest
                    local moved = disk_storage.pushItems(peripheral.getName(filling_chest), slot, 1, 2)

                    if moved > 0 then
                        progress_stage = progress_stage + 1
                    end
                end
            else
                -- A cell was already in the ME Chest
                progress_stage = progress_stage + 1
            end
        elseif progress_stage == 1 then
            -- Fill the cell with the crafting items

            --- @type number
            local moved
            --- @type number
            local total_moved = 0

            repeat
                -- NOTE: not specifying a name, nbt nor tag will make the "search item" filter match any item

                moved = bridge.importItem({ count = 65535 }, CRAFT_ITEMS)

                if moved then total_moved = total_moved + moved end
            until (not moved) or (moved < 1)

            if total_moved and total_moved > 0 then
                progress_stage = progress_stage + 1
            end
        elseif progress_stage == 2 then
            -- Move the filled cell to the output drive

            local moved = filling_chest.pushItems(peripheral.getName(ouput_drive), 2, 1)

            if moved > 0 then
                progress_stage = progress_stage + 1
            end
        end

        __report_progress()
    end,
    -- sleep_watcher
    nil,
    -- quit
    nil
)