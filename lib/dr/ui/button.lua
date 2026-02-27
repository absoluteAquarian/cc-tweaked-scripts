local paint = require "lib.dr.paint"

local class = require "lib.class"
local exec = require "lib.exec"

--- @class ButtonDefinition : ClassDefinition
--- @field base nil
local Button = class.class("Button")

--- @class ButtonParameters
--- @field x integer  The x coordinate of the top left corner of the button
--- @field y integer  The y coordinate of the top left corner of the button
--- @field label string  The text to display on the button
--- @field color ButtonColorParameters  A table containing the colors used for different parts of the button

--- @class ButtonColorParameters
--- @field fg number  The foreground color to use for the button (see: colors)
--- @field bg number  The background color to use for the button (see: colors)

--- [override] Creates a new Button instance with the given parameters
--- @param terminal table  The terminal this Button will be drawn on
--- @param params ButtonParameters  The parameters for this Button
--- @return Button
function Button:new(terminal, params)
    --- @class Button : ClassInstance
    --- @field base nil
    local instance = self:create_instance(terminal, params)

    --- The terminal this Button is drawn on
    instance.terminal = terminal

    --- The X-coordinate of the top left corner of the button
    instance.x = params.x
    --- The Y-coordinate of the top left corner of the button
    instance.y = params.y

    --- The text to display on the button
    instance.label = params.label

    --- A table containing the colors used for different parts of the button
    instance.color = {
        --- The foreground color to use for the button (see: colors)
        fg = params.color.fg,
        --- The background color to use for the button (see: colors)
        bg = params.color.bg
    }

    --- The Painter instance used to draw this Button
    instance.painter = paint.create(terminal)

    --- @type boolean  Whether this Button can be clicked
    instance.clickable = true

    --- @type boolean  Whether this Button is currently visible on the terminal
    instance.visible = false

    --- Draws this button and marks it as visible
    function instance:draw()
        self.painter:begin()
            :move({ x = self.x, y = self.y })
            :color(self.color.fg, self.color.bg)
            :text(self.label)
            :paint()

        self.visible = true
    end

    --- Hides this Button from the terminal
    function instance:hide()
        if not self.visible then return end

        self.painter:begin()
            :move({ x = self.x, y = self.y })
            :color(colors.black, colors.black)
            :text(self.label)
            :paint()

        self.visible = false
    end

    --- Moves the button to the provided coordinates
    --- @param new_x integer  The new X-coordinate of the top left corner of the button
    --- @param new_y integer  The new Y-coordinate of the top left corner of the button
    function instance:move(new_x, new_y)
        local was_visible = self.visible
        if was_visible then self:hide() end
        self.x = new_x
        self.y = new_y
        if was_visible then self:draw() end
    end

    --- @private
    --- @class ButtonEvents  A table containing the events invoked by this Button
    instance.events = {
        --- @type boolean  Whether this Button is currently being clicked
        __clicking = false,
        --- @type function?  Invoked through the "mouse_click" event
        click = nil,
        --- @type function?  Invoked through the "mouse_up" event
        release = nil
    }

    --- Sets the function to be called when this Button is clicked
    --- @param func fun(self: BorderedButton, button: number)?  The function to call when this Button is clicked.<br/>The "button" parameter is the mouse button that was used (see: event mouse_click)
    function instance:set_click_listener(func)
        self.events.click = func
    end

    --- Sets the function to be called when this Button is released after being clicked
    --- @param func fun(self: BorderedButton, button: number)?  The function to call when this Button is released after being clicked.<br/>The "button" parameter is the mouse button that was used (see: event mouse_up)
    function instance:set_release_listener(func)
        self.events.release = func
    end

    --- Returns whether the provided coordinates are within the clickable area of this Button
    --- @param event_x number  The X-coordinate of the click event
    --- @param event_y number  The Y-coordinate of the click event
    --- @return boolean
    function instance:clickable_area_contains(event_x, event_y)
        return event_x >= self.x and event_x <= self.x + #self.label - 1 and event_y == self.y
    end

    --- Gets the EventWatcher object that this Button should listen through
    --- @return EventWatcher?
    --- @return EventWatcher?
    function instance:get_event_watchers()
        if not self.clickable then return nil, nil end

        --- @type EventWatcher, EventWatcher
        return
        {
            event = "mouse_click",
            --- @param button number
            --- @param event_x number
            --- @param event_y number
            predicate = function(button, event_x, event_y)
                -- Check if the click was within the button's label
                if self.visible and self:clickable_area_contains(event_x, event_y) then
                    if self.events.click then self.events.click(self, button) end
                    self.events.__clicking = true
                end
            end
        },
        {
            event = "mouse_up",
            --- @param event_x number
            --- @param event_y number
            predicate = function(button, event_x, event_y)
                -- Check if this is a release for a click that started within the button's label
                if self.visible and self.events.__clicking and self:clickable_area_contains(event_x, event_y) then
                    if self.events.release then self.events.release(self, button) end
                    self.events.__clicking = false
                end
            end
        }
    end

    return instance
