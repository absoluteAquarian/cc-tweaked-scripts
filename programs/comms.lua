local R_terminal = require "lib.cc.terminal"

local exec = require "lib.exec"
local R_table = require "lib.table"

--- @type integer
local __id = os.getComputerID()

--- @type integer[]
local __targets = {}

--- @type table<integer, boolean>
local __alive = {}
--- @type integer
local __watchdog_timer

--- @class PeripheralModem
--- @field open fun(channel: number)
--- @field isOpen fun(channel: number) : boolean
--- @field close fun(channel: number)
--- @field closeAll fun()
--- @field transmit fun(channel: number, replyChannel: number, payload: any)
--- @field isWireless fun() : boolean
local modem

--- @return PeripheralModem
local function look_for_modem()
    --- @type PeripheralModem
    local modem_temp = nil

    while true do
        -- Search for a wireless modem
        for _, name in ipairs(peripheral.getNames()) do
            local p = peripheral.wrap(name)
            if p and p.isWireless and p.isWireless() then
                modem_temp = p
                break
            end
        end

        if modem_temp then break end

        R_terminal.reset_terminal()

        write("[]: Waiting for modem.")
        sleep(1)
        write(".")
        sleep(1)
        write(".")
        sleep(1)
    end

    return modem_temp
end

--- @class CommandPayload
--- @field command integer
--- @field sender integer
--- @field data table

local CHANNEL_GENERIC_TX = 413
local CHANNEL_WATCHDOG_TX = 414
local CHANNEL_GENERIC_RX = 612
local CHANNEL_WATCHDOG_RX = 613

local function send_with_channels(command, tx, rx, ...)
    modem.transmit(
        tx,
        rx,
        { command = command, sender = __id, data = table.pack(...) }
    )
end

--- @param command integer
--- @param ... any
local function send(command, ...) send_with_channels(command, CHANNEL_GENERIC_TX, CHANNEL_GENERIC_RX, ...) end

local function __pinged_by(sender)
    R_table.remove_values(__targets, sender)
    table.insert(__targets, sender)
    __alive[sender] = true

    print(string.format("[]: Received ping from computer %d", sender))
end

local COMMAND_PING = 1
local COMMAND_PING_REPLY = 2
local WATCHDOG_CHECK = 3
local WATCHDOG_RESPONSE = 4

--- @type table<integer, fun(sender: integer, command: integer, ...: any)>
local receive_funcs =
{
    [COMMAND_PING] = function(sender, command, ...)
        __pinged_by(sender)
        send(COMMAND_PING_REPLY, sender)
    end,
    [COMMAND_PING_REPLY] = function(sender, command, ...)
        local target_id = select(1, ...)

        if target_id == __id then
            __pinged_by(sender)
        end
    end,
    [WATCHDOG_CHECK] = function(sender, command, ...)
        local target_id = select(1, ...)

        if target_id == __id then
            send_with_channels(WATCHDOG_RESPONSE, CHANNEL_WATCHDOG_TX, CHANNEL_WATCHDOG_RX, sender)
        end
    end,
    [WATCHDOG_RESPONSE] = function(sender, command, ...)
        local target_id = select(1, ...)

        if target_id == __id then
            __alive[sender] = true
        end
    end
}

--- @param sender integer
--- @param command integer
--- @param ... any
local function receive(sender, command, ...)
    local func = receive_funcs[command]
    if func then
        func(sender, command, ...)
    else
        print(string.format("[]: Received unknown command (%d) from computer %d", command, sender))
    end
end

exec.loop_forever
(
    -- wait_interval
    1,
    -- init
    function()
        modem = look_for_modem()
        modem.open(CHANNEL_GENERIC_RX)
        modem.open(CHANNEL_GENERIC_TX)
        modem.open(CHANNEL_WATCHDOG_RX)
        modem.open(CHANNEL_WATCHDOG_TX)

        write('\n')
        print("[]: Modem found. Sending ping...")

        send(COMMAND_PING)

        __watchdog_timer = os.startTimer(5)
    end,
    -- body
    function()
    end,
    -- sleep_watcher
    exec.class.EventWatcher:new()
        :listen(
            "modem_message",
            function(side, channel, replyChannel, message, distance)
                if replyChannel ~= CHANNEL_GENERIC_RX
                and replyChannel ~= CHANNEL_WATCHDOG_RX
                then return end

                if type(message) ~= "table" then return end
                if message.command == nil or message.sender == nil or message.data == nil then return end

                --- @cast message CommandPayload

                if message.sender == __id then return end

                receive(message.sender, message.command, table.unpack(message.data))
            end
        )
        :listen(
            "timer",
            function(timer_id)
                if timer_id == __watchdog_timer then
                    __watchdog_timer = os.startTimer(5)

                    local targets = __targets
                    for i = #targets, 1, -1 do
                        local target = targets[i]
                        if __alive[target] then
                            send_with_channels(WATCHDOG_CHECK, CHANNEL_WATCHDOG_TX, CHANNEL_WATCHDOG_RX, target)
                            __alive[target] = false  -- Target must respond before next check to be considered alive
                        else
                            print(string.format("[]: Connection to computer %d was lost", target))
                            table.remove(targets, i)
                            __alive[target] = nil
                        end
                    end
                end
            end
        ),
    --quit
    nil
)