--- Converts a compact JSON string into a more human-readable format with indentation, whitespace and newlines.
--- @param json string  The JSON string to prettify.  Expected to be in a valid JSON format, though any whitespace not in quoted strings will be ignored.
--- @return string
local function prettify(json)
    local prettified = ""
    local indent = ""
    local quoted = false
    local c, prev = "", ""
    for i = 1, #json do
        prev = c
        c = json:sub(i, i)

        if not quoted then
            -- Ignore whitespace in the original string; this logic injects its own whitespace
            if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
                if c == "\"" and prev ~= "\\" then
                    quoted = true
                    prettified = prettified .. c
                elseif c == "{" or c == "[" then
                    if #prettified == 0 then
                        -- Start of the file, don't prepend a newline
                        prettified = prettified .. c .. "\n"
                    else
                        prettified = prettified .. "\n" .. indent .. c .. "\n"
                    end

                    indent = indent .. "  "
                elseif c == "}" or c == "]" then
                    if #indent > 0 then indent = indent:sub(1, -3) end
                    prettified = prettified .. "\n" .. indent .. c
                elseif c == "," then
                    prettified = prettified .. c .. "\n" .. indent
                else
                    prettified = prettified .. c
                end
            end
        else
            -- Reading is in the middle of a quoted string, so just append characters until the end quote is reached
            if c == "\"" and prev ~= "\\" then quoted = false end
            prettified = prettified .. c
        end
    end

    return prettified
end

return {
    prettify = prettify
}