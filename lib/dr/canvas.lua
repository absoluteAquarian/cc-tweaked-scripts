local class = require "lib.class"
local R_string = require "lib.string"
local R_table = require "lib.table"

local native = {
    bit32 = {
        btest = bit32.btest,
        bxor = bit32.bxor,
        lshift = bit32.lshift
    },
    colors = {
        --- @type fun(color: number) : string
        toBlit = colors.toBlit,
        --- @type fun(blit: string) : number
        fromBlit = colors.fromBlit
    },
    math = {
        ceil = math.ceil,
        floor = math.floor,
        max = math.max,
        min = math.min
    },
    table = {
        concat = table.concat
    },
    string = {
        byte = string.byte,
        char = string.char,
        gsub = string.gsub,
        sub = string.sub,
        reverse = string.reverse
    }
}

--- @class TexelCanvasDefinition : ClassDefinition
--- @field base nil
--- @field class TexelCanvasDefinition
local TexelCanvas = class.class("TexelCanvas")

--- [override] Creates a new <code>Canvas</code> instance with the given parameters
--- @param width integer  The width of the canvas
--- @param height integer  The height of the canvas
--- @param fg number?  The initial foreground color for the canvas, or <code>nil</code> to defer to the terminal's foreground color when painting
--- @param bg number?  The initial background color for the canvas, or <code>nil</code> to defer to the terminal's background color when painting
--- @param transparent boolean?  If <code>true</code>, the canvas will initially be transparent; otherwise, the canvas will initially be filled with the default foreground and background colors.
--- @return TexelCanvas
function TexelCanvas:new(width, height, fg, bg, transparent)
    --- @class TexelCanvas : ClassInstance
    --- @field base nil
    --- @field class TexelCanvasDefinition
    --- @field this TexelCanvas
    local instance = self:create_instance(width, height)

    --- How many columns of texels exist on the canvas
    instance.texel_width = width
    instance:mark_readonly("texel_width")
    --- How many rows of texels exist on the canvas
    instance.texel_height = height
    instance:mark_readonly("texel_height")
    --- The default foreground color for the canvas, or <code>nil</code> to defer to the terminal's foreground color when painting
    instance.fg = fg
    instance:mark_readonly("fg")
    --- The default background color for the canvas, or <code>nil</code> to defer to the terminal's background color when painting
    instance.bg = bg
    instance:mark_readonly("bg")
    local fg_blit = fg and colors.toBlit(fg) or "-"
    --- @private
    --- @type string  The blit character to use for the default foreground color
    instance.fg_blit = fg_blit
    instance:mark_readonly("fg_blit")
    local bg_blit = bg and colors.toBlit(bg) or "-"
    --- @private
    --- @type string  The blit character to use for the default background color
    instance.bg_blit = bg_blit
    instance:mark_readonly("bg_blit")

    --- @private
    --- The rows of strings used to display the text
    instance.blit = {
        --- The text to display
        text = R_table.create_2d(width, height, function() return " " end),
        --- The blit string for the foreground colors
        fg = R_table.create_2d(width, height, function() return fg_blit end),
        --- The blit string for the background colors
        bg = R_table.create_2d(width, height, function() return bg_blit end),
        dirty = {
            text = R_table.create(height, function() return true end),
            fg = R_table.create(height, function() return true end),
            bg = R_table.create(height, function() return true end)
        },
        cache = {
            --- @type number?
            terminal_fg = nil,
            --- @type number?
            terminal_bg = nil,
            --- @type string[]
            blitted_text = {},
            --- @type string[]
            blitted_fg = {},
            --- @type string[]
            blitted_bg = {}
        }
    }

    local hide = transparent == true
    local hidden_count = hide and width or 0

    --- @private
    instance.pass = {
        count = R_table.create(height, function() return hidden_count end),
        flags = R_table.create_2d(width, height, function() return hide end)
    }

    --- @protected
    --- Marks the texel at the specified texel row as dirty<br/>
    --- When a texel is marked dirty, the canvas's internal cache will be updated when it is drawn next
    --- @param y integer  The vertical texel row
    function instance:mark_dirty_text(y)
        if not self:contains_texel(1, y) then
            error(string.format("Texel row %d is out of bounds", y), 2)
        end

        -- contains() already verifies the coordinates

        self.blit.dirty.text[y] = true
    end

    --- @protected
    --- Marks the texel's foreground color at the specified texel row as dirty<br/>
    --- When a texel is marked dirty, the canvas's internal cache will be updated when it is drawn next
    --- @param y integer  The vertical texel row
    function instance:mark_dirty_foreground(y)
        if not self:contains_texel(1, y) then
            error(string.format("Texel row %d is out of bounds", y), 2)
        end

        -- contains() already verifies the coordinates

        self.blit.dirty.fg[y] = true
    end

    --- @protected
    --- Marks the texel's background color at the specified texel row as dirty<br/>
    --- When a texel is marked dirty, the canvas's internal cache will be updated when it is drawn next
    --- @param y integer  The vertical texel row
    function instance:mark_dirty_background(y)
        if not self:contains_texel(1, y) then
            error(string.format("Texel row %d is out of bounds", y), 2)
        end

        -- contains() already verifies the coordinates

        self.blit.dirty.bg[y] = true
    end

    --- @protected
    --- @param coord any
    --- @param var_name string
    function instance.verify_integer_coordinate(coord, var_name)
        if type(coord) ~= "number" then
            error(string.format("Expected variable '%s' to be an integer, got %s", var_name, type(coord)), 3)
        end
        if coord % 1 ~= 0 then
            error(string.format("Expected variable '%s' to be an integer, got a floating-point number", var_name), 3)
        end
    end

    --- @protected
    --- Gets whether the specified texel is hidden<br/>
    --- Hidden texels do not update the underlying terminal's character nor color at their position
    --- @param x integer  The horizontal texel coordinate
    --- @param y integer  The vertical texel coordinate
    --- @return boolean
    function instance:hidden(x, y)
        if not self:contains_texel(x, y) then return true end

        -- contains() already verifies the coordinates

        return self.pass.flags[y][x]
    end

    --- Clears the canvas
    --- @param transparent boolean?  If <code>true</code>, the canvas will be cleared to a transparent state; otherwise, the canvas will be cleared to the default foreground and background colors
    function instance:clear(transparent)
        local tbl_blit = self.blit
        local tbl_pass = self.pass
        local self_width = self.texel_width

        if transparent then
            for y = 1, self.texel_height do
                local row = tbl_pass.flags[y]

                for x = 1, self_width do
                    row[x] = true
                end

                tbl_pass.count[y] = self_width
            end
        else
            local fg_blit = self.fg_blit
            local bg_blit = self.bg_blit

            for y = 1, self.texel_height do
                local row_text = tbl_blit.text[y]
                local row_fg = tbl_blit.fg[y]
                local row_bg = tbl_blit.bg[y]
                local row_flags = tbl_pass.flags[y]

                for x = 1, self_width do
                    row_text[x] = " "
                    row_fg[x] = fg_blit
                    row_bg[x] = bg_blit
                    row_flags[x] = false
                end

                tbl_pass.count[y] = 0

                local tbl_dirty = tbl_blit.dirty
                tbl_dirty.text[y] = true
                tbl_dirty.fg[y] = true
                tbl_dirty.bg[y] = true
            end
        end
    end

    --- Returns whether the specified texel coordinates are within the bounds of the canvas
    --- @param x integer  The x-coordinate
    --- @param y integer  The y-coordinate
    --- @return boolean
    function instance:contains_texel(x, y)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        return x >= 1 and x <= self.texel_width and y >= 1 and y <= self.texel_height
    end

    --- @private
    --- @param x integer
    --- @param y integer
    --- @param value boolean
    function instance:updatePass(x, y, value)
        if not self:contains_texel(x, y) then
            error(string.format("Texel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        -- contains() already verifies the coordinates

        local tbl_pass = self.pass
        local row = tbl_pass.flags[y]

        local value_old = row[x]

        if value == value_old then return end

        row[x] = value

        local count = tbl_pass.count[y]
        tbl_pass.count[y] = native.math.max(0, native.math.min(self.texel_width, value and (count + 1) or (count - 1)))
    end

    --- @private
    --- @param x_start integer
    --- @param x_end integer
    --- @param y integer
    --- @param value boolean
    function instance:updatePassMany(x_start, x_end, y, value)
        self.verify_integer_coordinate(x_start, "x_start")
        self.verify_integer_coordinate(x_end, "x_end")
        self.verify_integer_coordinate(y, "y")

        if not self:contains_texel(x_start, y) then
            error(string.format("Start of texel range (%d, %d) is out of bounds", x_start, y), 2)
        end
        if not self:contains_texel(x_end, y) then
            error(string.format("End of texel range (%d, %d) is out of bounds", x_end, y), 2)
        end
        if x_start > x_end then
            error(string.format("Start of texel range (%d) cannot be greater than end of texel range (%d)", x_start, x_end), 2)
        end

        local tbl_pass = self.pass
        local row = tbl_pass.flags[y]
        local updated = 0

        for x = x_start, x_end do
            local old_value = row[x]
            row[x] = value

            if old_value ~= value then
                updated = updated + 1
            end
        end

        if updated > 0 then
            local count = tbl_pass.count[y]
            tbl_pass.count[y] = native.math.max(0, native.math.min(self.texel_width, value and (count + updated) or (count - updated)))
        end
    end

    --- Gets the text and colors for the specified texel on the canvas
    --- @param x integer  The horizontal texel coordinate
    --- @param y integer  The vertical texel coordinate
    --- @return string? char  The character at the specified texel, or <code>nil</code> if the texel is hidden
    --- @return number? fg  The foreground color at the specified texel, or <code>nil</code> if the texel is hidden
    --- @return number? bg  The background color at the specified texel, or <code>nil</code> if the texel is hidden
    function instance:get_texel(x, y)
        if not self:contains_texel(x, y) then
            return nil, nil, nil
        end

        -- contains() already verifies the coordinates

        if self.pass.flags[y][x] then
            return nil, nil, nil
        else
            local tbl_blit = self.blit
            return tbl_blit.text[y][x], native.colors.fromBlit(tbl_blit.fg[y][x]), native.colors.fromBlit(tbl_blit.bg[y][x])
        end
    end

    --- @param new_char string?
    --- @param x integer
    --- @param y integer
    --- @param target_table string[][]
    --- @param dirty_table boolean[]
    --- @param forced boolean
    local function try_update_text(new_char, x, y, target_table, dirty_table, forced)
        if new_char ~= nil then
            local row = target_table[y]
            local old_char = row[x]
            if forced or old_char ~= new_char then
                row[x] = new_char
                dirty_table[y] = true
            end
        end
    end

    --- @param color (number|string)?
    --- @return string?
    local function resolve_color(color)
        if color ~= nil then
            return type(color) == "number" and native.colors.toBlit(color--[[@as number]]) or color--[[@as string]]
        else
            return nil
        end
    end

    --- @param new_color (number|string)?
    --- @param x integer
    --- @param y integer
    --- @param target_table string[][]
    --- @param dirty_table boolean[]
    --- @param forced boolean
    local function try_update_color(new_color, x, y, target_table, dirty_table, forced)
        if new_color ~= nil then
            local row = target_table[y]
            local old_color = row[x]
            new_color = resolve_color(new_color)
            if forced or old_color ~= new_color then
                row[x] = new_color
                dirty_table[y] = true
            end
        end
    end

    --- @class TexelSetParameters
    --- @field fg (number|string)?  The foreground color, either as a <code>colors</code> value or <code>nil</code> to not update the color<br/>(use <code>"-"</code> to defer to the terminal's foreground color when painting)
    --- @field bg (number|string)?  The background color, either as a <code>colors</code> value or <code>nil</code> to not update the color<br/>(use <code>"-"</code> to defer to the terminal's background color when painting)
    --- @field forced boolean?  If <code>true</code>, a painted texel will force an update to the blit cache, even if its character and colors did not change.

    --- Paints the given character texel onto the canvas and forces it to be visible
    --- @param x integer  The horizontal texel coordinate
    --- @param y integer  The vertical texel coordinate
    --- @param char string  The texel to paint
    --- @param params TexelSetParameters  The parameters for painting the texel
    function instance:set_texel(x, y, char, params)
        if not self:contains_texel(x, y) then
            error(string.format("Texel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        -- contains() already verifies the coordinates

        local tbl_blit = self.blit
        local tbl_dirty = tbl_blit.dirty

        try_update_text(char, x, y, tbl_blit.text, tbl_dirty.text, params.forced)
        try_update_color(params.fg, x, y, tbl_blit.fg, tbl_dirty.fg, params.forced)
        try_update_color(params.bg, x, y, tbl_blit.bg, tbl_dirty.bg, params.forced)

        if params.forced then
            tbl_dirty.text[y] = true
            tbl_dirty.fg[y] = true
            tbl_dirty.bg[y] = true
        end

        self:updatePass(x, y, false)
    end

    --- Updates one of the colors for the given character texel
    --- @param x integer  The horizontal texel coordinate
    --- @param y integer  The vertical texel coordinate
    --- @param color number|string  The color to update as a <code>colors</code> value or <code>"-"</code> to defer to the terminal's color when painting
    --- @param background boolean  If <code>true</code>, the background color will be updated; otherwise, the foreground color will be updated
    function instance:set_texel_color(x, y, color, background)
        if not self:contains_texel(x, y) then
            error(string.format("Texel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        -- contains() already verifies the coordinates

        local tbl_blit = self.blit
        local tbl_dirty = tbl_blit.dirty

        if background then
            try_update_color(color, x, y, tbl_blit.bg, tbl_dirty.bg, false)
        else
            try_update_color(color, x, y, tbl_blit.fg, tbl_dirty.fg, false)
        end

        self:updatePass(x, y, false)
    end

    --- @class ManyTexelSetParameters : TexelSetParameters
    --- @field vertical boolean?  If <code>true</code>, painting will move vertically across the canvas; otherwise, painting will move horizontally across the canvas.
    --- @field tail_align boolean?  If <code>true</code>, the provided coordinate will be adjusted so that painting stops at the original coordinate; otherwise, painting will start at the original coordinate.
    --- @field reversed boolean?  If <code>true</code>, the provided text will be painted in reverse order; otherwise, it will be painted in the current order.
    --- @field count integer?  If not <code>nil</code> and greater than 1, the provided text will be painted the given number of times.<br/>For example, with <code>text = "abc"</code> and <code>repeat = 3</code>, the text <code>"abcabcabc"</code> would be painted.

    --- @protected
    --- @param x integer
    --- @param y integer
    --- @param text string
    --- @param params ManyTexelSetParameters
    --- @return integer start_x
    --- @return integer start_y
    --- @return string actual_text
    --- @return integer start_of_text
    --- @return integer end_of_text
    --- @return integer text_length
    function instance:__set_texel_many_resolve_parameters(x, y, text, params)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        if #text == 0 then
            return x, y, text, 1, 1, 0
        end

        local coordinate = params.vertical and y or x
        local dimension = params.vertical and self.texel_height or self.texel_width

        if coordinate + #text < 2 or coordinate > dimension then return x, y, text, 1, 1, 0 end

        local temp_text = text

        if params.reversed then
            temp_text = native.string.reverse(temp_text)
        end

        if params.count and params.count > 1 then
            temp_text = R_string.cached_rep(temp_text, params.count)
        end

        text = temp_text

        if params.tail_align then
            coordinate = coordinate - #text + 1
        end

        -- Adjust the input text

        local start, length = 1, nil
        if coordinate < 1 then
            -- Trim the start of input text
            start = 2 - coordinate
            length = native.math.min(#text - start + 1, dimension)
            coordinate = 1
        end

        if coordinate + #text > dimension then
            -- Trim the end of the input text
            length = dimension - coordinate + 1
        else
            -- The full input text is within bounds
            length = #text
        end

        if params.vertical then y = coordinate else x = coordinate end

        return x, y, text, start, start + length - 1, length
    end

    --- Paints the given texel sequence on the canvas and forces it to be visible
    --- @param x number  The horizontal texel coordinate of the start of the text
    --- @param y number  The vertical texel coordinate of the text
    --- @param text string  The texels to paint
    --- @param params ManyTexelSetParameters  The parameters for painting the text
    --- @return integer count  The number of texels that were painted
    --- @return integer end_x  The horizontal texel coordinate of the texel after the end of the painted text
    --- @return integer end_y  The vertical texel coordinate of the texel after the end of the painted text
    function instance:set_texel_many(x, y, text, params)
        if #text == 0 then return 0, x, y end

        local text_start, text_end, length
        x, y, text, text_start, text_end, length = self:__set_texel_many_resolve_parameters(x, y, text, params)

        if length <= 1 then
            self:set_texel(x, y, text, params)
            if params.vertical then return 1, x, y + 1 else return 1, x + 1, y end
        end

        if params.vertical then
            -- Intercept the parameters to make execution faster
            params.fg = resolve_color(params.fg)
            params.bg = resolve_color(params.bg)

            -- Characters have to be painted one-by-one
            for i = text_start, text_end do
                self:set_texel(x, y + i - text_start, native.string.sub(text, i, i), params)
            end

            return length, x, y + length
        else
            local tbl_blit = self.blit
            local line_text = tbl_blit.text[y]
            local line_fg = tbl_blit.fg[y]
            local line_bg = tbl_blit.bg[y]

            local fg = resolve_color(params.fg)
            local bg = resolve_color(params.bg)

            local tbl_dirty = tbl_blit.dirty

            local forced = params.forced

            -- Update each array with the new values
            for i = text_start, text_end do
                local index = x + i - text_start

                local old_text = line_text[index]
                local new_text = native.string.sub(text, i, i)

                if forced or old_text ~= new_text then
                    line_text[index] = new_text
                    tbl_dirty.text[y] = true
                end

                local old_fg = line_fg[index]
                if fg ~= nil and (forced or old_fg ~= fg) then
                    line_fg[index] = fg
                    tbl_dirty.fg[y] = true
                end

                local old_bg = line_bg[index]
                if bg ~= nil and (forced or old_bg ~= bg) then
                    line_bg[index] = bg
                    tbl_dirty.bg[y] = true
                end
            end

            if forced then
                tbl_dirty.text[y] = true
                tbl_dirty.fg[y] = true
                tbl_dirty.bg[y] = true
            end

            self:updatePassMany(x, x + length - 1, y, false)

            return length, x + length, y
        end
    end

    --- @class TexelEraseParameters
    --- @field vertical boolean?  If <code>true</code>, erasing will move vertically across the canvas; otherwise, erasing will move horizontally across the canvas.
    --- @field tail_align boolean?  If <code>true</code>, the provided coordinate will be adjusted so that erasing stops at the original coordinate; otherwise, erasing will start at the original coordinate.
    --- @field count integer?  If not <code>nil</code> and greater than 1, <code>count</code> consecutive texels will be erased.

    --- Sets the specified texel to be hidden<br/>
    --- Hidden texels do not update the underlying terminal's character nor color at their position
    --- @param x number  The horizontal texel coordinate
    --- @param y number  The vertical texel coordinate
    --- @param params TexelEraseParameters?  The parameters for the erasing operation.<br/>If <code>nil</code>, only the single specified texel will be erased.
    function instance:erase_texel(x, y, params)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        if not self:contains_texel(x, y) then
            error(string.format("Texel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        if params then
            local coordinate = params.vertical and y or x
            local dimension = params.vertical and self.texel_height or self.texel_width
            local count = params.count and params.count > 1 and params.count or 1

            if coordinate + count < 2 or coordinate > dimension then return end

            if params.tail_align then
                if params.vertical then
                    y = y - count + 1
                else
                    x = x - count + 1
                end
            end

            if params.vertical then
                for i = 1, count do
                    self:updatePass(x, y + i - 1, true)
                end
            else
                self:updatePassMany(x, x + count - 1, y, true)
            end
        else
            self:updatePass(x, y, true)
        end
    end

    --- Pushes the canvas to the specified terminal, drawing the canvas's text and colors to the terminal while respecting hidden texels
    --- @param terminal table  The terminal to write the canvas onto
    function instance:push(terminal)
        local tbl_blit = self.blit
        local tbl_cache = self.blit.cache
        local tbl_dirty = tbl_blit.dirty

        local terminal_fg = terminal.getTextColor()
        local forced_dirty_fg = tbl_cache.terminal_fg ~= terminal_fg
        local terminal_bg = terminal.getBackgroundColor()
        local forced_dirty_bg = tbl_cache.terminal_bg ~= terminal_bg

        local x_prev, y_prev = terminal.getCursorPos()
        local x, y = x_prev, y_prev

        for r = 1, self.texel_height do
            local pass = self.pass

            -- Preprocess any deferred colors
            if tbl_dirty.text[r] then
                tbl_dirty.text[r] = false
                tbl_cache.blitted_text[r] = native.table.concat(tbl_blit.text[r])
            end

            if forced_dirty_fg or tbl_dirty.fg[r] or (not tbl_cache.blitted_fg[r]) then
                tbl_dirty.fg[r] = false
                tbl_cache.terminal_fg = terminal_fg
                tbl_cache.blitted_fg[r] = native.string.gsub(native.table.concat(tbl_blit.fg[r]), "%-", native.colors.toBlit(terminal_fg))
            end

            if forced_dirty_bg or tbl_dirty.bg[r] or (not tbl_cache.blitted_bg[r]) then
                tbl_dirty.bg[r] = false
                tbl_cache.terminal_bg = terminal_bg
                tbl_cache.blitted_bg[r] = native.string.gsub(native.table.concat(tbl_blit.bg[r]), "%-", native.colors.toBlit(terminal_bg))
            end

            if pass.count[r] == 0 then
                -- No texels are hidden, push as-is
                terminal.blit(tbl_cache.blitted_text[r], tbl_cache.blitted_fg[r], tbl_cache.blitted_bg[r])
            elseif pass.count[r] < self.texel_width then
                -- Some texels are hidden; splice the blit strings to skip them
                local flags = pass.flags[r]
                local blit_start, blit_end = 1, 1

                local text = tbl_cache.blitted_text[r]
                local fg = tbl_cache.blitted_fg[r]
                local bg = tbl_cache.blitted_bg[r]

                for c = 1, self.texel_width do
                    if flags[c] then
                        -- Texel is hidden, push the blit text up to this point and skip the hidden texel
                        if blit_end < c then
                            terminal.setCursorPos(x + blit_start - 1, y)
                            terminal.blit(
                                native.string.sub(text, blit_start, blit_end),
                                native.string.sub(fg, blit_start, blit_end),
                                native.string.sub(bg, blit_start, blit_end)
                            )
                        end

                        blit_start, blit_end = c + 1, c + 1
                    else
                        -- Texel is not hidden, continue the blit text
                        blit_end = c
                    end
                end

                -- Push any remaining blit text after the last hidden texel
                if blit_end <= self.texel_width then
                    terminal.setCursorPos(x + blit_start - 1, y)
                    terminal.blit(
                        native.string.sub(text, blit_start, blit_end),
                        native.string.sub(fg, blit_start, blit_end),
                        native.string.sub(bg, blit_start, blit_end)
                    )
                end
            end

            -- Move the cursor to the next line for the next iteration
            y = y + 1
        end

        tbl_cache.terminal_fg = terminal_fg
        tbl_cache.terminal_bg = terminal_bg

        terminal.setCursorPos(x_prev, y_prev + self.texel_height)
        terminal.setTextColor(terminal_fg)
        terminal.setBackgroundColor(terminal_bg)
    end

    return instance
end

--[[

This will need some explanation.

First, characters 128 to 159 are rendered as blocks within a 2-wide by 3-tall grid of pixels, where a "filled" pixel uses the foreground color.
Looking at the binary and visual representations of the decimal value for each character shows the following:

  128 | 1000 0000 | B B
                  | B B
                  | B B
 -----------------------
  129 | 1000 0001 | F B
                  | B B
                  | B B
 -----------------------
  130 | 1000 0010 | B F
                  | B B
                  | B B
...
(To view all of the visual representations, check the blocks tables from "lib/dr/paint.lua".)

This indicates that (from left-to-right and top-to-bottom) pixel 0 = bit 0, pixel 1 = bit 1, and so forth.
Thus, each texel can be represented through 6 bits in a byte.
However, the character set stops early:

  159 | 1001 1111 | F F
                  | F F
                  | F B

Hence, some additional logic is needed for the rest of the possible pixels.
Fortunately, this can be resolved in a clever manner.
Consider the case where the foreground and background colors are swapped:

  159 | 1001 1111 | B B
                  | B B
                  | B F
 ------------------------
  158 | 1001 1110 | F B
                  | B B
                  | B F
 -----------------------
  157 | 1001 1101 | B F
                  | B B
                  | B F
...

This indicates that the rest of the possible pixels can be represented by swapping the colors and adjusting the bits as follows:

  char = (63 - bits) + 128

In total, given a byte storing whether each pixel should be "on", the character and colors can be retrieved via:

  if bits <= 31 then
    char = bits + 128
    fg = color_0
    bg = color_1
  else
    char = (63 - bits) + 128
    fg = color_1
    bg = color_0
  end

Lua doesn't have a "byte"-like type, but "integer" should be good enough.

--]]

--- @type table<number, string>
local __bits_to_char_lookup = {}
--- @type table<string|number, number>
local __char_to_bits_lookup = {}
for i = 0, 31 do
    local code = i + 128
    local char = native.string.char(code)
    __bits_to_char_lookup[i] = char
    __char_to_bits_lookup[char] = i
    __char_to_bits_lookup[code] = i
end
for i = 32, 63 do
    local code = (63 - i) + 128
    local char = native.string.char(code)
    __bits_to_char_lookup[i] = char
    __char_to_bits_lookup[char] = i
    __char_to_bits_lookup[code] = i
end

--- Converts pixel coordinates to the corresponding texel coordinates
--- @param x integer  The horizontal pixel coordinate
--- @param y integer  The vertical pixel coordinate
--- @return integer texel_x  The horizontal texel coordinate
--- @return integer texel_y  The vertical texel coordinate
local function pixel_to_texel(x, y)
    return native.math.floor((x + 1) / 2), native.math.floor((y + 2) / 3)
end

--- Converts texel coordinates to the corresponding pixel coordinates for the top-left pixel in the texel
--- @param x integer  The horizontal texel coordinate
--- @param y integer  The vertical texel coordinate
--- @return integer pixel_x  The horizontal pixel coordinate
--- @return integer pixel_y  The vertical pixel coordinate
local function texel_to_pixel(x, y)
    return x * 2 - 1, y * 3 - 2
end

local MIN_TEXEL_STATE = 0x00
local MAX_TEXEL_STATE = 0x3F
local INVALID_TEXEL_STATE = 0x40

--- @class PixelCanvasDefinition : TexelCanvasDefinition
--- @field base TexelCanvasDefinition
--- @field class PixelCanvasDefinition
local PixelCanvas = class.class("PixelCanvas", TexelCanvas)

--- [override] Creates a new <code>PixelCanvas</code> instance with the given parameters
--- @param width integer  The width of the canvas
--- @param height integer  The height of the canvas
--- @param fg number?  The initial foreground color for the canvas, or <code>nil</code> to defer to the terminal's foreground color when painting
--- @param bg number?  The initial background color for the canvas, or <code>nil</code> to defer to the terminal's background color when painting
--- @param transparent boolean?  If <code>true</code>, the canvas will initially be transparent; otherwise, the canvas will initially be filled with the default foreground and background colors.
--- @return PixelCanvas
function PixelCanvas:new(width, height, fg, bg, transparent)
    --- @class PixelCanvas : TexelCanvas
    --- @field base TexelCanvas
    --- @field class PixelCanvasDefinition
    --- @field this PixelCanvas
    local instance = self:create_instance(native.math.ceil(width / 2), native.math.ceil(height / 3), fg, bg, transparent)
    -- TexelCanvas:new(width, height, fg, bg, transparent)

    --- The width of the canvas in pixels.<br/>Not to be confused with <code>TexelCanvas.texel_width</code>
    instance.pixel_width = width
    instance:mark_readonly("pixel_width")
    --- The height of the canvas in pixels.<br/>Not to be confused with <code>TexelCanvas.texel_height</code>
    instance.pixel_height = height
    instance:mark_readonly("pixel_height")

    --- @private
    --- Information used to build the texels for the base class
    instance.map = {
        texel_state = R_table.create_2d(instance.base.texel_width, instance.base.texel_height, function() return 0 end),
        --- @type (number?)[][]
        texel_fg = R_table.create_2d(instance.base.texel_width, instance.base.texel_height, function() return fg end),
        --- @type (number?)[][]
        texel_bg = R_table.create_2d(instance.base.texel_width, instance.base.texel_height, function() return bg end)
    }

    --  TexelCanvas Overrides

    --- @private
    --- @param x integer
    --- @param char string
    --- @param fg (number|string)?
    --- @param bg (number|string)?
    --- @param state_row integer[]
    --- @param fg_row (number?)[]
    --- @param bg_row (number?)[]
    local function __set_texel_update_maps(x, char, fg, bg, state_row, fg_row, bg_row)
        local code = native.string.byte(char)

        if (code < 128) or (code > 159) then
            -- The texel isn't a block character, invalidate all pixels in the texel
            state_row[x] = INVALID_TEXEL_STATE
        else
            -- The texel is a block character, force the map to use it and its colors
            state_row[x] = __char_to_bits_lookup[code]

            if fg ~= nil then
                fg_row[x] = type(fg) == "number" and fg or nil
            end

            if bg ~= nil then
                bg_row[x] = type(bg) == "number" and bg or nil
            end
        end
    end

    --- [override] Paints the given character texel onto the canvas and forces it to be visible
    --- @param x integer  The horizontal texel coordinate
    --- @param y integer  The vertical texel coordinate
    --- @param char string  The texel to paint
    --- @param params TexelSetParameters  The parameters for painting the texel
    function instance:set_texel(x, y, char, params)
        self.base:set_texel(x, y, char, params)

        __set_texel_update_maps(x, char, params.fg, params.bg, self.map.texel_state[y], self.map.texel_fg[y], self.map.texel_bg[y])
    end

    --- [override] Updates one of the colors for the given character texel
    --- @param x integer  The horizontal texel coordinate
    --- @param y integer  The vertical texel coordinate
    --- @param color number|string  The color to update as a <code>colors</code> value or <code>"-"</code> to defer to the terminal's color when painting
    --- @param background boolean  If <code>true</code>, the background color will be updated; otherwise, the foreground color will be updated
    function instance:set_texel_color(x, y, color, background)
        self.base:set_texel_color(x, y, color, background)

        local map = self.map

        if background then
            map.texel_bg[y][x] = type(color) == "number" and color or nil
        else
            map.texel_fg[y][x] = type(color) == "number" and color or nil
        end
    end

    --- [override] Paints the given texel sequence on the canvas and forces it to be visible
    --- @param x number  The horizontal texel coordinate of the start of the text
    --- @param y number  The vertical texel coordinate of the text
    --- @param text string  The texels to paint
    --- @param params ManyTexelSetParameters  The parameters for painting the text
    --- @return integer count  The number of texels that were painted
    --- @return integer end_x  The horizontal texel coordinate of the texel after the end of the painted text
    --- @return integer end_y  The vertical texel coordinate of the texel after the end of the painted text
    function instance:set_texel_many(x, y, text, params)
        local orig_x, orig_y, orig_text = x, y, text
        local count, end_x, end_y = self.base:set_texel_many(x, y, text, params)

        if count > 0 and not params.vertical then
            -- Note: params.vertical calls set_texel() for each character, so the map is already updated in that case

            local fg = params.fg
            local bg = params.bg

            local text_start, text_end, length
            x, y, text, text_start, text_end, length = self:__set_texel_many_resolve_parameters(orig_x, orig_y, orig_text, params)

            if length > 0 and text_start <= text_end then
                local map = self.map
                local texel_state_row = map.texel_state[y]
                local texel_fg_row = map.texel_fg[y]
                local texel_bg_row = map.texel_bg[y]

                for i = text_start, text_end do
                    __set_texel_update_maps(x + i - text_start, native.string.sub(text, i, i), fg, bg, texel_state_row, texel_fg_row, texel_bg_row)
                end
            end
        end

        return count, end_x, end_y
    end

    --  (end) TexelCanvas Overrides

    --- @private
    --- @param texel_x integer
    --- @param texel_y integer
    --- @param updating_fg 0|1|2|3  Indicates whether the update is for the foreground color (1), background color (2), both (3) or neither (0)
    function instance:refresh_texel(texel_x, texel_y, updating_fg)
        local map = self.map
        local texel_state = map.texel_state[texel_y][texel_x]
        local texel_char = __bits_to_char_lookup[texel_state]
        local texel_colors_fg = map.texel_fg[texel_y][texel_x]
        local texel_colors_bg = map.texel_bg[texel_y][texel_x]

        local texel_fg, texel_bg

        if texel_state <= 31 then
            -- Normal texel characters use the colors as-is
            texel_fg = texel_colors_fg
            texel_bg = texel_colors_bg
        else
            -- "Negated" texel characters require swapping the colors
            texel_fg = texel_colors_bg
            texel_bg = texel_colors_fg
        end

        self.base:set_texel(
            texel_x,
            texel_y,
            texel_char,
            {
                fg = native.bit32.btest(updating_fg, 1) and (texel_fg or "-") or nil,
                bg = native.bit32.btest(updating_fg, 2) and (texel_bg or "-") or nil
            }
        )
    end

    --- Returns whether the specified pixel coordinates are within the bounds of the canvas
    --- @param x integer  The horizontal pixel coordinate
    --- @param y integer  The vertical pixel coordinate
    --- @return boolean
    function instance:contains_pixel(x, y)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        return x >= 1 and x <= self.pixel_width and y >= 1 and y <= self.pixel_height
    end

    --- Gets the color of the specified pixel on the canvas
    --- @param x integer  The horizontal pixel coordinate
    --- @param y integer  The vertical pixel coordinate
    --- @return number? color  The color of the pixel, or <code>nil</code> if the pixel is transparent, defers its color to the terminal or is not a block grid character
    --- @return boolean? active  Whether the pixel will try to use the foreground color of its texel, or <code>nil</code> if the pixel is transparent or not a block grid character
    function instance:get_pixel(x, y)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        if not self:contains_pixel(x, y) then
            error(string.format("Pixel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        local texel_x, texel_y = pixel_to_texel(x, y)

        if not self:contains_texel(texel_x, texel_y) then
            error(string.format("Texel coordinates (%d, %d) are out of bounds (from pixel coordinates (%d, %d))", texel_x, texel_y, x, y), 2)
        end

        if self:hidden(texel_x, texel_y) then
            -- The pixel is transparent
            return nil, nil
        end

        local bit = bit32.lshift(1, (y % 3) * 2 + (x % 2))

        local map = self.map
        local texel_state = map.texel_state[texel_y][texel_x]

        if native.bit32.btest(texel_state, INVALID_TEXEL_STATE) then
            -- The texel isn't one of the blocky characters
            return nil, nil
        end

        local active = native.bit32.btest(texel_state, bit)
        local color

        if (texel_state <= 31) == active then
            -- The pixel uses the foreground color of the texel
            color = map.texel_fg[texel_y][texel_x]
        else
            -- The pixel uses the background color of the texel
            color = map.texel_bg[texel_y][texel_x]
        end

        return color, active
    end

    --- @private
    --- @param x integer
    --- @param y integer
    --- @param color number?
    --- @param active boolean
    --- @return boolean changed
    --- @return 0|1|2|3 updated_colors  Indicates whether the update is for the foreground color (1), background color (2), both (3) or neither (0)
    function instance:update_pixel(x, y, color, active)
        if not self:contains_pixel(x, y) then
            error(string.format("Pixel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        local changed = false
        local updated_colors = 0

        local texel_x, texel_y = pixel_to_texel(x, y)

        if not self:contains_texel(texel_x, texel_y) then
            error(string.format("Texel coordinates (%d, %d) are out of bounds (from pixel coordinates (%d, %d))", texel_x, texel_y, x, y), 2)
        end

        local bit_to_check = bit32.lshift(1, ((y - 1) % 3) * 2 + ((x - 1) % 2))

        local map = self.map
        local texel_state_row = map.texel_state[texel_y]
        local current_state = texel_state_row[texel_x]
        local current_active = native.bit32.btest(current_state, bit_to_check)

        if active ~= current_active then
            -- The state of the pixel is being flipped
            current_state = native.bit32.bxor(current_state, bit_to_check)
            texel_state_row[texel_x] = current_state
            changed = true
        end

        local texel_fg_row = map.texel_fg[texel_y]
        local texel_bg_row = map.texel_bg[texel_y]
        local current_color

        if (current_state <= 31) == active then
            -- The pixel will use the foreground color
            current_color = texel_fg_row[texel_x]
            texel_fg_row[texel_x] = color
            updated_colors = 1
        else
            -- The pixel will use the background color
            current_color = texel_bg_row[texel_x]
            texel_bg_row[texel_x] = color
            updated_colors = 2
        end

        if current_color ~= color then
            changed = true
        end

        return changed, updated_colors
    end

    --- @private
    --- @type table<integer, table<integer, 0|1|2|3>>
    instance.__pending_texel_updates = nil
    --- @private
    --- @type boolean
    instance.__has_active_group = false

    --- Notifies the <code>set_pixel()</code> family of functions that the texel updates may be added across multiple calls, so they shouldn't push updates just yet<br/>
    --- To flush the texel updates, call <code>end_update_group()</code>
    function instance:begin_update_group()
        if self.__has_active_group then
            error("A texel update group is already active", 2)
        end

        self.__has_active_group = true
        self.__pending_texel_updates = {}
    end

    --- Attempts call <code>begin_update_group()</code> and returns whether it was successful
    --- @return boolean
    function instance:try_begin_update_group()
        if not self.__has_active_group then
            self:begin_update_group()
            return true
        end

        return false
    end

    --- @private
    --- @param updating_table table<integer, table<integer, 0|1|2|3>>
    function instance:__push_texel_updates(updating_table)
        for texel_y, row in pairs(updating_table) do
            for texel_x, updating_colors in pairs(row) do
                self:refresh_texel(texel_x, texel_y, updating_colors)
            end
        end
    end

    --- Flushes any pending texel updates from the <code>set_pixel()</code> family of functions and allows them to push texel updates<br/>
    --- A call to <code>begin_update_group()</code> is required before calling this method
    function instance:end_update_group()
        if not self.__has_active_group then
            error("No texel update group is active", 2)
        end

        self:__push_texel_updates(self.__pending_texel_updates)

        self.__has_active_group = false
        self.__pending_texel_updates = nil
    end

    --- @param texel_x integer
    --- @param texel_y integer
    --- @param updating_table table<integer, table<integer, 0|1|2|3>>
    --- @param updated_colors 0|1|2|3  Indicates whether the update is for the foreground color (1), background color (2), both (3) or neither (0)
    local function __mark_texel_for_updates(texel_x, texel_y, updating_table, updated_colors)
        local existing_row = updating_table[texel_y]
        if not existing_row then
            existing_row = {}
            updating_table[texel_y] = existing_row
        end

        local existing_column = existing_row[texel_x]
        if existing_column and existing_column > 0 then
            -- The texel was already being updated, force both colors to be updated
            existing_row[texel_x] = 3
        else
            -- A new texel is being updated, mark it for the appropriate color updates, if any
            existing_row[texel_x] = updated_colors
        end
    end

    --- Sets the color of the specified pixel on the canvas
    --- @param x integer  The horizontal pixel coordinate
    --- @param y integer  The vertical pixel coordinate
    --- @param color number?  The new color for the pixel, or <code>nil</code> to make the pixel defer its color to the terminal
    --- @param active boolean  Whether the pixel should be considered "active".<br/>Active pixels will try to use the foreground color of their texel (unless the texel state requires using the background color instead) whereas inactive pixels use the opposite.
    function instance:set_pixel(x, y, color, active)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        if not self:contains_pixel(x, y) then
            error(string.format("Pixel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        local changed, updated_colors = self:update_pixel(x, y, color, active)

        if changed then
            local texel_x, texel_y = pixel_to_texel(x, y)
            if not self.__has_active_group then
                self:refresh_texel(texel_x, texel_y, updated_colors)
            else
                __mark_texel_for_updates(texel_x, texel_y, self.__pending_texel_updates, updated_colors)
            end
        end
    end

    --- Sets whether the specified pixel on the canvas is active
    --- @param x integer  The horizontal pixel coordinate
    --- @param y integer  The vertical pixel coordinate
    --- @param active boolean  Whether the pixel should be considered "active".<br/>Active pixels will try to use the foreground color of their texel (unless the texel state requires using the background color instead) whereas inactive pixels use the opposite.
    function instance:set_pixel_state(x, y, active)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        if not self:contains_pixel(x, y) then
            error(string.format("Pixel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        local texel_x, texel_y = pixel_to_texel(x, y)
        local bit_to_check = bit32.lshift(1, (y % 3) * 2 + (x % 2))

        local map = self.map
        local texel_state_row = map.texel_state[texel_y]
        local current_state = texel_state_row[texel_x]
        local current_active = native.bit32.btest(current_state, bit_to_check)

        if active ~= current_active then
            -- The state of the pixel is being flipped
            current_state = native.bit32.bxor(current_state, bit_to_check)
            texel_state_row[texel_x] = current_state

            if not self.__has_active_group then
                -- Preserve the colors by having it "update" both without actually changing them
                self:refresh_texel(texel_x, texel_y, 0)
            else
                __mark_texel_for_updates(texel_x, texel_y, self.__pending_texel_updates, 0)
            end
        end
    end

    --- Sets the activity of all six pixels within the specified texel
    --- @param x integer  The horizontal texel coordinate
    --- @param y integer  The vertical texel coordinate
    --- @param active_bits integer  The activity of each pixel<p/>Each bit in the value cooresponds to the following pixels:<br/>0 1<br/>2 3<br/>4 5<p/>Using values smaller than 0 or larger than 63 will throw an error
    function instance:set_pixel_state_texel(x, y, active_bits)
        self.verify_integer_coordinate(x, "x")
        self.verify_integer_coordinate(y, "y")

        if not self:contains_texel(x, y) then
            error(string.format("Texel coordinates (%d, %d) are out of bounds", x, y), 2)
        end

        if active_bits < 0 or active_bits > 63 then
            error(string.format("active_bits must be between 0 and 63 (inclusive), was %d", active_bits), 2)
        end

        local map = self.map
        local texel_state_row = map.texel_state[y]
        local current_state = texel_state_row[x]

        if current_state ~= active_bits then
            texel_state_row[x] = active_bits

            if not self.__has_active_group then
                -- Preserve the colors by having it "update" both without actually changing them
                self:refresh_texel(x, y, 0)
            else
                __mark_texel_for_updates(x, y, self.__pending_texel_updates, 0)
            end
        end
    end

    --- @alias PixelCanvasIterationFunction fun() : integer?, integer?, number?, boolean?

    --- Sets the colors of multiple pixels on the canvas
    --- @param iter PixelCanvasIterationFunction  An iterator which returns the coordinates and color for each pixel to update, or <code>nil</code> to stop iterating
    function instance:set_pixel_many(iter)
        --- @type table<integer, table<integer, 0|1|2|3>>
        local updates = self.__has_active_group and self.__pending_texel_updates or {}

        local x, y, color, active = iter()

        while x ~= nil and y ~= nil do
            if not self:contains_pixel(x, y) then
                error(string.format("Pixel coordinates (%d, %d) are out of bounds", x, y), 2)
            end
            if active == nil then
                error(string.format("Attempted to set a nil active state for pixel coordinates (%d, %d)", x, y), 2)
            end

            local texel_x, texel_y = pixel_to_texel(x, y)
            local changed, updated_colors = self:update_pixel(x, y, color, active)

            if changed then
                __mark_texel_for_updates(texel_x, texel_y, updates, updated_colors)
            end

            x, y, color, active = iter()
        end

        if not self.__has_active_group then
            -- Refresh the updated texels
            self:__push_texel_updates(updates)
        end
    end

    return instance
end

return {
    --- The classes defined by this module
    class = {
        --- A class representing an area of character texels within a terminal
        TexelCanvas = TexelCanvas,
        --- An implementation of TexelCanvas that allows for finer control of individual pixels within each texel in the canvas<br/>
        --- <b>Note:</b> Due to limitations in CraftOS rendering, each texel can only have two colors
        PixelCanvas = PixelCanvas
    },
    --- Constants defined by this module
    consts = {
        --- The smallest value for the state of a texel in a PixelCanvas (0x00, 0)
        MIN_TEXEL_STATE = MIN_TEXEL_STATE,
        --- The largest value for the state of a texel in a PixelCanvas (0x3F, 63)
        MAX_TEXEL_STATE = MAX_TEXEL_STATE,
        --- Represents the state for any character texel in a PixelCanvas that isn't part of the block character set
        INVALID_TEXEL_STATE = INVALID_TEXEL_STATE
    },
    pixel_to_texel = pixel_to_texel,
    texel_to_pixel = texel_to_pixel
}