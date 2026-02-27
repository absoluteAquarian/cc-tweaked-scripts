local class = require "lib.class"
local R_string = require "lib.string"

--- @class PainterDefinition : ClassDefinition
local Painter = class.class("Painter")

--- [override] Creates a new Painter instance for the given target terminal
--- @param target table  The terminal to write to
function Painter:new(target)
    --- @class Painter : ClassInstance
    local instance = self:create_instance(target)

    --- The terminal this Painter will write to
    instance.terminal = target
    --- @type { x: integer, y: integer }?  The anchor point for the current painting operation.  If not nil, reset() will return the cursor to this position.
    instance.anchor_pos = nil
    --- @private
    --- A cache of information related to the target terminal
    instance.cache =
    {
        --- @type number  The original foreground color of the terminal before painting began
        fg = target.getTextColor(),
        --- @type number  The original background color of the terminal before painting began
        bg = target.getBackgroundColor(),
        --- @type boolean  Whether the target terminal is a window in a terminal
        window = pcall(target.isVisible) and pcall(target.setVisible, target.isVisible()),
        --- @type boolean  If the target terminal is a window, this field indicates whether it was originally visible before painting began
        visible = nil
    }

    instance.cache.visible = instance.cache.window and target.isVisible()

    --- Sets the anchor point for this Painter, which will be used as the return point for reset()<br/>
    --- Only one anchor point can be active at once.
    --- @param coordinate { x: integer, y: integer }?  The coordinate of the anchor point, or nil to use the current cursor position as the anchor
    --- @return Painter
    function instance:anchor(coordinate)
        if coordinate then
            self.anchor_pos = coordinate
        else
            local x, y = self.terminal.getCursorPos()
            self.anchor_pos = { x = x, y = y }
        end
        return self
    end

    --- Starts a new painting operation
    --- @return Painter
    function instance:begin()
        if self.cache.window then
            --self.cache.visible = self.terminal.isVisible()
            --self.terminal.setVisible(false)
        end

        self.anchor_pos = nil

        self.cache.fg = self.terminal.getTextColor()
        self.cache.bg = self.terminal.getBackgroundColor()

        return self
    end

    --- Removes all text from the terminal and resets the colors to the original colors before painting began
    --- @return Painter
    function instance:clean()
        local fg = self.terminal.getTextColor()
        local bg = self.terminal.getBackgroundColor()

        self.terminal.setTextColor(self.cache.fg)
        self.terminal.setBackgroundColor(self.cache.bg)

        self.terminal.clear()

        self.terminal.setTextColor(fg)
        self.terminal.setBackgroundColor(bg)

        return self
    end


    --- Sets the current colors for this Painter, which will be used for subsequent writes
    --- @param fg number|"reset"?  The color to set the foreground to (see: colors).<br/>If "reset", the foreground color will be reset to the original color before painting began.<br/>If nil, the foreground color will be left unchanged.
    --- @param bg number|"reset"?  The color to set the background to (see: colors).<br/>If "reset", the background color will be reset to the original color before painting began.<br/>If nil, the background color will be left unchanged.
    --- @return Painter
    function instance:color(fg, bg)
        if fg == "reset" then
            self.terminal.setTextColor(self.cache.fg)
        elseif fg ~= nil then
            self.terminal.setTextColor(fg)
        end

        if bg == "reset" then
            self.terminal.setBackgroundColor(self.cache.bg)
        elseif bg ~= nil then
            self.terminal.setBackgroundColor(bg)
        end

        return self
    end

    --- Removes the current anchor point
    --- @return Painter
    function instance:deanchor()
        self.anchor_pos = nil
        return self
    end

    --- Moves the cursor to the edge of the terminal in the given direction
    --- @param side "left"|"right"|"top"|"bottom"  The side of the terminal to move the cursor to
    --- @return Painter
    function instance:edge(side)
        local w, h = self.terminal.getSize()
        local x, y = self.terminal.getCursorPos()

        if side == "left" then
            self.terminal.setCursorPos(1, y)
        elseif side == "right" then
            self.terminal.setCursorPos(w, y)
        elseif side == "top" then
            self.terminal.setCursorPos(x, 1)
        elseif side == "bottom" then
            self.terminal.setCursorPos(x, h)
        else
            error("Invalid side: " .. tostring(side), 2)
        end

        return self
    end

    --- Clears the specified number of characters to the right of the current cursor position
    --- @param count integer  The number of characters to clear
    --- @return Painter
    function instance:erase(count)
        if count < 1 then return self end
        local x, y = self.terminal.getCursorPos()
        self:text(" ", { count = count })
        self.terminal.setCursorPos(x, y)
        return self
    end

    --- Clears the entire line that the cursor is currently on
    --- @return Painter
    function instance:erase_line()
        local x, y = self.terminal.getCursorPos()
        self.terminal.setCursorPos(1, y)
        self:text(" ", { count = self:width() })
        self.terminal.setCursorPos(x, y)
        return self
    end

    --- Returns the height of the terminal this Painter is writing to
    --- @return integer
    function instance:height()
        local _, h = self.terminal.getSize()
        return h
    end

    --- Moves the cursor to the given coordinate
    --- @param coordinate { x: integer, y: integer }  The coordinate to move the cursor to.  If a coordinate is negative, it is interpreted as a coordinate from the right or bottom edges of the terminal.  For example, { x = -1, y = -1 } would move the cursor to the bottom right corner of the terminal.
    --- @return Painter
    function instance:move(coordinate)
        local x, y

        if coordinate.x < 0 or coordinate.y < 0 then
            local w, h = self.terminal.getSize()

            if coordinate.x < 0 then
                x = w + coordinate.x
            else
                x = coordinate.x
            end

            if coordinate.y < 0 then
                y = h + coordinate.y
            else
                y = coordinate.y
            end
        else
            x, y = coordinate.x, coordinate.y
        end

        if x == 0 then error("X-coordinate for move() cannot be 0", 2) end
        if y == 0 then error("Y-coordinate for move() cannot be 0", 2) end

        self.terminal.setCursorPos(x, y)

        return self
    end

    --- Moves the cursor down to the next line, optionally keeping the same horizontal position
    --- @param keep_indent boolean?  Whether to keep the same horizontal position on the next line, or move back to the left edge.  If nil, defaults to false.
    --- @return Painter
    function instance:nextline(keep_indent)
        local x, y = self.terminal.getCursorPos()
        self.terminal.setCursorPos(keep_indent == true and x or 1, y + 1)
        return self
    end

    --- Writes the string representation of the given object at the current cursor position
    --- @param thing any  The object to write
    --- @param params PainterFunctionTextParams?  Optional parameters for how the text should be written.
    --- @return Painter
    function instance:obj(thing, params)
        return self:text(tostring(thing), params)
    end

    --- Offsets the cursor by the given amounts
    --- @param x integer?  The amount to offset the cursor horizontally, or nil to leave unchanged
    --- @param y integer?  The amount to offset the cursor vertically, or nil to leave unchanged
    --- @return Painter
    function instance:offset(x, y)
        if x ~= nil or y ~= nil then
            local current_x, current_y = self.terminal.getCursorPos()
            self.terminal.setCursorPos(current_x + (x or 0), current_y + (y or 0))
        end
        return self
    end

    --- Ends the current painting operation, displaying the results on the terminal<br/>
    --- This function also restores the colors from before painting began
    function instance:paint()
        if self.cache.window and self.cache.visible then
            -- Setting the window back to visible will trigger it to redraw with the new contents
            --self.terminal.setVisible(true)
        end

        self.terminal.setTextColor(self.cache.fg)
        self.terminal.setBackgroundColor(self.cache.bg)
    end

    --- Moves the cursor back to the anchor point, or to (1, 1) if no anchor point is set
    --- @return Painter
    function instance:reset()
        if self.anchor_pos then
            self.terminal.setCursorPos(self.anchor_pos.x, self.anchor_pos.y)
        else
            self.terminal.setCursorPos(1, 1)
        end
        return self
    end

    --- Swaps the foreground and background colors
    --- @return Painter
    function instance:swap()
        local fg = self.terminal.getTextColor()
        local bg = self.terminal.getBackgroundColor()
        self.terminal.setTextColor(bg)
        self.terminal.setBackgroundColor(fg)
        return self
    end

    --- @class PainterFunctionTextParams
    --- @field vertical boolean?  If true, text will be written vertically starting at the current cursor position; otherwise, text will be written horizontally.
    --- @field ends_at_cursor boolean?  If true, the text will be written so that it ends at the current cursor position instead of starting at it.  For horizontal text, this means the text will be right-aligned to the cursor; for vertical text, this means the text will be bottom-aligned to the cursor.
    --- @field reversed boolean?  If true, the written text's characters will be in reverse order; otherwise, they will be in normal order.
    --- @field count integer?  If not nil, the text will be repeated the given number of times.  For example, with text = "abc" and repeat = 3, the text "abcabcabc" would be written.

    --- Writes the given text at the current cursor position
    --- @param text string  The text to write
    --- @param params PainterFunctionTextParams?  Optional parameters for how the text should be written.
    function instance:text(text, params)
        if params then
            local t
            if params.reversed then
                if params.count then
                    t = R_string.cached_rep(text:reverse(), params.count)
                else
                    t = text:reverse()
                end
            else
                if params.count then
                    t = R_string.cached_rep(text, params.count)
                else
                    t = text
                end
            end

            if params.vertical then
                local x, y = self.terminal.getCursorPos()

                if params.ends_at_cursor then
                    y = y - #t + 1
                end

                for i = 1, #t do
                    self.terminal.setCursorPos(x, y + i - 1)
                    self.terminal.write(t:sub(i, i))
                end
            else
                if params.ends_at_cursor then
                    local x, y = self.terminal.getCursorPos()
                    self.terminal.setCursorPos(x - #t + 1, y)
                end

                self.terminal.write(t)
            end
        else
            self.terminal.write(text)
        end

        return self
    end

    --- Returns the width of the terminal this Painter is writing to
    --- @return integer
    function instance:width()
        local w, _ = self.terminal.getSize()
        return w
    end

    return instance
end

--- @class PaintBlockCharacters
local block_chars =
{
    --- @type string
    --- \- -<br/>
    --- \- -<br/>
    --- \- -
    EMPTY = "\128",
    --- @type string
    ---  x -<br/>
    --- \- -<br/>
    --- \- -
    HIGH_LEFT = "\129",
    --- @type string
    --- \- x<br/>
    --- \- -<br/>
    --- \- -
    HIGH_RIGHT = "\130",
    --- @type string
    --- x x<br/>
    --- \- -<br/>
    --- \- -
    HIGH = "\131",
    --- @type string
    --- \- -<br/>
    ---  x -<br/>
    --- \- -
    MIDDLE_LEFT = "\132",
    --- @type string
    ---  x -<br/>
    ---  x -<br/>
    --- \- -
    HIGH_LEFT_MIDDLE_LEFT = "\133",
    --- @type string
    --- \- x<br/>
    ---  x -<br/>
    --- \- -
    HIGH_RIGHT_MIDDLE_LEFT = "\134",
    --- @type string
    ---  x x<br/>
    ---  x -<br/>
    --- \- -
    HIGH_MIDDLE_LEFT = "\135",
    --- @type string
    --- \- -<br/>
    --- \- x<br/>
    --- \- -
    MIDDLE_RIGHT = "\136",
    --- @type string
    ---  x -<br/>
    --- \- x<br/>
    --- \- -
    HIGH_LEFT_MIDDLE_RIGHT = "\137",
    --- @type string
    --- \- x<br/>
    --- \- x<br/>
    --- \- -
    HIGH_RIGHT_MIDDLE_RIGHT = "\138",
    --- @type string
    ---  x x<br/>
    --- \- x<br/>
    --- \- -
    HIGH_MIDDLE_RIGHT = "\139",
    --- @type string
    --- \- -<br/>
    ---  x x<br/>
    --- \- -
    MIDDLE = "\140",
    --- @type string
    ---  x -<br/>
    ---  x x<br/>
    --- \- -
    HIGH_LEFT_MIDDLE = "\141",
    --- @type string
    --- \- x<br/>
    ---  x x<br/>
    --- \- -
    HIGH_RIGHT_MIDDLE = "\142",
    --- @type string
    ---  x x<br/>
    ---  x x<br/>
    --- \- -
    HIGH_MIDDLE = "\143",
    --- @type string
    --- \- -<br/>
    --- \- -<br/>
    ---  x -
    LOW_LEFT = "\144",
    --- @type string
    ---  x -<br/>
    --- \- -<br/>
    ---  x -
    HIGH_LEFT_LOW_LEFT = "\145",
    --- @type string
    --- \- x<br/>
    --- \- -<br/>
    ---  x -
    HIGH_RIGHT_LOW_LEFT = "\146",
    --- @type string
    ---  x x<br/>
    --- \- -<br/>
    ---  x -
    HIGH_LOW_LEFT = "\147",
    --- @type string
    --- \- -<br/>
    ---  x -<br/>
    ---  x -
    MIDDLE_LEFT_LOW_LEFT = "\148",
    --- @type string
    ---  x -<br/>
    ---  x -<br/>
    ---  x -
    HIGH_LEFT_MIDDLE_LEFT_LOW_LEFT = "\149",
    --- @type string
    --- \- x<br/>
    ---  x -<br/>
    ---  x -
    HIGH_RIGHT_MIDDLE_LEFT_LOW_LEFT = "\150",
    --- @type string
    ---  x x<br/>
    ---  x -<br/>
    ---  x -
    HIGH_MIDDLE_LEFT_LOW_LEFT = "\151",
    --- @type string
    --- \- -<br/>
    --- \- x<br/>
    ---  x -
    MIDDLE_RIGHT_LOW_LEFT = "\152",
    --- @type string
    ---  x -<br/>
    --- \- x<br/>
    ---  x -
    HIGH_LEFT_MIDDLE_RIGHT_LOW_LEFT = "\153",
    --- @type string
    --- \- x<br/>
    --- \- x<br/>
    ---  x -
    HIGH_RIGHT_MIDDLE_RIGHT_LOW_LEFT = "\154",
    --- @type string
    ---  x x<br/>
    --- \- x<br/>
    ---  x -
    HIGH_MIDDLE_RIGHT_LOW_LEFT = "\155",
    --- @type string
    --- \- -<br/>
    ---  x x<br/>
    ---  x -
    MIDDLE_LOW_LEFT = "\156",
    --- @type string
    ---  x -<br/>
    ---  x x<br/>
    ---  x -
    HIGH_LEFT_MIDDLE_LOW_LEFT = "\157",
    --- @type string
    --- \- x<br/>
    ---  x x<br/>
    ---  x -
    HIGH_RIGHT_MIDDLE_LOW_LEFT = "\158",
    --- @type string
    ---  x x<br/>
    ---  x x<br/>
    ---  x -
    HIGH_MIDDLE_LOW_LEFT = "\159"
}

--- @class PaintBlockCharactersNegated
local negated_chars = {
    --- @type string
    ---  x x<br/>
    ---  x x<br/>
    ---  x x
    FULL = "\128",
    --- @type string
    --- \- x<br/>
    ---  x x<br/>
    ---  x x
    HIGH_RIGHT_MIDDLE_LOW = "\129",
    --- @type string
    ---  x -<br/>
    ---  x x<br/>
    ---  x x
    HIGH_LEFT_MIDDLE_LOW = "\130",
    --- @type string
    --- \- -<br/>
    ---  x x<br/>
    ---  x x
    MIDDLE_LOW = "\131",
    --- @type string
    ---  x x<br/>
    --- \- x<br/>
    ---  x x
    HIGH_MIDDLE_RIGHT_LOW = "\132",
    --- @type string
    --- \- x<br/>
    --- \- x<br/>
    ---  x x
    HIGH_RIGHT_MIDDLE_RIGHT_LOW = "\133",
    --- @type string
    ---  x -<br/>
    --- \- x<br/>
    ---  x x
    HIGH_LEFT_MIDDLE_RIGHT_LOW = "\134",
    --- @type string
    --- \- -<br/>
    --- \- x<br/>
    ---  x x
    MIDDLE_RIGHT_LOW = "\135",
    --- @type string
    ---  x x<br/>
    ---  x -<br/>
    ---  x x
    HIGH_MIDDLE_LEFT_LOW = "\136",
    --- @type string
    --- \- x<br/>
    ---  x -<br/>
    ---  x x
    HIGH_RIGHT_MIDDLE_LEFT_LOW = "\137",
    --- @type string
    ---  x -<br/>
    ---  x -<br/>
    ---  x x
    HIGH_LEFT_MIDDLE_LEFT_LOW = "\138",
    --- @type string
    --- \- -<br/>
    ---  x -<br/>
    ---  x x
    MIDDLE_LEFT_LOW = "\139",
    --- @type string
    ---  x x<br/>
    --- \- -<br/>
    ---  x x
    HIGH_LOW = "\140",
    --- @type string
    --- \- x<br/>
    --- \- -<br/>
    ---  x x
    HIGH_RIGHT_LOW = "\141",
    --- @type string
    ---  x -<br/>
    --- \- -<br/>
    ---  x x
    HIGH_LEFT_LOW = "\142",
    --- @type string
    --- \- -<br/>
    --- \- -<br/>
    ---  x x
    LOW = "\143",
    --- @type string
    ---  x x<br/>
    ---  x x<br/>
    --- \- x
    HIGH_MIDDLE_LOW_RIGHT = "\144",
    --- @type string
    --- \- x<br/>
    ---  x x<br/>
    --- \- x
    HIGH_RIGHT_MIDDLE_LOW_RIGHT = "\145",
    --- @type string
    ---  x -<br/>
    ---  x x<br/>
    --- \- x
    HIGH_LEFT_MIDDLE_LOW_RIGHT = "\146",
    --- @type string
    --- \- -<br/>
    ---  x x<br/>
    --- \- x
    MIDDLE_LOW_RIGHT = "\147",
    --- @type string
    ---  x x<br/>
    --- \- x<br/>
    --- \- x
    HIGH_MIDDLE_RIGHT_LOW_RIGHT = "\148",
    --- @type string
    --- \- x<br/>
    --- \- x<br/>
    --- \- x
    HIGH_RIGHT_MIDDLE_RIGHT_LOW_RIGHT = "\149",
    --- @type string
    ---  x -<br/>
    --- \- x<br/>
    --- \- x
    HIGH_LEFT_MIDDLE_RIGHT_LOW_RIGHT = "\150",
    --- @type string
    --- \- -<br/>
    --- \- x<br/>
    --- \- x
    MIDDLE_RIGHT_LOW_RIGHT = "\151",
    --- @type string
    ---  x x<br/>
    ---  x -<br/>
    --- \- x
    HIGH_MIDDLE_LEFT_LOW_RIGHT = "\152",
    --- @type string
    --- \- x<br/>
    ---  x -<br/>
    --- \- x
    HIGH_RIGHT_MIDDLE_LEFT_LOW_RIGHT = "\153",
    --- @type string
    ---  x -<br/>
    ---  x -<br/>
    --- \- x
    HIGH_LEFT_MIDDLE_LEFT_LOW_RIGHT = "\154",
    --- @type string
    --- \- -<br/>
    ---  x -<br/>
    --- \- x
    MIDDLE_LEFT_LOW_RIGHT = "\155",
    --- @type string
    ---  x x<br/>
    --- \- -<br/>
    --- \- x
    HIGH_LOW_RIGHT = "\156",
    --- @type string
    --- \- x<br/>
    --- \- -<br/>
    --- \- x
    HIGH_RIGHT_LOW_RIGHT = "\157",
    --- @type string
    ---  x -<br/>
    --- \- -<br/>
    --- \- x
    HIGH_LEFT_LOW_RIGHT = "\158",
    --- @type string
    --- \- -<br/>
    --- \- -<br/>
    --- \- x
    LOW_RIGHT = "\159"
}

return {
    class = {
        Painter = Painter
    },
    --- @type PaintBlockCharacters
    --- A list of characters that render as blocks in a 2x3 grid, indexed by descriptive names of which parts of the grid they fill.<br/>
    --- HIGH refers to the topmost row, MIDDLE refers to the middle row, and LOW refers to the bottom row.  LEFT and RIGHT refer to the respective columns.<br/>
    --- In the field descriptions, "x" represents the foreground color and "-" represents the background color.
    blocks = block_chars,
    --- @type PaintBlockCharactersNegated
    --- A list of characters that render as blocks in a 2x3 grid, indexed by descriptive names of which parts of the grid they leave unfilled.<br/>
    --- HIGH refers to the topmost row, MIDDLE refers to the middle row, and LOW refers to the bottom row.  LEFT and RIGHT refer to the respective columns.<br/>
    --- In the field descriptions, "x" represents the background color and "-" represents the foreground color.
    --- ```lua
    --- local paint = require "lib.dr.paint"
    --- ...
    --- local painter = paint.create(term.current())
    --- -- Draws a block character with the "J" shape in yellow
    --- -- swap() is used to swap the terminal colors so that the block identifier matches how it's displayed
    --- painter:begin()
    ---     :color(colors.yellow, colors.black)
    ---     :swap()
    ---     :text(paint.negated_blocks.HIGH_RIGHT_MIDDLE_RIGHT_LOW)
    ---     :swap()
    ---     :paint()
    --- ```
    negated_blocks = negated_chars
}