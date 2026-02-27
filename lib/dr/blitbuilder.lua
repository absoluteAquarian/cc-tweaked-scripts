local class = require("lib.class")
local R_string = require("lib.string")

--- @class BlitBuilderDefinition : ClassDefinition
local BlitBuilder = class.class("BlitBuilder")

--- [override] Creates a new BlitBuilder instance for the given terminal
--- @param terminal table  The terminal this BlitBuilder will write to
function BlitBuilder:new(terminal)
    --- @class BlitBuilder : ClassInstance
    local instance = self:create_instance(terminal)

    --- The terminal this BlitBuilder will write to
    instance.terminal = terminal
    --- The text to write
    instance.text = ""
    --- The built color string for the foreground colors
    instance.text_fg = ""
    --- The built color string for the background colors
    instance.text_bg = ""
    --- @class BlitBuilderCache  A cache of the built blit strings and the colors they were built with
    --- @field fg number  The original foreground color of the terminal
    --- @field bg number  The original background color of the terminal
    --- @field text_fg string  The built blit string for the foreground colors
    --- @field text_bg string  The built blit string for the background colors
    instance.cache = nil

    --- Appends text with the given colors to this BlitBuilder
    --- @param text string  The text to append
    --- @param fg string|number?  The color to use for the foreground, either as a blit color string or a colors value.  Defaults to the current foreground color if nil.
    --- @param bg string|number?  The color to use for the background, either as a blit color string or a colors value.  Defaults to the current background color if nil.
    function instance:append(text, fg, bg)
        if type(fg) == "string" and #text ~= #fg then
            error("Foreground color string must be the same length as the text", 2)
        end
        if type(bg) == "string" and #text ~= #bg then
            error("Background color string must be the same length as the text", 2)
        end

        self.text = self.text .. text

        local fg_blit = type(fg) == "number" and R_string.cached_rep(colors.toBlit(fg), #text) or fg == nil and R_string.cached_rep("-", #text) or fg
        local bg_blit = type(bg) == "number" and R_string.cached_rep(colors.toBlit(bg), #text) or bg == nil and R_string.cached_rep("-", #text) or bg

        self.text_fg = self.text_fg .. fg_blit
        self.text_bg = self.text_bg .. bg_blit

        self.cache = nil

        return self
    end

    --- Writes the blitted text to the terminal
    function instance:write()
        if not self.cache then
            local fg = self.terminal.getTextColor()
            local bg = self.terminal.getBackgroundColor()
            self.cache = {
                fg = fg,
                bg = bg,
                text_fg = self.text_fg:gsub("%-", colors.toBlit(fg)),
                text_bg = self.text_bg:gsub("%-", colors.toBlit(bg))
            }
        else
            -- Cache may be outdated; replace the fields when necessary
            local color = self.terminal.getTextColor()
            if color ~= self.cache.fg then
                self.cache.fg = color
                self.cache.text_fg = self.text_fg:gsub("%-", colors.toBlit(color))
            end

            color = self.terminal.getBackgroundColor()
            if color ~= self.cache.bg then
                self.cache.bg = color
                self.cache.text_bg = self.text_bg:gsub("%-", colors.toBlit(color))
            end
        end

        self.terminal.blit(self.text, self.cache.text_fg, self.cache.text_bg)
    end

    return instance
end

return {
    class = {
        BlitBuilder = BlitBuilder
    }
}