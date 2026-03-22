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
    EVENT_DATA_RX = "comms_data_rx",
    --- The name of the event that's fired when a computer connects to the network
    EVENT_CONNECT = "comms_connect",
    --- The name of the event that's fired when a computer disconnects from the network
    EVENT_DISCONNECT = "comms_disconnect",
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
local __event_callback_data = nil

--- Assigns a function to be called when a data packet is received
--- @param func fun(sender: integer, ...)  The function to call when a data packet is received
function module_table.register_data_callback(func)
    __event_callback_data = func
end

--- @type fun(id: integer)
local __event_callback_connect = nil

--- Assigns a function to be called when a computer connects to the network
--- @param func fun(id: integer)  The function to call when a computer connects to the network
function module_table.register_connect_callback(func)
    __event_callback_connect = func
end

--- @type fun(id: integer)
local __event_callback_disconnect = nil

--- Assigns a function to be called when a computer disconnects from the network
--- @param func fun(id: integer)  The function to call when a computer disconnects from the network
function module_table.register_disconnect_callback(func)
    __event_callback_disconnect = func
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
                if __event_callback_data then trace.scall(__event_callback_data, sender, ...) end
            end
        },
        {
            event = module_table.consts.EVENT_CONNECT,
            predicate = function(id)
                if __event_callback_connect then trace.scall(__event_callback_connect, id) end
            end
        },
        {
            event = module_table.consts.EVENT_DISCONNECT,
            predicate = function(id)
                if __event_callback_disconnect then trace.scall(__event_callback_disconnect, id) end
            end
        }
    }
end

return module_table