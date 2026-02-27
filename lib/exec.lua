local R_monitor = require "lib.cc.monitor"
local R_terminal = require "lib.cc.terminal"

local class = require "lib.class"
local handler = require "lib.handler"
local trace = require "lib.trace"

--- @class EventWatcherDefinition : ClassDefinition
local EventWatcher = class.class("EventWatcher")

--- @class EventContext  A table representing an entry in an EventWatcher
--- @field event string  The name of the event being watched
--- @field predicate fun(...)  The function to invoke when the event is pulled, with the event parameters passed as arguments

--- @class PulledEvent  An event pulled via os.pullEvent() or os.pullEventRaw()
--- @field [1] string  The name of the pulled event
--- @field [integer] any  For indices > 1, the parameters of the pulled event

--- [override] Creates a new EventWatcher instance
--- @return EventWatcher
function EventWatcher:new()
    --- @class EventWatcher : ClassInstance
    local instance = self:create_instance()

    --- @private
    --- @type table<string, (fun(...))[]>  The map of event names to predicates to invoke when that event is pulled
    instance.map = {}

    --- @private
    --- @type integer  How many events have been registered to this EventWatcher
    instance._count = 0

    --- @private
    --- Registers a new predicate for the given event name
    --- @param name string
    --- @param predicate fun(...)
    function instance:register(name, predicate)
        local list = self.map[name]
        if not list then
            list = {}
            self.map[name] = list
        end
        table.insert(list, predicate)
        self._count = self._count + 1
    end

    --- Adds the events to the list of events to watch
    --- @param contexts EventContext[]  The contexts for each event
    --- @return EventWatcher
    function instance:add(contexts)
        if (not contexts) or #contexts == 0 then return self end
        for _, context in ipairs(contexts) do
            self:register(context.event, context.predicate)
        end
        return self
    end

    --- Returns whether this EventWatcher is watching any events
    --- @return boolean
    function instance:any()
        return self._count > 0
    end

    --- Returns how many events have been registered to this EventWatcher
    --- @return integer
    function instance:count()
        return self._count
    end

    --- Adds the given predicate to the list of predicates for the given event name(s)
    --- @param name_or_names string|(string[])  The name(s) of the event(s) to watch
    --- @param predicate fun(...)  The function to invoke when the event is pulled
    --- @return EventWatcher
    function instance:listen(name_or_names, predicate)
        if not name_or_names then
            error("No events were specified to listen for", 2)
        end
        if not predicate then
            error("No predicate was specified", 2)
        end

        if type(name_or_names) == "string" then
            -- The predicate is registered for a single event
            self:register(name_or_names, predicate)
        else
            -- The predicate is registered for multiple events
            for _, name in ipairs(name_or_names) do
                self:register(name, predicate)
            end
        end
        return self
    end

    --- Checks the given event against the registered predicates, invoking any matching predicates with the event parameters
    --- @param event PulledEvent  The event to check
    function instance:check_pulled_event(event)
        local name = event[1]
        if name == nil then return end

        local predicates = self.map[name]
        if predicates then
            for _, predicate in ipairs(predicates) do
                predicate(table.unpack(event, 2))
            end
        end
    end
end

--- @param seconds number
--- @param watcher EventWatcher
local function sleep_with_polling(seconds, watcher)
    local timer = os.startTimer(seconds)

    while true do
        local e = { os.pullEvent() }
        local event = e[1]

        if event == "timer" and e[2] == timer then break end

        watcher:check_pulled_event(e)
    end
end

--- @param wait_interval (fun() : integer)|integer
--- @param init fun()?
--- @param body fun()
--- @param sleep_watcher EventWatcher?
--- @param quit fun()?
local function loop_forever(wait_interval, init, body, sleep_watcher, quit)
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

                if sleep_watcher and sleep_watcher:any() then
                    sleep_with_polling(ticks / 20, sleep_watcher)
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
    class = {
        EventWatcher = EventWatcher
    },
    --- Sleeps for the given number of seconds, but also pulls events while waiting for the sleep timer to expire.
    --- @param seconds number  The number of seconds to sleep for
    --- @param watcher EventWatcher  The table of events to watch while sleeping
    sleep_with_polling = function(seconds, watcher) return trace.scall(sleep_with_polling, seconds, watcher) end,
    --- A utility function to loop forever, with optional logic to run when quitting or restarting the program.
    --- @param wait_interval (fun() : integer)|integer  The amount of ticks to wait between iterations.  Forced to be at least 1.
    --- @param init fun()?  An optional function to run once before the loop starts or when the program is restarted after an error
    --- @param body fun()  The function to run every loop iteration
    --- @param sleep_watcher EventWatcher?  An optional EventWatcher to pull events from while sleeping between loop iterations
    --- @param quit fun()?  An optional function to run when the program is quitting after an error
    loop_forever = function(wait_interval, init, body, sleep_watcher, quit) return trace.scall(loop_forever, wait_interval, init, body, sleep_watcher, quit) end
}