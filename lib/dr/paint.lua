local canvas = require "lib.dr.canvas"

local class = require "lib.class"
local R_math = require "lib.math"
local R_string = require "lib.string"

local native = {
    math = {
        abs = math.abs,
        huge = math.huge,
        max = math.max,
        min = math.min
    },
    string = {
        sub = string.sub,
        reverse = string.reverse
    }
}

--- @class PainterDefinition : ClassDefinition
--- @field base nil
--- @field class PainterDefinition
local Painter = class.class("Painter")

--- @class PainterFunctionTextParams
--- @field vertical boolean?  If <code>true</code>, text will be written vertically starting at the current cursor position; otherwise, text will be written horizontally.
--- @field tail_align boolean?  If <code>true</code>, the text will be written so that it ends at the current cursor position instead of starting at it.<br/>For horizontal text, this means the text will be right-aligned to the cursor; for vertical text, this means the text will be bottom-aligned to the cursor.
--- @field reversed boolean?  If <code>true</code>, the written text's characters will be in reverse order; otherwise, they will be in normal order.
--- @field count integer?  If not <code>nil</code>, the text will be repeated the given number of times.<br/>For example, with <code>text = "abc"</code> and <code>repeat = 3</code>, the text <code>"abcabcabc"</code> would be written.

--- [override] Creates a new <code>Painter</code> instance for the given target terminal
--- @param target table  The terminal to write to
function Painter:new(target)
    --- @class Painter : ClassInstance
    --- @field base nil
    --- @field class PainterDefinition
    --- @field this Painter
    local instance = self:create_instance(target)

    --- The terminal the painter will write to
    instance.terminal = target
    --- @type { x: integer, y: integer }?  The anchor point for the current painting operation.<br/>If not <code>nil</code>, <code>reset()</code> will return the cursor to this position.
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

    --- Sets the anchor point for the painter, which will be used as the return point for reset()<br/>
    --- Only one anchor point can be active at once.
    --- @param coordinate { x: integer, y: integer }?  The coordinate of the anchor point, or <code>nil</code> to use the current cursor position as the anchor
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


    --- Sets the current colors for the painter, which will be used for subsequent writes
    --- @param fg number|"reset"?  The color to set the foreground to (see: <code>colors</code>).<br/>If <code>"reset"</code>, the foreground color will be reset to the original color before painting began.<br/>If <code>nil</code>, the foreground color will be left unchanged.
    --- @param bg number|"reset"?  The color to set the background to (see: <code>colors</code>).<br/>If <code>"reset"</code>, the background color will be reset to the original color before painting began.<br/>If <code>nil</code>, the background color will be left unchanged.
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
            error(string.format("Invalid side: %s", tostring(side)), 2)
        end

        return self
    end

    --- Clears the specified number of characters to the right of the current cursor position
    --- @param count integer  The number of characters to clear
    --- @return Painter
    function instance:erase(count)
        if count < 1 then return self end
        local x, y = self.terminal.getCursorPos()
        self.this:text(" ", { count = count })
        self.terminal.setCursorPos(x, y)
        return self
    end

    --- Clears the entire line that the cursor is currently on
    --- @return Painter
    function instance:erase_line()
        local x, y = self.terminal.getCursorPos()
        self.terminal.setCursorPos(1, y)
        self.this:text(" ", { count = self:width() })
        self.terminal.setCursorPos(x, y)
        return self
    end

    --- Returns the height of the terminal the painter is writing to
    --- @return integer
    function instance:height()
        local _, h = self.terminal.getSize()
        return h
    end

    --- Moves the cursor to the given coordinate
    --- @param coordinate { x: integer, y: integer }  The coordinate to move the cursor to.<br/>If a coordinate is negative, it is interpreted as a coordinate from the right or bottom edges of the terminal.<br/>For example, <code>{ x = -1, y = -1 }</code> would move the cursor to the bottom right corner of the terminal.
    --- @return Painter
    function instance:move(coordinate)
        local x, y

        if coordinate.x < 0 or coordinate.y < 0 then
            local w, h = self.terminal.getSize()

            if coordinate.x < 0 then
                x = w + coordinate.x + 1
            else
                x = coordinate.x
            end

            if coordinate.y < 0 then
                y = h + coordinate.y + 1
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
    --- @param keep_indent boolean?  Whether to keep the same horizontal position on the next line, or move back to the left edge.<br/>If <code>nil</code>, defaults to false.
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
        if type(thing.nameof) == "function" and R_string.contains(thing:nameof(), "DeferredPixelPainter") then
            thing--[[@as DeferredPixelPainter]]:paint(self.terminal)
            return self
        end

        return self.this:text(tostring(thing), params)
    end

    --- Offsets the cursor by the given amounts
    --- @param x integer?  The amount to offset the cursor horizontally, or <code>nil</code> to leave unchanged
    --- @param y integer?  The amount to offset the cursor vertically, or <code>nil</code> to leave unchanged
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

    --- Writes the given text at the current cursor position
    --- @param text string  The text to write
    --- @param params PainterFunctionTextParams?  Optional parameters for how the text should be written.
    function instance:text(text, params)
        if type(text) ~= "string" then
            error("Text must be a string", 2)
        end

        if #text == 0 then return self end

        if params then
            local t
            if params.reversed then
                if params.count then
                    t = R_string.cached_rep(native.string.reverse(text), params.count)
                else
                    t = native.string.reverse(text)
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

                if params.tail_align then
                    y = y - #t + 1
                end

                for i = 1, #t do
                    self.terminal.setCursorPos(x, y + i - 1)
                    self.terminal.write(native.string.sub(t, i, i))
                end
            else
                if params.tail_align then
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

    --- Returns the width of the terminal the painter is writing to
    --- @return integer
    function instance:width()
        local w, _ = self.terminal.getSize()
        return w
    end

    return instance
end

--- @private
--- @class AbstractPaintOperationDefinition : ClassDefinition
--- @field base nil
--- @field class AbstractPaintOperationDefinition
local AbstractPaintOperation = class.class("AbstractPaintOperation")

