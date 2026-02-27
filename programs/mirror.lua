local filesystem = require "lib.cc.filesystem"

local button = require "lib.dr.ui.button"

local paint = require "lib.dr.paint"

local class = require "lib.class"
local config = require "lib.config"
local exec = require "lib.exec"
local R_table = require "lib.table"

local cfg_file = config.unserialize("mirror")

--- @class DrivePeripheralActor : ClassDefinition
local DrivePeripheralActor = class.class("DrivePeripheralActor")

--- @class DrivePeripheralActorRenderParams
--- @field display_name string  The display name of the actor
--- @field line integer  The line on which to render this actor
--- @field err_disconnected string  The error message to display when the peripheral is not connected
--- @field err_no_disk string  The error message to display when the disk drive peripheral does not have a disk present

--- [override] Creates a new DrivePeripheralActor instance with the given parameters
--- @param cfg_key string  The key in the config file to read the peripheral name from
--- @param default_peripheral string  The default peripheral name to use if the config value is not set
--- @param painter Painter  The painter to use for rendering the state of this peripheral
--- @param render_params DrivePeripheralActorRenderParams  The parameters to use for rendering this actor to the terminal
--- @return DrivePeripheralActorInstance
function DrivePeripheralActor:new(cfg_key, default_peripheral, painter, render_params)
    --- @class DrivePeripheralActorInstance : ClassInstance
    local instance = DrivePeripheralActor:create_instance(cfg_key, painter)

    --- @private
    --- The key in the config file to read the peripheral name from
    instance.cfg_key = cfg_key
    --- @private
    --- The painter to use for rendering the state of this peripheral to the terminal
    instance.painter = painter
    --- @private
    --- The parameters to use for rendering this actor's state to the terminal
    instance.render_params = render_params
    --- @type table?  The disk drive peripheral.  Will be nil if the target peripheral is disconnected or not a disk drive.
    instance.disk_drive = nil
    --- @type string?  The directory corresponding to the disk in the peripheral.  Will be nil if no disk is present.
    instance.mount = nil
    --- @type string  The name of the peripheral this actor will interact with
    instance.peripheral_name = nil
    --- @private
    --- @type string  The previous peripheral name read from the config file
    instance.__prev_peripheral_name = ""
    --- @type boolean  Whether the peripheral is connected
    instance.exists = false
    --- @type boolean  Whether the disk drive peripheral has a floppy disk present
    instance.ready = false

    --- Reloads the peripheral name from the config file
    function instance:reload_peripheral()
        local cfg = cfg_file:getString(self.cfg_key)

        if not cfg then
            -- Save the default peripheral to the config
            cfg_file:setString(self.cfg_key, default_peripheral)
            config.serialize(cfg_file)
            cfg = default_peripheral
        end

        self.__prev_peripheral_name = self.peripheral_name or ""
        self.peripheral_name = cfg
    end

    --- Updates the state of this actor depending on its target peripheral and renders the new state to the terminal
    function instance:check_peripheral_state()
        self.exists = false
        self.ready = false
        self.disk_drive = nil
        self.mount = nil

        local wrapped = peripheral.wrap(self.peripheral_name)
        if wrapped and pcall(wrapped.isDiskPresent) and pcall(wrapped.hasData) then
            self.exists = true
            self.disk_drive = wrapped
            self.mount = wrapped.getMountPath()
            self.ready = wrapped.isDiskPresent() and wrapped.hasData()
        end
    end

    --- Renders the initial display for this actor in the terminal
    function instance:render_template()
        self.painter:begin()
            :move({ x = 2, y = self.render_params.line })
            :text("[")
            :color(colors.red, nil)
            :text("\120")
            :color("reset", nil)
            :text("] ")
            :color(colors.red, nil)
            :text(self.render_params.display_name)
            :color("reset", nil)
            :text(" (\"")
            :erase(#self.__prev_peripheral_name + 2)
            :text(self.peripheral_name or "")
            :text("\")")
            :paint()
    end

    --- Renders the current state of this actor to the terminal
    function instance:render_current_state()
        --- @type number, string
        local color, icon

        if self.exists and self.ready then
            color = colors.green
            icon = "\186"
        else
            color = colors.red
            icon = "\120"
        end

        self.painter:begin()
            :move({ x = 2, y = self.render_params.line })
            :color(color, nil)
            :text(icon)
            :offset(2, nil)
            :text(self.render_params.display_name)
            :color("reset", nil)
            :offset(3, nil)
            :erase(#self.__prev_peripheral_name + 2)
            :text(self.peripheral_name or "")
            :text("\")")
            :paint()
    end

    --- Gets the current error message to display based on the state of this actor's peripheral, or nil if there is no error
    --- @return string?
    function instance:get_error()
        if not self.exists then
            return self.render_params.err_disconnected
        elseif not self.ready then
            return self.render_params.err_no_disk
        else
            return nil
        end
    end

    --- Updates this actor's state if the provided peripheral matches its target peripheral
    --- @param name string  The name of the peripheral that was connected
    --- @return boolean success  Whether this actor's state was updated
    --- @return string? err  An error message to display, or nil if there is no error
    function instance:on_peripheral_changed(name)
        if name == self.peripheral_name then
            self:check_peripheral_state()
            self:render_current_state()
            return true, self:get_error()
        end
        return false, nil
    end

    return instance
end

local wait_cycle = 1
local copy_stage = 0
local tick = 0

local w, h = term.current().getSize()

--- @type table
local window_instance = window.create(term.current(), 2, 2, w - 1, h - 1, false)
window_instance.setCursorBlink(false)

local global_painter = paint.create(window_instance)

--- @class FileSystemEntry
--- @field path string  The path to the file
--- @field text string  The text contained in the file

--- @type FileSystemEntry[]  The buffer of files copied from the source disk
local buffer_fs = {}
--- @type function?  An iterator function over the source disk's mounted path
local iterator = nil
--- @type integer
local num_copied = 0

--- @param painter Painter
--- @param msg string?
local function display_error(painter, msg)
    if msg then
        painter:begin()
            :move({ x = 2, y = -2 })  -- Negative y is an offset from the bottom of the terminal
            :erase(painter:width() - 2)
            :color(colors.red, nil)
            :text(msg)
            :color("reset", nil)
            :paint()
    else
        painter:begin()
            :move({ x = 2, y = -2 })  -- Negative y is an offset from the bottom of the terminal
            :erase(painter:width() - 2)
            :paint()
    end
end

local actor_source = DrivePeripheralActor:new(
    "SRC",
    "left",
    paint.create(window_instance),
    {
        display_name = "Source",
        line = 3,
        err_disconnected = "ERR_INVALID_SRC",
        err_no_disk = "ERR_NO_DISK_SRC"
    }
)

local actor_destination = DrivePeripheralActor:new(
    "DEST",
    "right",
    paint.create(window_instance),
    {
        display_name = "Destination",
        line = 4,
        err_disconnected = "ERR_INVALID_DEST",
        err_no_disk = "ERR_NO_DISK_DEST"
    }
)

local button_start = button.create_bordered_button(
    window_instance,
    {
        x = 3,
        y = 5,
        label = "Start",
        color =
        {
            fg = colors.white,
            bg = colors.green,
            border = colors.lightGray
        }
    }
)

local button_reset = button.create_bordered_button(
    window_instance,
    {
        x = button_start.x + #button_start.label + 2 + 4,  -- 4 is the horizontal padding of the button
        y = button_start.y,
        label = "Reset",
        color =
        {
            fg = colors.white,
            bg = colors.red,
            border = colors.lightGray
        }
    }
)

button_reset:set_release_listener(
    function(self, btn)
        -- Left click
        if btn == 1 then
            -- Reset the program
            copy_stage = -1
        end
    end
)

--- @param p string  The name of the updated peripheral
local function check_actors(p)
    local updated, err = actor_source:on_peripheral_changed(p)
    if not updated then
        updated, err = actor_destination:on_peripheral_changed(p)
    end
    if updated then
        display_error(global_painter, err)
    end
end

local function init_window_canvas()
    --   Border:
    --
    --   x x   x x   x x
    --   x -   - -   - x
    --   x -   - -   - x
    --
    --   x -   - -   - x
    --   x -   - -   - x
    --   x -   - -   - x
    --
    --   x -   - -   - x
    --   x -   - -   - x
    --   x x   x x   x x

    local was_visible = window_instance.isVisible()
    window_instance.setVisible(false)

    global_painter:begin()
        :clean()
        :reset()
        -- The window border
        :color(colors.blue, colors.black)
        --   The top corners and edge
        :text(paint.blocks.HIGH_MIDDLE_LEFT_LOW_LEFT)
        :text(paint.blocks.HIGH, { count = global_painter:width() - 2 })
        :swap()
        :text(paint.negated_blocks.HIGH_MIDDLE_RIGHT_LOW_RIGHT)
        :swap()
        --   The left edge
        :move({ x = 1, y = 2 })
        :text(paint.blocks.HIGH_LEFT_MIDDLE_LEFT_LOW_LEFT, { count = global_painter:height() - 2, vertical = true })
        --   The right edge
        :move({ x = -1, y = 2 })
        :swap()
        :text(paint.negated_blocks.HIGH_RIGHT_MIDDLE_RIGHT_LOW_RIGHT, { count = global_painter:height() - 2, vertical = true })
    --    :swap()
        --   The bottom corners and edge
        :move({ x = 1, y = -1 })
    --    :swap()
        :text(paint.negated_blocks.HIGH_LEFT_MIDDLE_LEFT_LOW)
        :text(paint.negated_blocks.LOW, { count = global_painter:width() - 2 })
        :text(paint.negated_blocks.HIGH_RIGHT_MIDDLE_RIGHT_LOW)
        :swap()
        -- Waiting for disks to be ready...
        :move({ x = 2, y = 2 })
        :color("reset", "reset")
        :text("Waiting for disks to be ready .")
        :nextline(false)
        :paint()

    actor_source:render_template()
    actor_destination:render_template()

    button_reset:draw()

    display_error(global_painter, actor_source:get_error() or actor_destination:get_error())

    window_instance.setVisible(was_visible)
end

exec.loop_forever(
    -- wait_interval
    function()
        return copy_stage == 0 and 5 or 1
    end,
    -- init
    function()
        actor_source:reload_peripheral()
        actor_destination:reload_peripheral()

        actor_source:check_peripheral_state()
        actor_destination:check_peripheral_state()

        -- Render the initial state

        init_window_canvas()
    end,
    -- body
    function()
        ::check_stage::
        if copy_stage == -1 then
            -- Clean up objects used by later stages

            buffer_fs = {}
            iterator = nil

            wait_cycle = 1
            tick = 0

            window_instance.setVisible(false)

            init_window_canvas()

            button_start.visible = false
            button_start:set_release_listener(nil)

            window_instance.setVisible(true)

            copy_stage = 0
            goto check_stage
        elseif copy_stage == 0 then
            -- Wait for both disks to be ready before proceeding

            if actor_source.ready and actor_destination.ready then
                global_painter:begin()
                    :move({ x = 2, y = 2 })
                    :erase(#"Waiting for disks to be ready ...")
                    :text("Disks are ready.")
                    :paint()

                wait_cycle = 1
                tick = 0

                copy_stage = 1
                goto check_stage
            else
                window_instance.setVisible(false)
                
                wait_cycle = wait_cycle == 3 and 1 or wait_cycle + 1

                global_painter:begin()
                    -- Waiting for disks to be ready...
                    :move({ x = 2 + #"Waiting for disks to be ready " + 1, y = 2 })
                    :erase(3)
                    :text(".", { count = wait_cycle })
                    :paint()

                tick = (tick + 1) % 24  -- Cycles every (5 * 24) / 20 = 6 seconds

                if tick == 0 then
                    -- Manually check the states of each actor
                    actor_source:reload_peripheral()
                    actor_source:check_peripheral_state()
                    actor_source:render_current_state()
                    actor_destination:reload_peripheral()
                    actor_destination:check_peripheral_state()
                    actor_destination:render_current_state()

                    display_error(global_painter, actor_source:get_error() or actor_destination:get_error())
                end

                window_instance.setVisible(true)
            end
        elseif copy_stage == 1 then
            -- Reinitialize the button

            button_start:set_release_listener(
                function(self, btn)
                    -- Left click
                    if copy_stage == 2 and btn == 1 then
                        -- Fade out the button

                        window_instance.setVisible(false)

                        self.color.fg = colors.lightGray
                        self.color.bg = colors.gray
                        self.color.border = colors.gray

                        self:draw()

                        -- Display the next message

                        global_painter:begin()
                            :move({ x = 2, y = 9 })
                            :text("Collecting source files .   (total: -)")
                            :paint()

                        window_instance.setVisible(true)

                        wait_cycle = 1
                        iterator = filesystem.iterate_all_files(actor_source.mount)

                        copy_stage = 3
                    end
                end
            )

            button_start:draw()

            copy_stage = 2
        elseif copy_stage == 2 then
            -- Wait for the user to click the button

            if (not actor_source.ready) or (not actor_destination.ready) then
                -- Reset the program
                copy_stage = -1
                goto check_stage
            end
        elseif copy_stage == 3 then
            -- Collect the files to use

            if (not actor_source.ready) or (not actor_destination.ready) then
                -- Reset the program
                copy_stage = -1
                goto check_stage
            end

            --- @type string?
            local file = iterator--[[@as fun():string?]]()

            if file then
                -- Get the file's text
                local handle = fs.open(file, "r")
                local text = handle.readAll()
                handle.close()
                table.insert(buffer_fs, { path = file, text = text })

                -- Display the total file count

                window_instance.setVisible(false)

                global_painter:begin()
                    :move({ x = 2 + #"Collecting source files ... (total: " + 1, y = 9 })
                    :obj(#buffer_fs)
                    :text(")")
                    :paint()

                tick = (tick + 1) % 5

                if tick == 0 then
                    wait_cycle = wait_cycle == 3 and 1 or wait_cycle + 1

                    global_painter:begin()
                        :move({ x = 2 + #"Collecting source files" + 1, y = 9 })
                        :erase(3)
                        :text(".", { count = wait_cycle })
                        :paint()
                end

                window_instance.setVisible(true)
            else
                -- No more files to collect
                iterator = R_table.yield_ipairs(buffer_fs)

                -- Display the next message
                local text_total = tostring(#buffer_fs)

                global_painter:begin()
                    :move({ x = 2, y = 10 })
                    :text("Copying files to destination .   (copied: ")
                    :text("-", { count = #text_total })
                    :text("/" .. text_total .. ")")
                    :paint()

                wait_cycle = 1
                tick = 0

                copy_stage = 4
            end
        elseif copy_stage == 4 then
            -- Copy the files to the destination disk

            if (not actor_source.ready) or (not actor_destination.ready) then
                -- Reset the program
                copy_stage = -1
                goto check_stage
            end

            window_instance.setVisible(false)

            local path, contents = iterator--[[@as fun():string?, string?]]()

            if path then
                -- Copy the contents of the file to the destination disk
                local dest_path = actor_destination.mount .. path:sub(#actor_source.mount + 1)
                local handle = fs.open(dest_path, "w")
                handle.write(contents)
                handle.flush()
                handle.close()

                num_copied = num_copied + 1

                -- Display the copied file count
                local text_num = tostring(num_copied)
                local text_total = tostring(#buffer_fs)

                global_painter:begin()
                    :move({ x = 2 + #"Copying files to destination... (copied: " + 1, y = 10 })
                    :erase(#text_total)
                    :offset(#text_total - #text_num, nil)
                    :text(text_num)
                    :paint()
            else
                -- No more files to copy
                global_painter:begin()
                    :move({ x = 2, y = 11 })
                    :text("Copy complete! Reset or eject a disk to restart.")
                    :paint()

                copy_stage = 5
            end

            window_instance.setVisible(true)
        elseif copy_stage == 5 then
            -- Reset if a disk was ejected
            if (not actor_source.ready) or (not actor_destination.ready) then
                -- Reset the program
                copy_stage = -1
                goto check_stage
            end
        end
    end,
    -- sleep_watchers
    {
        {
            event = "peripheral",
            predicate = check_actors
        },
        {
            event = "peripheral_detach",
            predicate = check_actors
        },
        {
            event = "disk",
            predicate = check_actors
        },
        {
            event = "disk_eject",
            predicate = check_actors
        },
        button_start:get_event_watchers(),
        button_reset:get_event_watchers()
    },
    -- quit
    nil
)