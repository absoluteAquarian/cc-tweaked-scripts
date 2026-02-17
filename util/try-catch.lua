-- From: https://github.com/Poeschl/computercraft-scripts/blob/main/try-catch.lua

-- This is a utility class to add try - catch functionality
-- include it by downloading to your computer and import it with 'require "util.try-catch"'

function catch(what)
    return what[1]
end

function try(what)
    local status, result = pcall(what[1])
    if not status then
        what[2](result)
    end
    return result
end

return {
    try = try,
    catch = catch
}