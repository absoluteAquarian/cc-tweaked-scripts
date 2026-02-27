local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"
local handler = require "lib.handler"

--- @class EventWatcher
--- @field event string  The event to watch for
--- @field predicate fun(...)  The function to execute when the event has been fired

--- Sleeps for the given number of seconds, but also pulls events while waiting for the sleep timer to expire.
--- @param seconds number  The number of seconds to sleep for
--- @param watchers EventWatcher[]  The array of event watchers
local function sleep_with_polling(seconds, watchers)
    local timer = os.startTimer(seconds)

    while true do
        local e = { os.pullEvent() }
        local event = e[1]

        if event == "timer" and e[2] == timer then break end

        -- Check the event watchers
        for _, watcher in ipairs(watchers) do
            if event == watcher.event then
                watcher.predicate(table.unpack(e, 2))
            end
        end
    end
end

--- A utility function to loop forever, with optional logic to run when quitting or restarting the program.
--- @param wait_interval (fun() : integer)|integer  The amount of ticks to wait between iterations.  Forced to be at least 1.
--- @param init fun()?  An optional function to run once before the loop starts or when the program is restarted after an error
--- @param body fun()  The function to run every loop iteration
--- @param sleep_watchers EventWatcher[]?  The array of event watchers to use while sleeping between loop iterations.  If nil, the standard sleep function will be used.
--- @param quit fun()?  An optional function to run when the program is quitting after an error
local function loop_forever(wait_interval, init, body, sleep_watchers, quit)
    if type(wait_interval) == "number" and wait_interval < 1 then wait_interval = 1 end

    local running = true
    local has_init = false

    while running do
        handler.try {
            -- try
            function()
                if not has_init and init then
                    init()
                    has_init = true
                end

                body()

                local ticks
                if type(wait_interval) == "function" then
                    ticks = wait_interval()
                    if ticks < 1 then ticks = 1 end
                else
                    ticks = wait_interval
                end

                if sleep_watchers and #sleep_watchers > 0 then
                    sleep_with_polling(ticks / 20, sleep_watchers)
                else
                    sleep(ticks / 20)
                end
            end,
            -- catch
            function(error)
                R_monitor.bsod_external_monitors()

                local valid = false
                while not valid do
                    R_terminal.reset_terminal()

                    print("Detected error:")
                    print(error)
                    print()
                    print("r -> restart")
                    print("q -> quit")

                    local _, key = os.pullEvent("key")

                    if key == keys.q then
                        valid = true
                        running = false
                    elseif key == keys.r then
                        valid = true
                        has_init = false
                    end

                    if valid then
                        -- Flush the event queue so that the entered key is consumed
                        os.queueEvent("FAKE_EVENT")
                        os.pullEvent("FAKE_EVENT")
                        R_terminal.reset_terminal()
                    end
                end
            end
        }
    end

    if quit then quit() end
end

return {
    sleep_with_polling = sleep_with_polling,
    loop_forever = loop_forever
}