--- [override] Creates a new <code>AbstractPaintOperation</code> instance
--- @return AbstractPaintOperation
function AbstractPaintOperation:new()
    --- @class AbstractPaintOperation : ClassInstance
    --- @field base nil
    --- @field class AbstractPaintOperationDefinition
    --- @field this AbstractPaintOperation
    local instance = self:create_instance()

    --- Executes the painting operation on the given painter
    --- @param painter DeferredPixelPainter  The painter
    function instance:execute(painter) end

    return instance
end

--- @class RecallCallback
--- @field __recall_callback fun() : any  A function representing the value access in a DeferredPixelPainter's data cache

--- @private
--- @param callback any  The possible RecallCallback to check
--- @return any result  If <code>callback</code> is a RecallCallback, returns the result of the callback function; otherwise, returns the parameter itself
local function __extract(callback)
    if type(callback) == "table" and type(callback.__recall_callback) == "function" then
        return callback.__recall_callback()
    else
        return callback
    end
end

--- @class CanvasCoordinate
--- @field x integer  The horizontal position within the painter's canvas
--- @field y integer  The vertical position within the painter's canvas

--- @class CanvasCoordinateAdjustment
--- @field x integer?  The horizontal position or offset within the painter's canvas.
--- @field y integer?  The vertical position or offset within the painter's canvas.

--- @class CanvasArea
--- @field x integer?  The horizontal position of the top-left corner within the painter's canvas.<br/>If <code>nil</code>, <code>left</code> must be defined.<br/>Negative values are interpreted as offsets from the right edge of the canvas.
--- @field y integer?  The vertical position of the top-left corner within the painter's canvas.<br/>If <code>nil</code>, <code>top</code> must be defined.<br/>Negative values are interpreted as offsets from the bottom edge of the canvas.
--- @field width integer?  The width of the area.<br/>If <code>nil</code>, <code>right</code> must be defined.<br/>Negative values are interpreted a relative size compared to the canvas width.
--- @field height integer?  The height of the area.<br/>If <code>nil</code>, <code>bottom</code> must be defined.<br/>Negative values are interpreted a relative size compared to the canvas height.
--- @field left integer?  The horizontal position of the left edge within the painter's canvas.<br/>If <code>nil</code>, <code>x</code> must be defined.<br/>Negative values are interpreted as offsets from the right edge of the canvas.
--- @field top integer?  The vertical position of the top edge within the painter's canvas.<br/>If <code>nil</code>, <code>y</code> must be defined.<br/>Negative values are interpreted as offsets from the bottom edge of the canvas.
--- @field right integer?  The horizontal position of the right edge within the painter's canvas.<br/>If <code>nil</code>, <code>x</code> (or <code>left</code>) and <code>width</code> must be defined.<br/>Negative values are interpreted as offsets from the right edge of the canvas.
--- @field bottom integer?  The vertical position of the bottom edge within the painter's canvas.<br/>If <code>nil</code>, <code>y</code> (or <code>top</code>) and <code>height</code> must be defined.<br/>Negative values are interpreted as offsets from the bottom edge of the canvas.

--- @param area CanvasArea
--- @return integer left
--- @return integer top
--- @return integer right
--- @return integer bottom
local function __resolve_area_bounds(area, enclosing_width, enclosing_height)
    --- @type integer, integer, integer, integer
    local left, top, right, bottom

    --- @param coordinate integer
    --- @param enclosing_dimension integer
    --- @return integer
    local function __resolve_to_absolute(coordinate, enclosing_dimension)
        if coordinate < 0 then
            return enclosing_dimension + coordinate + 1
        else
            return coordinate
        end
    end

    if area.left ~= nil then
        left = __resolve_to_absolute(area.left, enclosing_width)
    elseif area.x ~= nil then
        left = __resolve_to_absolute(area.x, enclosing_width)
    else
        error("Defined area must specify one of ('x') or ('left')", 2)
    end

    if area.top ~= nil then
        top = __resolve_to_absolute(area.top, enclosing_height)
    elseif area.y ~= nil then
        top = __resolve_to_absolute(area.y, enclosing_height)
    else
        error("Defined area must specify one of ('y') or ('top')", 2)
    end

    if area.right ~= nil then
        right = __resolve_to_absolute(area.right, enclosing_width)
    elseif area.width ~= nil then
        right = left + __resolve_to_absolute(area.width, enclosing_width) - 1
    else
        error("Defined area must specify one of (('x' or 'left') and 'width') or ('right')", 2)
    end

    if area.bottom ~= nil then
        bottom = __resolve_to_absolute(area.bottom, enclosing_height)
    elseif area.height ~= nil then
        bottom = top + __resolve_to_absolute(area.height, enclosing_height) - 1
    else
        error("Defined area must specify one of (('y' or 'top') and 'height') or ('bottom')", 2)
    end

    return left, top, right, bottom
end

