local R_monitor = require "util.cc.monitor"
local R_terminal = require "util.cc.terminal"
local handler = require "util.handler"

--- A utility function to loop forever, with optional logic to run when quitting or restarting the program.
--- @param wait_interval number  The number of ticks to wait between iterations.  Forced to be at least 1.
--- @param init fun()?  An optional function to run once before the loop starts or when the program is restarted after an error
--- @param body fun()  The function to run every loop iteration
--- @param quit fun()?  An optional function to run when the program is quitting after an error
local function loop_forever(wait_interval, init, body, quit, restart)
    wait_interval = (wait_interval and wait_interval >= 1) and wait_interval or 1

    local running = true
    local has_init = false

    while running do
        handler.try {
            -- try
            function()
                if not has_init and init then init() end
                body()
                sleep(wait_interval / 20.0)
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
    loop_forever = loop_forever
}