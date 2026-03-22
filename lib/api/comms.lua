local exec = require "lib.exec"
local trace = require "lib.trace"

--- @class PeripheralModem
--- @field open fun(channel: number)
--- @field isOpen fun(channel: number) : boolean
--- @field close fun(channel: number)
--- @field closeAll fun()
--- @field transmit fun(channel: number, replyChannel: number, payload: any)
--- @field isWireless fun() : boolean

--- @class CommandPayload
--- @field command integer
--- @field sender integer
--- @field data table

local module_table = {}

module_table.consts = {
    channels = {
        --- The modem channel used when transmitting commands
        GENERIC_TX = 413,
        --- The modem channel listened on when receiving commands
        GENERIC_RX = 612,
    },
    --- The name of the event that's fired when sending data packets
    EVENT_DATA_TX = "comms_data_tx",
    --- The name of the event that's fired when receiving data packets
    EVENT_DATA_RX = "comms_data_rx"
}

--- Sends a data packet to all connected computers
--- @param ... any  The data to include in the data packet
function module_table.broadcast(...)
    os.queueEvent(module_table.consts.EVENT_DATA_TX, -1, ...)
end

--- Sends a data packet to a specific computer
--- @param target_computer integer  The ID of the computer to send the data packet to
--- @param ... any  The data to include in the data packet
function module_table.send(target_computer, ...)
    os.queueEvent(module_table.consts.EVENT_DATA_TX, target_computer, ...)
end

--- @type fun(sender: integer, ...)
local __event_callback = nil

--- @param func fun(sender: integer, ...)  The function to call when a data packet is received
function module_table.register_data_callback(func)
    __event_callback = func
end

--- Returns an array of <code>EventContext</code> for use with <code>lib.exec.EventWatcher:add()</code>
--- @return EventContext[]
function module_table.get_event_contexts()
    --- @type EventContext[]
    return
    {
        {
            event = module_table.consts.EVENT_DATA_RX,
            predicate = function(sender, ...)
                if __event_callback then trace.scall(__event_callback, sender, ...) end
            end
        }
    }
end

return module_table