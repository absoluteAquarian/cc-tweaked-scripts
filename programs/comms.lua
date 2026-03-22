local comms_api = require "lib.api.comms"

local R_terminal = require "lib.cc.terminal"

local exec = require "lib.exec"
local R_table = require "lib.table"

local native = {
    math = {
        max = math.max,
        min = math.min,
        floor = math.floor
    },
    table = {
        insert = table.insert,
        remove = table.remove,
        concat = table.concat,
    }
}

local w, h = term.getSize()

--- @type string[]
local __messages = {}
--- @type { fg: number, bg: number }[]
local __msgcol = {}
local __colfg = colors.white
local __colbg = colors.black

local __msgview = 1
local __msgviwemax = h - 2

local function __get_message_positions()
    local view_start = __msgview
    local view_end = native.math.min(view_start + __msgviwemax - 1, #__messages)

    return view_start, view_end
end

--- @param msg string
local function record(msg)
    local _, view_end = __get_message_positions()
    local bottom = view_end == #__messages

    local first, last = 1, native.math.min(w, #msg)
    while first <= #msg do
        -- Restrict the message history
        if #__messages >= 200 then
            table.remove(__messages, 1)
            table.remove(__msgcol, 1)
            if __msgview > 1 then __msgview = __msgview - 1 end
        end

        table.insert(__messages, msg:sub(first, last))
        table.insert(__msgcol, { fg = __colfg, bg = __colbg })
        first, last = last + 1, native.math.min(last + w, #msg)
    end

    -- Move the messages up if the view is at the bottom, to keep it at the bottom as new messages come in
    if bottom then __msgview = native.math.max(1, #__messages - __msgviwemax + 1) end
end

--- @param fmt string
--- @param ... any
local function recordfmt(fmt, ...)
    record(string.format(fmt, ...))
end

--- @param fg number
--- @param bg number
local function set_record_colors(fg, bg)
    __colfg = fg
    __colbg = bg
end

--- @param msg string
local function recorderr(msg)
    set_record_colors(colors.red, colors.black)
    record(msg)
    set_record_colors(colors.white, colors.black)
end

--- @param fmt string
--- @param ... any
local function recorderrfmt(fmt, ...)
    recorderr(string.format(fmt, ...))
end

--- @type string[]
local __input = {}
local __inputview = 1
local INPUTPREFIX = "> "
local __inputcursor = #INPUTPREFIX + 1

--- @return integer view_start
--- @return integer view_end
--- @return integer cursor_in_view
local function __get_input_positions()
    local view_start = __inputview
    local view_end = native.math.min(view_start + w - #INPUTPREFIX - 1, #__input + 1)
    local cursor_in_view = view_start + __inputcursor - #INPUTPREFIX - 1

    return view_start, view_end, cursor_in_view
end

local function refresh_message_display()
    term.setCursorBlink(false)

    -- Erase the lines
    for i = 1, __msgviwemax do
        term.setCursorPos(1, i)
        term.clearLine()
    end

    -- Show the messages
    local y = 1
    local fg, bg = colors.white, colors.black

    local view_start, view_end = __get_message_positions()

    for i = view_start, view_end do
        local cols = __msgcol[i]

        term.setCursorPos(1, y)

        if fg ~= colors.white then term.setTextColor(colors.white) end
        if bg ~= colors.black then term.setBackgroundColor(colors.black) end

        fg, bg = cols.fg, cols.bg

        term.clearLine()

        if fg ~= colors.white then term.setTextColor(fg) end
        if bg ~= colors.black then term.setBackgroundColor(bg) end

        write(__messages[i])
        y = y + 1
    end

    while y <= h do
        term.setCursorPos(1, y)
        term.clearLine()
        y = y + 1
    end

    term.setCursorPos(__inputcursor, h)
    term.setCursorBlink(true)
end

local function refresh_input_display()
    term.setCursorBlink(false)

    -- Erase the line
    term.setCursorPos(1, h)
    term.clearLine()

    -- Show the input
    term.setCursorPos(1, h)
    write(INPUTPREFIX)

    local view_start, view_end, _ = __get_input_positions()

    for i = view_start, view_end do
        if i <= #__input then
            write(__input[i])
        else
            write(" ")  -- Allow cursor to be "after" the input text, even when it would normally span the entire display
        end
    end

    term.setCursorPos(__inputcursor, h)
    term.setCursorBlink(true)
end

--- @type integer
local __id = os.getComputerID()

--- @type integer[]
local __targets = {}

--- @type table<integer, boolean>
local __alive = {}
--- @type integer
local __watchdog_timer

--- @type PeripheralModem
local modem

--- @return PeripheralModem
local function find_wireless_modem()
    local modem_temp
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if p and p.isWireless and p.isWireless() then
            modem_temp = p
            break
        end
    end
    return modem_temp
end

--- @return PeripheralModem
local function look_for_modem()
    --- @type PeripheralModem
    local modem_temp = nil

    while true do
        -- Search for a wireless modem
        modem_temp = find_wireless_modem()

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

local CHANNEL_GENERIC_TX = comms_api.consts.channels.GENERIC_TX
local CHANNEL_WATCHDOG_TX = CHANNEL_GENERIC_TX + 1
local CHANNEL_GENERIC_RX = comms_api.consts.channels.GENERIC_RX
local CHANNEL_WATCHDOG_RX = CHANNEL_GENERIC_RX + 1

local function __pinged_by(sender)
    R_table.remove_values(__targets, sender)
    table.insert(__targets, sender)
    __alive[sender] = true

    recordfmt("[]: Received ping from computer %d", sender)
    refresh_message_display()

    os.queueEvent(comms_api.consts.EVENT_CONNECT, sender)
end

local COMMAND_PING = 1
local COMMAND_PING_REPLY = 2
local WATCHDOG_CHECK = 3
local WATCHDOG_RESPONSE = 4
local COMMAND_API_BROADCAST = 5
local COMMAND_API_SPECIFIC = 6

--- @param command integer
--- @param tx integer
--- @param rx integer
--- @param ... any
local function send_on_channels(command, tx, rx, ...)
    modem.transmit(
        tx,
        rx,
        { command = command, sender = __id, data = table.pack(...) }
    )
end

--- @type table<integer, fun(sender: integer, command: integer, ...: any)>
local receive_funcs =
{
    [COMMAND_PING] = function(sender, command, ...)
        __pinged_by(sender)
        send_on_channels(COMMAND_PING_REPLY, CHANNEL_GENERIC_TX, CHANNEL_GENERIC_RX, sender)
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
            send_on_channels(WATCHDOG_RESPONSE, CHANNEL_WATCHDOG_TX, CHANNEL_WATCHDOG_RX, sender)
        end
    end,
    [WATCHDOG_RESPONSE] = function(sender, command, ...)
        local target_id = select(1, ...)

        if target_id == __id then
            __alive[sender] = true
        end
    end,
    [COMMAND_API_BROADCAST] = function(sender, command, ...)
        -- Forward to the API event to other programs
        os.queueEvent(comms_api.consts.EVENT_DATA_RX, sender, ...)
    end,
    [COMMAND_API_SPECIFIC] = function(sender, command, ...)
        local target_id = select(1, ...)

        if target_id == __id then
            -- Forward to the API event to other programs
            os.queueEvent(comms_api.consts.EVENT_DATA_RX, sender, select(2, ...))
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
        recordfmt("[]: Received unknown command (%d) from computer %d", command, sender)
        refresh_message_display()
    end
end

--- @param new_cursor integer
--- @return boolean
local function __set_cursor(new_cursor)
    local old = __inputcursor

    local max_cursor = native.math.min(w, #__input + #INPUTPREFIX + 1)
    __inputcursor = native.math.max(1 + #INPUTPREFIX, native.math.min(new_cursor, max_cursor))

    return old ~= __inputcursor
end

local MAX_INPUT_LENGTH = w - #INPUTPREFIX

--- @param new_view integer
--- @return boolean
local function __set_view(new_view)
    local old = __inputview

    local view_max = native.math.max(1, #__input - MAX_INPUT_LENGTH + 1)
    __inputview = native.math.max(1, native.math.min(new_view, view_max))

    return old ~= __inputview
end

local KEYHOLDMAX = 15
local __keyhold = 1
local __keyholdmax = KEYHOLDMAX

--- @param held boolean
--- @param func function
local function __key_holdfunc(held, func, recurse)
    if not held then
        if not recurse then
            -- Reset key hold state
            __keyhold = KEYHOLDMAX
            __keyholdmax = KEYHOLDMAX
        end

        func()
    else
        -- Held keys should trigger the function after a short delay, and then repeatedly after that delay until released
        __keyhold = __keyhold - 1

        if __keyhold <= 0 then
            __key_holdfunc(false, func, true)

            __keyhold = __keyholdmax

            if __keyholdmax > 1 then __keyholdmax = native.math.max(1, native.math.floor(__keyholdmax / 2)) end
        end
    end
end

--- @param direction 1|-1
--- @param held boolean
local function __key_cursormove(direction, held)
    __key_holdfunc(
        held,
        function()
            if not __set_cursor(__inputcursor + direction) then
                -- Cursor is at a hard limit, so move the view if possible
                __set_view(__inputview + direction)
            end
        end
    )
end

--- @param pos integer
local function __key_cursorset(pos)
    if __set_cursor(pos) then
        refresh_input_display()
    end
end

local function __key_viewset(pos)
    if __set_view(pos) then
        refresh_input_display()
    end
end

local function __input_reset()
    __input = {}
    __inputview = 1
    __inputcursor = 1
end

local function __input_set(str)
    __input = {}

    for i = 1, #str do
        table.insert(__input, str:sub(i, i))
    end

    __set_cursor(w)
    __set_view(#__input + 1)
end

--- @type table<string, string>
local cmd_descriptions =
{
    ["whoami"] = "Display the ID of this computer",
    ["help"] = "Show details about a command",
    ["ping"] = "Send a ping to all other computers running this program",
    ["list"] = "List all known commands",
    ["clear"] = "Clear the message history"
}

--- @type table<string, function>
local commands =
{
    ["whoami"] = function()
        recordfmt("I am computer %d", __id)
        refresh_message_display()
    end,
    ["help"] = function(...)
        local num = select("#", ...)
        if num == 0 then
            recorderr("Expected command as argument")
        elseif num > 1 then
            recorderr("Too many arguments")
        else
            local cmd = select(1, ...)
            local desc = cmd_descriptions[cmd]
            if desc then
                recordfmt("%s", cmd)
                recordfmt("  %s", desc)
            else
                recorderrfmt("Unknown command: %s", cmd)
            end
        end
        refresh_message_display()
    end,
    ["ping"] = function()
        record("Sending ping...")
        send_on_channels(COMMAND_PING, CHANNEL_GENERIC_TX, CHANNEL_GENERIC_RX)
        refresh_message_display()
    end,
    ["list"] = function()
        record("Available commands:")
        for cmd, _ in pairs(commands) do
            recordfmt(" - %s", cmd)
        end
        refresh_message_display()
    end,
    ["clear"] = function()
        __messages = {}
        __msgcol = {}
        __msgview = 1

        recordfmt("%s%s", INPUTPREFIX, "clear")
        refresh_message_display()
    end
}

--- @type string[]
local __submit_history = {}
local __history_index = 1

local function __key_submit()
    local str = native.table.concat(__input)

    if #str > 0 then
        -- Print the submitted command
        recordfmt("%s%s", INPUTPREFIX, str)

        -- Check for commands
        --- @type string, string
        local cmd, rest = str:match("^(%S+)%s*(.*)$")
        local command_func = commands[cmd]
        if command_func then
            local args = {}

            while #rest > 0 do
                local quote = rest:find('"')
                if quote then
                    -- Get the next quoted argument
                    local arg = rest:match('^%s*"([^"]*)"')
                    if arg then
                        table.insert(args, arg)
                        rest = rest:sub(quote + #arg + 2)
                    else
                        recorderr("Mismatched quote in command arguments")
                        goto skip_to_display
                    end
                else
                    -- Get the next whitespace-delimited argument
                    local arg = rest:match("^%s*(%S+)")
                    if arg then
                        table.insert(args, arg)
                        rest = rest:sub(rest:find(arg) + #arg)
                    else
                        -- No more arguments
                        break
                    end
                end
            end

            -- Attempt to deserialize the arguments
            for i, arg in ipairs(args) do
                local success, deserialized = pcall(textutils.unserialize, arg)
                if success then args[i] = deserialized end
            end

            local success, err = pcall(command_func, table.unpack(args))
            if not success then
                recorderrfmt("Error executing command: %s", err)
            end
        else
            recorderrfmt("Unknown command: %s", cmd)
        end

        ::skip_to_display::

        refresh_message_display()

        -- Restrict the length of the submit history
        if #__submit_history >= 30 then
            table.remove(__submit_history, 1)
        end

        -- Save the command for possible reuse
        table.insert(__submit_history, str)
        __history_index = #__submit_history + 1

        -- Clear the input
        __input_reset()
        refresh_input_display()
    end
end

local function __key_gethistory(direction)
    local history = __history_index + direction
    if history == #__submit_history + 1 then
        __history_index = history
        __input_reset()
        refresh_input_display()
    elseif history >= 1 and history <= #__submit_history then
        __history_index = history
        __input_set(__submit_history[history])
        refresh_input_display()
    end
end

local function __key_remove(pos)
    if pos >= 1 and pos <= #__input then
        table.remove(__input, pos)
        if __inputcursor > pos then __set_cursor(__inputcursor - 1) end
        refresh_input_display()
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

        R_terminal.reset_terminal()

        record("[]: Waiting for modem...")
        record("[]: Modem found.")
        record("[]: Sending ping...")

        refresh_message_display()
        refresh_input_display()

        send_on_channels(COMMAND_PING, CHANNEL_GENERIC_TX, CHANNEL_GENERIC_RX)

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
                            send_on_channels(WATCHDOG_CHECK, CHANNEL_WATCHDOG_TX, CHANNEL_WATCHDOG_RX, target)
                            __alive[target] = false  -- Target must respond before next check to be considered alive
                        else
                            recordfmt("[]: Connection to computer %d was lost", target)
                            os.queueEvent(comms_api.consts.EVENT_DISCONNECT, target)
                            table.remove(targets, i)
                            __alive[target] = nil
                        end
                    end
                end
            end
        )
        -- Input-related events
        :listen(
            "key",
            function(key, held)
                if key == keys.left or key == keys.right then
                    local direction = key == keys.left and -1 or 1
                    __key_cursormove(direction, held)
                    refresh_input_display()
                elseif key == keys.up or key == keys.down then
                    if not held then
                        local direction = key == keys.up and -1 or 1
                        __key_gethistory(direction)
                    end
                elseif key == keys.enter then
                    if not held then
                        __key_submit()
                    end
                elseif key == keys.home then
                    if not held then
                        __key_cursorset(1)
                        __key_viewset(1)
                    end
                elseif key == keys["end"] then
                    if not held then
                        __key_cursorset(#__input + 1)
                        __key_viewset(#__input + 1)
                    end
                elseif key == keys.delete then
                    __key_holdfunc(
                        held,
                        function()
                            __key_remove(__inputcursor - #INPUTPREFIX)
                        end
                    )
                elseif key == keys.backspace then
                    __key_holdfunc(
                        held,
                        function()
                            __key_remove(__inputcursor - #INPUTPREFIX - 1)
                        end
                    )
                end
            end
        )
        :listen(
            "char",
            function(char)
                local _, _, cursor_in_view = __get_input_positions()
                native.table.insert(__input, cursor_in_view, char)
                if not __set_cursor(__inputcursor + 1) or __inputcursor == w then
                    __set_view(__inputview + 1)
                end
                refresh_input_display()
            end
        )
        -- API-related events
        :listen(
            comms_api.consts.EVENT_DATA_TX,
            function(target, ...)
                -- Broadcast the data
                if target < 0 then
                    send_on_channels(COMMAND_API_BROADCAST, CHANNEL_GENERIC_TX, CHANNEL_GENERIC_RX, ...)
                else
                    send_on_channels(COMMAND_API_SPECIFIC, CHANNEL_GENERIC_TX, CHANNEL_GENERIC_RX, target, ...)
                end
            end
        )
    ,
    --quit
    nil
)