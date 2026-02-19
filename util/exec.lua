require "util.cc.monitor"
require "util.try-catch"

--- A utility function to loop forever, with optional logic to run when quitting or restarting the program.
--- @param wait_interval number  The number of ticks to wait between iterations.  Forced to be at least 1.
--- @param body fun()  The function to run every loop iteration
--- @param quit fun()?  An optional function to run when the program is quitting after an error
--- @param restart fun()?  An optional function to run when the program is restarting after an error
function loop_forever(wait_interval, body, quit, restart)
    wait_interval = (wait_interval and wait_interval >= 1) and wait_interval or 1

    local running = true
    while running do
        try {
            -- try
            function()
                body()
                sleep(wait_interval / 20.0)
            end,
            -- catch
            function(error)
                bsod_external_monitors()
                print()
                print("Detected error:")
                print(error)
                print()
                print("r -> restart")
                print("q -> quit")

                local valid = false

                while not valid do
                    local _, key = os.pullEvent("key")

                    if key == keys.q then
                        valid = true
                        running = false
                        if quit then quit() end
                    elseif key == keys.r then
                        valid = true
                        if restart then restart() end
                    end

                    if valid then
                        -- Flush the event queue so that the entered key is consumed
                        os.queueEvent("FAKE_EVENT")
                        os.pullEvent("FAKE_EVENT")
                    end
                end
            end
        }
    end
end

return {
    loop_forever = loop_forever
}