--- @private
--- @class MovePaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class MovePaintOperationDefinition
local MovePaintOperation = class.class("MovePaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>MovePaintOperation</code> instance with the given parameters
--- @param coordinate (CanvasCoordinateAdjustment|RecallCallback)  The texel coordinate to move to.<br/>If a coordinate is negative, it is interpreted as a coordinate from the right or bottom edges of the canvas.<br/>For example, <code>{ x = -1, y = -1 }</code> would move to the bottom right corner of the canvas.
--- @param relative boolean  Whether the movement is relative to the painter's current cursor position (<code>true</code>) or absolute within the painter's canvas (<code>false</code>).
--- @return MovePaintOperation
function MovePaintOperation:new(coordinate, relative)
    --- @class MovePaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    --- @field class MovePaintOperationDefinition
    --- @field this MovePaintOperation
    local instance = self:create_instance(coordinate, relative)

    --- The absolute or relative position
    instance.coordinate = coordinate
    --- Whether the movement is relative to the painter's current cursor position (<code>true</code>) or absolute within the painter's canvas (<code>false</code>).
    instance.relative = relative

    function instance:execute(painter)
        local cursor = painter.params.cursor
        local target_x, target_y

        local coord = __extract(self.coordinate) --[[@as CanvasCoordinateAdjustment]]

        if self.relative then
            target_x = cursor.x + (coord.x or 0)
            target_y = cursor.y + (coord.y or 0)
        else
            target_x = coord.x == nil and cursor.x or (coord.x < 0 and (painter.canvas.texel_width + coord.x + 1) or coord.x)
            target_y = coord.y == nil and cursor.y or (coord.y < 0 and (painter.canvas.texel_height + coord.y + 1) or coord.y)
        end

        -- Restrict the coordinates to be within the canvas
        target_x = native.math.max(1, native.math.min(painter.canvas.texel_width, target_x))
        target_y = native.math.max(1, native.math.min(painter.canvas.texel_height, target_y))

        cursor.x = target_x
        cursor.y = target_y
    end

    return instance
end

--- @class ColorChangePaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class ColorChangePaintOperationDefinition
local ColorChangePaintOperation = class.class("ColorChangePaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>ColorChangePaintOperation</code> instance with the given parameters
--- @param fg (number|RecallCallback|"reset")?  The color to set the foreground to (see: <code>colors</code>).<br/>If <code>"reset"</code>, the foreground color will be reset to the original color before painting began.<br/>If <code>nil</code>, the foreground color will be left unchanged.
--- @param bg (number|RecallCallback|"reset")?  The color to set the background to (see: <code>colors</code>).<br/>If <code>"reset"</code>, the background color will be reset to the original color before painting began.<br/>If <code>nil</code>, the background color will be left unchanged.
--- @return ColorChangePaintOperation
function ColorChangePaintOperation:new(fg, bg)
    --- @class ColorChangePaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    --- @field class ColorChangePaintOperationDefinition
    --- @field this ColorChangePaintOperation
    local instance = self:create_instance(fg, bg)

    instance.fg = fg
    instance.bg = bg

    function instance:execute(painter)
        local target = painter.params.color

        local color = __extract(self.fg) --[[@as (number|"reset")?]]
        if color then
            if type(color) == "string" then
                if color == "reset" then
                    target.fg = painter.canvas.fg
                end
            else
                target.fg = color
            end
        end

        color = __extract(self.bg) --[[@as (number|"reset")?]]
        if color then
            if type(color) == "string" then
                if color == "reset" then
                    target.bg = painter.canvas.bg
                end
            else
                target.bg = color
            end
        end
    end

    return instance
end

--- @class ColorSwapPaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class ColorSwapPaintOperationDefinition
local ColorSwapPaintOperation = class.class("ColorSwapPaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>ColorSwapPaintOperation</code> instance
--- @return ColorSwapPaintOperation
function ColorSwapPaintOperation:new()
    --- @class ColorSwapPaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    --- @field class ColorSwapPaintOperationDefinition
    --- @field this ColorSwapPaintOperation
    local instance = self:create_instance()

    function instance:execute(painter)
        local target = painter.params.color
        local fg, bg = target.fg, target.bg
        target.fg = bg
        target.bg = fg
    end

    return instance
end

--- @class TextPaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class TextPaintOperationDefinition
local TextPaintOperation = class.class("TextPaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>TextPaintOperation</code> instance with the given parameters
--- @param text (string|RecallCallback)  The text to write
--- @param params (PainterFunctionTextParams|RecallCallback)?  The parameters for writing the text
function TextPaintOperation:new(text, params)
    --- @class TextPaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    --- @field class TextPaintOperationDefinition
    --- @field this TextPaintOperation
    local instance = self:create_instance(text)

    instance.text = text
    instance.params = params

    --- @protected
    --- @return string
    function instance:get_text() return __extract(self.text) end

    function instance:execute(painter)
        local self_text = self.this:get_text()

        if self_text == nil or #self_text == 0 then return end

        local painter_params = painter.params
        local cursor = painter_params.cursor
        local x, y = cursor.x, cursor.y
        local color = painter_params.color

        local self_params = __extract(self.params) --[[@as PainterFunctionTextParams?]]

        local _, end_x, end_y = painter.canvas:set_texel_many(
            x,
            y,
            self_text,
            {
                fg = color.fg,
                bg = color.bg,
                vertical = self_params and self_params.vertical,
                tail_align = self_params and self_params.tail_align,
                reversed = self_params and self_params.reversed,
                count = self_params and self_params.count
            }
        )

        cursor.x = end_x
        cursor.y = end_y
    end

    return instance
end

--- @class ObjectToStringPaintOperationDefinition : TextPaintOperationDefinition
--- @field base TextPaintOperationDefinition
--- @field class ObjectToStringPaintOperationDefinition
local ObjectToStringPaintOperation = class.class("ObjectToStringPaintOperation", TextPaintOperation)

--- [override] Creates a new <code>ObjectToStringPaintOperation</code> instance with the given parameters
--- @param obj any  The object to paint
--- @param params (PainterFunctionTextParams|RecallCallback)?  The parameters for writing the text
--- @return ObjectToStringPaintOperation
function ObjectToStringPaintOperation:new(obj, params)
    --- @class ObjectToStringPaintOperation : TextPaintOperation
    --- @field base TextPaintOperation
    --- @field class ObjectToStringPaintOperationDefinition
    --- @field this ObjectToStringPaintOperation
    --- @field text nil
    local instance = self:create_instance("", params)
    -- TextPaintOperation:new(text, params)

    instance.obj = obj

    --- [override]
    function instance:get_text() return tostring(__extract(self.obj)) end

    return instance
end

--- @class ErasePaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class ErasePaintOperationDefinition
local ErasePaintOperation = class.class("ErasePaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>ErasePaintOperation</code> instance with the given parameters
--- @param params TexelEraseParameters|RecallCallback  The parameters for erasing texels on the painter's canvas
--- @return ErasePaintOperation
function ErasePaintOperation:new(params)
    --- @class ErasePaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    --- @field class ErasePaintOperationDefinition
    --- @field this ErasePaintOperation
    local instance = self:create_instance(params)

    instance.params = params

    function instance:execute(painter)
        local cursor = painter.params.cursor

        painter.canvas:erase_texel(
            cursor.x,
            cursor.y,
            __extract(self.params) --[[@as TexelEraseParameters]]
        )
    end

    return instance
end

--- @class EraseTexelsPaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class EraseTexelsPaintOperationDefinition
local EraseTexelsPaintOperation = class.class("EraseTexelsPaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>EraseTexelsPaintOperation</code> instance with the given parameters<br/>
--- Unlike <code>ErasePaintOperation</code>, this operation draws space characters to erase the texels instead of making them transparent
--- @param params TexelEraseParameters|RecallCallback  The parameters for erasing texels on the painter's canvas
function EraseTexelsPaintOperation:new(params)
    --- @class EraseTexelsPaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    --- @field class EraseTexelsPaintOperationDefinition
    --- @field this EraseTexelsPaintOperation
    local instance = self:create_instance(params)

    instance.params = params

    function instance:execute(painter)
        local painter_params = painter.params
        local cursor = painter_params.cursor
        local color = painter_params.color

        local params = __extract(self.params) --[[@as TexelEraseParameters]]

        painter.canvas:set_texel_many(
            cursor.x,
            cursor.y,
            " ",
            {
                fg = color.fg,
                bg = color.bg,
                vertical = params.vertical,
                tail_align = params.tail_align,
                count = params.count,
                forced = true
            }
        )

        -- Note: set_texel_many() does not update the cursor position
    end

    return instance
end

--- @class CanvasPixelCoordinate
--- @field x integer  The horizontal pixel coordinate within the painter's canvas
--- @field y integer  The vertical pixel coordinate within the painter's canvas

--- @class AbstractPixelPaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class AbstractPixelPaintOperationDefinition
local AbstractPixelPaintOperation = class.class("AbstractPixelPaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>AbstractPixelPaintOperation</code> instance with the given parameters
--- @param coordinate CanvasPixelCoordinate|RecallCallback  The pixel position within the painter's canvas.<br/>One texel coordinate is 2 pixels wide by 3 pixels tall.
function AbstractPixelPaintOperation:new(coordinate)
    --- @class AbstractPixelPaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    --- @field class AbstractPixelPaintOperationDefinition
    --- @field this AbstractPixelPaintOperation
    local instance = self:create_instance(coordinate)

    --- The pixel coordinate within the painter's canvas for this paint operation.<br/>
    --- One texel coordinate is 2 pixels wide by 3 pixels tall.
    instance.coordinate = coordinate

    return instance
end

--- @class DrawBoxPixelPaintOperationDefinition : AbstractPixelPaintOperationDefinition
--- @field base AbstractPixelPaintOperationDefinition
--- @field class DrawBoxPixelPaintOperationDefinition
local DrawBoxPixelPaintOperation = class.class("DrawBoxPixelPaintOperation", AbstractPixelPaintOperation)

--- [override] Creates a new <code>DrawBoxPixelPaintOperation</code> instance with the given parameters
--- @param area CanvasArea|RecallCallback  The bounds of the box to draw on the painter's canvas
--- @return DrawBoxPixelPaintOperation
function DrawBoxPixelPaintOperation:new(area)
    --- @class DrawBoxPixelPaintOperation : AbstractPixelPaintOperation
    --- @field base AbstractPixelPaintOperation
    --- @field class DrawBoxPixelPaintOperationDefinition
    --- @field this DrawBoxPixelPaintOperation
    local instance = self:create_instance({ x = area.x, y = area.y })
    -- AbstractPixelPaintOperation:new(coordinate)

    instance.area = area

    function instance:execute(painter)
        local painter_params = painter.params

        local area = __extract(self.area) --[[@as CanvasArea]]

        if area.width < 0 then area.width = painter.canvas.pixel_width + area.width + 1 end
        if area.height < 0 then area.height = painter.canvas.pixel_height + area.height + 1 end

        local left = area.x
        local right = area.x + area.width - 1
        local top = area.y
        local bottom = area.y + area.height - 1

        local iter_x, iter_y = left, top
        local iter_color = painter_params.color.fg
        local iter_state = 1

        --- @type PixelCanvasIterationFunction[]
        local iter_funcs =
        {
            function()
                -- Top-left corner
                iter_state = iter_state + 1
                return iter_x, iter_y, iter_color, true
            end,
            function()
                -- Top-left corner to top-right corner
                iter_x = iter_x + 1
                if iter_x >= right then
                    iter_x = right
                    iter_state = iter_state + 1
                end
                return iter_x, iter_y, iter_color, true
            end,
            function()
                -- Top-right corner to bottom-right corner
                iter_y = iter_y + 1
                if iter_y >= bottom then
                    iter_y = bottom
                    iter_state = iter_state + 1
                end
                return iter_x, iter_y, iter_color, true
            end,
            function()
                -- Bottom-right corner to bottom-left corner
                iter_x = iter_x - 1
                if iter_x <= left then
                    iter_x = left
                    iter_state = iter_state + 1
                end
                return iter_x, iter_y, iter_color, true
            end,
            function()
                -- Bottom-left corner to top-left corner
                iter_y = iter_y - 1
                if iter_y <= top then
                    iter_y = top
                    iter_state = iter_state + 1
                end
                return iter_x, iter_y, iter_color, true
            end
        }

        painter.canvas:set_pixel_many(
            function()
                if iter_state > #iter_funcs then return nil end
                return iter_funcs[iter_state]()
            end
        )
    end

    return instance
end

--- @class DrawLinePixelPaintOperationDefinition : AbstractPixelPaintOperationDefinition
--- @field base AbstractPixelPaintOperationDefinition
--- @field class DrawLinePixelPaintOperationDefinition
local DrawLinePixelPaintOperation = class.class("DrawLinePixelPaintOperation", AbstractPixelPaintOperation)

--- [override] Creates a new <code>DrawLinePixelPaintOperation</code> instance with the given parameters
--- @param coord_start CanvasPixelCoordinate|RecallCallback  The starting pixel coordinate within the painter's canvas for the line to draw.<br/>One texel coordinate is 2 pixels wide by 3 pixels tall.
--- @param coord_end CanvasPixelCoordinate|RecallCallback  The ending pixel coordinate within the painter's canvas for the line to draw.<br/>One texel coordinate is 2 pixels wide by 3 pixels tall.
--- @return DrawLinePixelPaintOperation
function DrawLinePixelPaintOperation:new(coord_start, coord_end)
    --- @class DrawLinePixelPaintOperation : AbstractPixelPaintOperation
    --- @field base AbstractPixelPaintOperation
    --- @field class DrawLinePixelPaintOperationDefinition
    --- @field this DrawLinePixelPaintOperation
    local instance = self:create_instance(coord_start, coord_end)
    -- AbstractPixelPaintOperation:new(coordinate)

    instance.coord_start = coord_start
    instance.coord_end = coord_end

    function instance:execute(painter)
        local painter_params = painter.params

        local start = __extract(self.coord_start) --[[@as CanvasPixelCoordinate]]
        local stop = __extract(self.coord_end) --[[@as CanvasPixelCoordinate]]

        local rise = stop.y - start.y
        local run = stop.x - start.x

        if rise == 0 and run == 0 then
            -- Single pixel line, just set the one pixel and return
            painter.canvas:set_pixel(start.x, start.y, painter_params.color.fg, true)
            return
        end

        --- @type number, number
        local iter_x, iter_y = start.x, start.y
        local stop_x, stop_y = stop.x, stop.y
        local iter_color = painter_params.color.fg

        local func_keep_drawing
        local func_step
        if run == 0 then
            -- Vertical line
            local direction
            if rise > 0 then
                func_keep_drawing = function() return iter_y <= stop_y end
                direction = 1
            else
                func_keep_drawing = function() return iter_y >= stop_y end
                direction = -1
            end
            func_step = function() iter_y = iter_y + direction end
        elseif rise == 0 then
            -- Horizontal line
            local direction
            if run > 0 then
                func_keep_drawing = function() return iter_x <= stop_x end
                direction = 1
            else
                func_keep_drawing = function() return iter_x >= stop_x end
                direction = -1
            end
            func_step = function() iter_x = iter_x + direction end
        else
            -- Sloped line
            if run >= 0 then
                func_keep_drawing = rise >= 0
                    and function() return R_math.integer(iter_x) <= stop_x and R_math.integer(iter_y) <= stop_y end
                    or function() return R_math.integer(iter_x) <= stop_x and R_math.integer(iter_y) >= stop_y end
            else
                func_keep_drawing = rise >= 0
                    and function() return R_math.integer(iter_x) >= stop_x and R_math.integer(iter_y) <= stop_y end
                    or function() return R_math.integer(iter_x) >= stop_x and R_math.integer(iter_y) >= stop_y end
            end

            if native.math.abs(run) >= native.math.abs(rise) then
                -- Shallow slope, step in X direction by integer and in Y direction by slope
                local direction = run > 0 and 1 or -1
                local slope = rise / run
                func_step = function()
                    iter_x = iter_x + direction
                    iter_y = iter_y + slope * direction
                end
            else
                -- Steep slope, step in Y direction by integer and in X direction by inverse of slope
                local direction = rise > 0 and 1 or -1
                local slope = run / rise
                func_step = function()
                    iter_x = iter_x + slope * direction
                    iter_y = iter_y + direction
                end
            end
        end

        painter.canvas:set_pixel_many(
            function()
                if not func_keep_drawing() then return nil end

                -- The returned values are for the current pixel, so they need to be stored before getting the next step
                local pixel_x, pixel_y = R_math.integer(iter_x), R_math.integer(iter_y)
                func_step()
                return pixel_x, pixel_y, iter_color, true
            end
        )
    end

    return instance
end

--- @class FillAreaPixelPaintOperationDefinition : AbstractPixelPaintOperationDefinition
--- @field base AbstractPixelPaintOperationDefinition
--- @field class FillAreaPixelPaintOperationDefinition
local FillAreaPixelPaintOperation = class.class("FillAreaPixelPaintOperation", AbstractPixelPaintOperation)

--- [override] Creates a new <code>FillAreaPixelPaintOperation</code> instance with the given parameters
--- @param area CanvasArea|RecallCallback  The bounds of the area to fill on the painter's canvas
--- @param background (boolean|RecallCallback)?  If <code>true</code>, the area's background color will be updated and the pixels are deactivated; otherwise, the foreground color will be updated and the pixels are activated
--- @return FillAreaPixelPaintOperation
function FillAreaPixelPaintOperation:new(area, background)
    --- @class FillAreaPixelPaintOperation : AbstractPixelPaintOperation
    --- @field base AbstractPixelPaintOperation
    --- @field class FillAreaPixelPaintOperationDefinition
    --- @field this FillAreaPixelPaintOperation
    local instance = self:create_instance({ x = area.x, y = area.y })
    -- AbstractPixelPaintOperation:new(coordinate)

    instance.area = area
    instance.background = background

    function instance:execute(painter)
        local painter_params = painter.params
        local painter_canvas = painter.canvas

        local area = __extract(self.area) --[[@as CanvasArea]]
        local background = __extract(self.background) --[[@as boolean]]

        local left, top, right, bottom = __resolve_area_bounds(area)

        -- Skip the calculations if the size of the area is "negative"
        if left > right or top > bottom then return end

        --[[

        Attempt to optimize by setting full texels where possible.
        Texel filling requires the full texel, so the "borders" of the area must entirely encompass the inner texels.

        X % 2 == 1:

              |- -- |    width >= 5
              PP PP P.
              PP PP P.
              PP PP P.

        X % 2 == 0:

               | -- |    width >= 4
              .P PP P.
              .P PP P.
              .P PP P.

        Y % 3 == 1:

            --- PP       height >= 7
             |  PP
             |  PP
              
             |  PP
             |  PP
             |  PP

            --- PP
                ..
                ..

        Y % 3 == 2:

                ..       height >= 6
            --- PP
             |  PP

             |  PP
             |  PP
             |  PP

            --- PP
                ..
                ..

        Y % 3 == 0:

                ..       height >= 5
                ..
            --- PP

             |  PP
             |  PP
             |  PP

            --- PP
                ..
                ..

        These measurements can be generalized via:

          width >= 5 - ((x - 1) % 2)
          height >= 7 - ((y - 1) % 3)

        --]]

        local width = right - left + 1
        local height = bottom - top + 1

        local new_group = painter_canvas:try_begin_update_group()

        if width >= 5 - ((left - 1) % 2) and height >= 7 - ((top - 1) % 3) then
            local start_texel_x, start_texel_y = canvas.pixel_to_texel(left, top)
            local stop_texel_x, stop_texel_y = canvas.pixel_to_texel(right, bottom)

            local color = (background ~= true and painter_params.color.fg or painter_params.color.bg) or "-"
            local active_bits = background ~= true and canvas.consts.MAX_TEXEL_STATE or canvas.consts.MIN_TEXEL_STATE

            for texel_y = start_texel_y + 1, stop_texel_y - 1 do
                for texel_x = start_texel_x + 1, stop_texel_x - 1 do
                    painter_canvas:set_texel_color(texel_x, texel_y, color, background)
                    painter_canvas:set_pixel_state_texel(texel_x, texel_y, active_bits)
                end
            end
        end

        -- Finally, update the pixels along the border's texels
        -- Pixel updates are grouped in the order of: top corners/edge, left edge, right edge then bottom corners/edge

        local pixel_active = background ~= true
        local iter_color = background == true and painter_params.color.bg or painter_params.color.fg

        --- @param l integer
        --- @param t integer
        --- @param r integer
        --- @param b integer
        local function __fill_pixels(l, t, r, b)
            local iter_x, iter_y = l, t
            painter_canvas:set_pixel_many(
                function()
                    if iter_y > b then return nil end

                    local pixel_x, pixel_y = iter_x, iter_y

                    iter_x = iter_x + 1

                    if iter_x > r then
                        iter_x = l
                        iter_y = iter_y + 1
                    end

                    return pixel_x, pixel_y, iter_color, pixel_active
                end
            )
        end

        local right_of_left, bottom_of_top = canvas.pixel_to_texel(left, top)
        right_of_left = right_of_left * 2
        bottom_of_top = bottom_of_top * 3

        local left_of_right, top_of_bottom = canvas.pixel_to_texel(right, bottom)

        -- Top corners and edge
        __fill_pixels(left, right, top, bottom_of_top)
        -- Left edge
        __fill_pixels(left, right_of_left, bottom_of_top + 1, top_of_bottom - 1)
        -- Right edge
        __fill_pixels(left_of_right, right, bottom_of_top + 1, top_of_bottom - 1)
        -- Bottom corners and edge
        __fill_pixels(left, right, top_of_bottom, bottom)

        if new_group then
            painter_canvas:end_update_group()
        end
    end

    return instance
end

--- @class PointPixelPaintOperationDefinition : AbstractPixelPaintOperationDefinition
--- @field base AbstractPixelPaintOperationDefinition
--- @field class PointPixelPaintOperationDefinition
local PointPixelPaintOperation = class.class("PointPixelPaintOperation", AbstractPixelPaintOperation)

--- [override] Creates a new <code>PointPixelPaintOperation</code> instance with the given parameters
--- @param coordinate CanvasPixelCoordinate|RecallCallback  The pixel coordinate within the painter's canvas for the point to draw.<br/>One texel coordinate is 2 pixels wide by 3 pixels tall.
--- @param active boolean|RecallCallback  Whether the pixel should be activated<br/>Activated pixels are drawn in the painter's current foreground color, while deactivated pixels are drawn in the painter's current background color
--- @return PointPixelPaintOperation
function PointPixelPaintOperation:new(coordinate, active)
    --- @class PointPixelPaintOperation : AbstractPixelPaintOperation
    --- @field base AbstractPixelPaintOperation
    --- @field class PointPixelPaintOperationDefinition
    --- @field this PointPixelPaintOperation
    local instance = self:create_instance(coordinate)

    instance.active = active

    function instance:execute(painter)
        local painter_params = painter.params

        local coordinate = __extract(self.coordinate) --[[@as CanvasPixelCoordinate]]
        local active = __extract(self.active) --[[@as boolean]]

        painter.canvas:set_pixel(coordinate.x, coordinate.y, active and painter_params.color.fg or painter_params.color.bg, active)
    end

    return instance
end

--- @class GroupPixelPaintOperationDefinition : AbstractPaintOperationDefinition
--- @field base AbstractPaintOperationDefinition
--- @field class GroupPixelPaintOperationDefinition
local GroupPixelPaintOperation = class.class("GroupPixelPaintOperation", AbstractPaintOperation)

--- [override] Creates a new <code>GroupPixelPaintOperation</code> instance with the given parameters
--- @param begin boolean  If <code>true</code>, a new batch of pixel painting operations will start; otherwise, the current batch will end
--- @return GroupPixelPaintOperation
function GroupPixelPaintOperation:new(begin)
    --- @class GroupPixelPaintOperation : AbstractPaintOperation
    --- @field base AbstractPaintOperation
    local instance = self:create_instance(begin)

    instance.begin = begin

    function instance:execute(painter)
        if self.begin then
            painter.canvas:begin_update_group()
        else
            painter.canvas:end_update_group()
        end
    end

    return instance
end

--- @class DeferredPixelPainterDefinition : ClassDefinition
--- @field base nil
--- @field class DeferredPixelPainterDefinition
local DeferredPixelPainter = class.class("DeferredPixelPainter")

--- [override] Creates a new <code>DeferredPixelPainter</code> instance
--- @param w integer  The width of the painter's canvas
--- @param h integer  The height of the painter's canvas
--- @param canvas_fg number?  The initial foreground color for the painter's canvas (see: <code>colors</code>), or <code>nil</code> to defer to the terminal's foreground color when painting
--- @param canvas_bg number?  The initial background color for the painter's canvas (see: <code>colors</code>), or <code>nil</code> to defer to the terminal's background color when painting
--- @param brush_fg number?  The initial foreground color for the painter's brush (see: <code>colors</code>).<br/>Defaults to <code>colors.white</code> if <code>nil</code>.
--- @param brush_bg number?  The initial background color for the painter's brush (see: <code>colors</code>).<br/>Defaults to <code>colors.black</code> if <code>nil</code>.
--- @param transparent boolean?  If <code>true</code>, the painter's canvas will initially be transparent; otherwise, the canvas will initially be filled with the default foreground and background colors.
--- @return DeferredPixelPainter
function DeferredPixelPainter:new(w, h, canvas_fg, canvas_bg, brush_fg, brush_bg, transparent)
    --- @class DeferredPixelPainter : ClassInstance
    --- @field base nil
    --- @field class DeferredPixelPainterDefinition
    --- @field this DeferredPixelPainter
    local instance = self:create_instance(w, h, canvas_fg, canvas_bg, brush_fg, brush_bg, transparent)

    --- A virtual canvas for storing the results from painting operations
    instance.canvas = canvas.class.PixelCanvas:new(w, h, canvas_fg, canvas_bg, transparent)

    --- @private
    instance.cache = {
        --- @type number
        brush_fg = brush_fg or colors.white,
        --- @type number
        brush_bg = brush_bg or colors.black,
        --- @type boolean
        transparent = transparent == true
    }

    --- Controls related to where and what is painted on the canvas
    instance.params = {
        --- @type CanvasCoordinate  The current working texel cursor position of the painter's brush
        cursor = {
            x = 1,
            y = 1
        },
        --- @type CanvasCoordinate  The location of the painter within the terminal
        origin = {
            x = 1,
            y = 1
        },
        --- @type { fg: number?, bg: number? }  The current colors of the painter's brush
        color = {
            fg = brush_fg or colors.white,
            bg = brush_bg or colors.black
        }
    }

    --- @private
    instance.work = {
        --- @type AbstractPaintOperation[]  The list of paint operations to execute when the painter is painted
        list = {},
        --- @type integer  The index of the last executed paint operation in the work list
        index = 0
    }

    --- @private
    --- @type table<string, any>  A table for storing any additional data related to the painter that paint operations may need to access
    instance.data = {}

    --- @private
    --- Adds the given operation to the work list
    --- @param operation AbstractPaintOperation  The painting operation
    --- @return DeferredPixelPainter
    function instance:__register_operation(operation)
        table.insert(self.work.list, operation)
        return self
    end

    --- Paints a hollow box on the painter's canvas, using the painter's current foreground color for the box's color
    --- @param area CanvasArea|RecallCallback  The bounds of the box to draw on the painter's canvas
    --- @return DeferredPixelPainter
    function instance:box(area)
        return self:__register_operation(DrawBoxPixelPaintOperation:new(area))
    end

    --- Erases the specified number of texels on the painter's canvas starting from the current position<br/>
    --- Unlike <code>erase()</code>, this method draws space characters to erase the texels instead of making them transparent
    --- @param params TexelEraseParameters|RecallCallback  The parameters for erasing texels on the painter's canvas
    --- @return DeferredPixelPainter
    function instance:clear(params)
        return self:__register_operation(EraseTexelsPaintOperation:new(params))
    end

    --- Sets the current colors for the painter's brush, which will be used for subsequent paint operations
    --- @param fg number|RecallCallback|"reset"?  The color to set the foreground to (see: <code>colors</code>).<br/>If <code>"reset"</code>, the foreground color will be reset to the original color before painting began.<br/>If <code>nil</code>, the foreground color will be left unchanged.
    --- @param bg number|RecallCallback|"reset"?  The color to set the background to (see: <code>colors</code>).<br/>If <code>"reset"</code>, the background color will be reset to the original color before painting began.<br/>If <code>nil</code>, the background color will be left unchanged.
    --- @return DeferredPixelPainter
    function instance:color(fg, bg)
        return self:__register_operation(ColorChangePaintOperation:new(fg, bg))
    end

    --- Stops the current batch of pixel painting operations
    --- @return DeferredPixelPainter
    function instance:end_group()
        return self:__register_operation(GroupPixelPaintOperation:new(false))
    end

    --- Erases the specified number of texels on the painter's canvas starting from the current position<br/>
    --- When texels are erased, they no longer update the underlying terminal when painted, effectively creating a "transparent" texel
    --- @param params TexelEraseParameters|RecallCallback  The parameters for erasing texels on the painter's canvas
    --- @return DeferredPixelPainter
    function instance:erase(params)
        return self:__register_operation(ErasePaintOperation:new(params))
    end

    --- Fills a region of pixels on the painter's canvas, using the painter's current colors
    --- @param area CanvasArea|RecallCallback  The bounds of the area to fill on the painter's canvas
    --- @param background (boolean|RecallCallback)?  If <code>true</code>, pixels within the given area will be deactivated and display the background color; otherwise, they will be activated and display the foreground color
    --- @return DeferredPixelPainter
    function instance:fill(area, background)
        return self:__register_operation(FillAreaPixelPaintOperation:new(area, background))
    end

    --- Starts a new batch of pixel painting operations<br/>
    --- While a batch is active, any pixel operations will have their results delayed to when the group ends
    --- @return DeferredPixelPainter
    function instance:group()
        return self:__register_operation(GroupPixelPaintOperation:new(true))
    end

    --- Paints a line on the painter's canvas, using the painter's current foreground color for the line's color
    --- @param coord_start CanvasPixelCoordinate|RecallCallback  The starting pixel coordinate within the painter's canvas for the line to draw.<br/>One texel coordinate is 2 pixels wide by 3 pixels tall.
    --- @param coord_end CanvasPixelCoordinate|RecallCallback  The ending pixel coordinate within the painter's canvas for the line to draw.<br/>One texel coordinate is 2 pixels wide by 3 pixels tall.
    --- @return DeferredPixelPainter
    function instance:line(coord_start, coord_end)
        return self:__register_operation(DrawLinePixelPaintOperation:new(coord_start, coord_end))
    end

    --- Sets the texel location of the painter's brush within its canvas
    --- @param coordinate (CanvasCoordinateAdjustment|RecallCallback)  The texel coordinate to move the brush to.<br/>If a coordinate is negative, it is interpreted as a coordinate from the right or bottom edges of the canvas.<br/>For example, <code>{ x = -1, y = -1 }</code> would move the brush to the bottom right corner of the canvas.
    --- @return DeferredPixelPainter
    function instance:move(coordinate)
        return self:__register_operation(MovePaintOperation:new(coordinate, false))
    end

    --- Paints the string representation of the given object onto the painter's canvas
    --- @param obj any  The object to paint, or a RecallCallback that returns the object to paint
    --- @param params PainterFunctionTextParams?  Optional parameters for how the text should be painted
    --- @return DeferredPixelPainter
    function instance:obj(obj, params)
        return self:__register_operation(ObjectToStringPaintOperation:new(obj, params))
    end

    --- Offsets the painter's brush by the given coordinate
    --- @param coordinate (CanvasCoordinateAdjustment|RecallCallback)  How far to offset the brush by
    --- @return DeferredPixelPainter
    function instance:offset(coordinate)
        return self:__register_operation(MovePaintOperation:new(coordinate, true))
    end

    --- Paints the current state of the painter's canvas to the terminal, applying any pending paint operations in the process
    --- @param terminal table  The terminal to paint to
    function instance:paint(terminal)
        local tbl_work = self.work

        if tbl_work.index < #tbl_work.list then
            if tbl_work.index == 0 then
                -- If no work has been done yet, clear the canvas before starting to paint
                self.canvas:clear(self.cache.transparent)
            end

            for i = tbl_work.index + 1, #tbl_work.list do
                local work = tbl_work.list[i]
                if work then work.this:execute(self) end
            end

            tbl_work.index = #tbl_work.list
        end

        local origin = self.params.origin
        terminal.setCursorPos(origin.x, origin.y)
        self.canvas:push(terminal)
    end

    --- Paints a single pixel on the painter's canvas, using the painter's current colors
    --- @param coordinate CanvasPixelCoordinate|RecallCallback  The pixel coordinate within the painter's canvas
    --- @param active boolean|RecallCallback  Whether the pixel should be activated<br/>Activated pixels are drawn in the painter's current foreground color, while deactivated pixels are drawn in the painter's current background color
    --- @return DeferredPixelPainter
    function instance:point(coordinate, active)
        return self:__register_operation(PointPixelPaintOperation:new(coordinate, active))
    end

    --- Retrieves a value from the painter's data cache, or <code>nil</code> if no value is stored under the given key
    --- @param key string  The key to look up in the data cache
    --- @return RecallCallback callback  A table containing a function representing the value access
    function instance:recall(key)
        return {
            __recall_callback = function() return self.data[key] end
        }
    end

    --- Resets the painter's canvas and brush to their initial states, then applies all painting operations again before painting the canvas to the terminal
    --- @param terminal table  The terminal to paint to
    function instance:repaint(terminal)
        local params = self.params
        local cursor = params.cursor
        cursor.x = 1
        cursor.y = 1

        local cache = self.cache

        local color = params.color
        color.fg = cache.brush_fg
        color.bg = cache.brush_bg

        self.work.index = 0
        self:paint(terminal)
    end

    --- Sets the origin point for the painter, which is the coordinate within the terminal that corresponds to (1, 1) on the painter's canvas<br/>
    --- <b>Calling this function does not clear where the canvas was previously painted!</b>
    --- @param x integer  The horizontal texel coordinate of the origin point within the terminal
    --- @param y integer  The vertical texel coordinate of the origin point within the terminal
    function instance:set_origin(x, y)
        local origin = self.params.origin
        origin.x = x
        origin.y = y
    end

    --- Sets a value in the painter's data cache<br/>
    --- The value can be accessed later using <code>recall()</code> with the same key
    --- @param key string  The key to store the value under
    --- @param value any  The value to store
    --- @return DeferredPixelPainter
    function instance:store(key, value)
        self.data[key] = value
        return self
    end

    --- Swaps the foreground and background colors of the painter's brush
    --- @return DeferredPixelPainter
    function instance:swap()
        return self:__register_operation(ColorSwapPaintOperation:new())
    end

    --- Paints the given text onto the painter's canvas
    --- @param text string|RecallCallback  The text to paint
    --- @param params PainterFunctionTextParams?  Optional parameters for how the text should be painted
    --- @return DeferredPixelPainter
    function instance:text(text, params)
        return self:__register_operation(TextPaintOperation:new(text, params))
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
    --- The classes defined by this module
    class = {
        --- A class representing abstraction over positioning and writing text to a terminal
        Painter = Painter,
        --- A class representing delayed painting operations that can be executed at a later time.<br/>
        --- Unlike Painter, this class can update individual pixels.<br/>
        --- Supports storing and recalling values based on string keys.
        DeferredPixelPainter = DeferredPixelPainter
    },
    --- @type PaintBlockCharacters
    --- A list of characters that render as blocks in a 2x3 grid, indexed by descriptive names of which parts of the grid they fill.<br/>
    --- HIGH refers to the topmost row, MIDDLE refers to the middle row, and LOW refers to the bottom row.<br/>LEFT and RIGHT refer to the respective columns.<br/>
    --- In the field descriptions, "x" represents the foreground color and "-" represents the background color.
    blocks = block_chars,
    --- @type PaintBlockCharactersNegated
    --- A list of characters that render as blocks in a 2x3 grid, indexed by descriptive names of which parts of the grid they leave unfilled.<br/>
    --- HIGH refers to the topmost row, MIDDLE refers to the middle row, and LOW refers to the bottom row.<br/>LEFT and RIGHT refer to the respective columns.<br/>
    --- In the field descriptions, "x" represents the background color and "-" represents the foreground color.
    --- ```lua
    --- local paint = require "lib.dr.paint"
    --- ...
    --- local painter = paint.class.Painter:new(term.current())
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