end

--- @class BorderedButtonDefinition : ButtonDefinition
--- @field base ButtonDefinition
local BorderedButton = class.class("BorderedButton", Button)

--- @class BorderedButtonParameters : ButtonParameters
--- @field color BorderedButtonColorParameters  [override] A table containing the colors used for different parts of the button

--- @class BorderedButtonColorParameters : ButtonColorParameters
--- @field border number  The foreground color to use for the button's border (see: colors)<br/>The background color is inherited from the terminal

--- [override] Creates a new Button instance with the given parameters
--- @param terminal table  The terminal this Button will be drawn on
--- @param params BorderedButtonParameters  The parameters for this BorderedButton
--- @return BorderedButton
function BorderedButton:new(terminal, params)
    --- @class BorderedButton : Button
    --- @field base Button
    local instance = self:create_instance(terminal, params)
    -- ButtonDefinition:new(terminal, x, y, label, fg, bg)

    --- The foreground color to use for the button's border (see: colors).  The background color is inherited from the terminal
    instance.color.border = params.color.border

    --- [override] Draws this button and marks it as visible
    function instance:draw()
        --   Character layout:
        --
        --   - -   - -   - -
        --   - -   - -   - -
        --   x x   x x   x x
        --
        --   x -   - -   - x
        --   x -   - -   - x
        --   x -   - -   - x
        --
        --   x x   x x   x x
        --   - -   - -   - -
        --   - -   - -   - -

        self.painter:begin()
            -- Draw the border
            :move({ x = self.x, y = self.y })
            :color(self.color.border, "reset")
            --   The top corners and edge
            :swap()
            :text(paint.negated_blocks.LOW, { count = #self.label + 2 })
            --   The left and right edges
            :move({ x = self.x, y = self.y + 1 })
            :swap()
            :text(paint.blocks.HIGH_LEFT_MIDDLE_LEFT_LOW_LEFT)
            :offset(#self.label)
            :swap()
            :text(paint.negated_blocks.HIGH_RIGHT_MIDDLE_RIGHT_LOW_RIGHT)
            --   The bottom corners and edge
            :move({ x = self.x, y = self.y + 2 })
            :swap()
            :text(paint.blocks.HIGH, { count = #self.label + 2 })
            --   The label text
            :move({ x = self.x + 1, y = self.y + 1 })
            :color(self.color.fg, self.color.bg)
            :text(self.label)
            :paint()

        self--[[@as Button]].visible = true
    end

    --- [override] Clears the area occupied by this button if it is currently visible
    function instance:hide()
        if not self.visible then return end

        self.painter:begin()
            :move({ x = self.x, y = self.y })
            :text(" ", { count = #self.label + 2 })
            :move({ x = self.x, y = self.y + 1 })
            :text(" ", { count = #self.label + 2 })
            :move({ x = self.x, y = self.y + 2 })
            :text(" ", { count = #self.label + 2 })
            :paint()

       self--[[@as Button]].visible = false
    end

    --- [override] Returns whether the provided coordinates are within the clickable area of this Button
    function instance:clickable_area_contains(event_x, event_y)
        return event_x >= self.x + 1 and event_x <= self.x + #self.label and event_y == self.y + 1
    end

    return instance
end

--- Creates a new Button instance with the given parameters
--- @param terminal table  The terminal this Button will be drawn on
--- @param params ButtonParameters  The parameters for this Button
--- @return Button
local function create_button(terminal, params)
    return Button:new(terminal, params)
end

--- Creates a new BorderedButton instance with the given parameters
--- @param terminal table  The terminal this Button will be drawn on
--- @param params BorderedButtonParameters  The parameters for this BorderedButton
--- @return BorderedButton
local function create_bordered_button(terminal, params)
    return BorderedButton:new(terminal, params)
end

return {
    class = {
        Button = Button,
        BorderedButton = BorderedButton
    },
    create_button = create_button,
    create_bordered_button = create_bordered_button
}