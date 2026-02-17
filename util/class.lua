-- Based on: http://lua-users.org/wiki/SimpleLuaClasses

-- class.lua
-- Compatible with Lua 5.1 (not 5.0).

--- Defines a table representing an object-oriented class, which can be instantiated by calling it like a function.
--- @param base table|function?  An optional base class to inherit from
--- @param init function?  An optional initializer function for the class, which will be called
function class(base, init)
    local class = {}  -- a new class instance

    if not init and type(base) == 'function' then
        init = base
        base = nil
    elseif type(base) == 'table' then
        -- our new class is a shallow copy of the base class!
        for i,v in pairs(base) do
            class[i] = v
        end
        class.base = base
    end

    -- the class will be the metatable for all its objects,
    -- and they will look up their methods in it.
    class.__index = class

    -- expose a constructor which can be called by <classname>(<args>)
    local mt = {}

    --- @param class_tbl table  The class definition table
    mt.__call = function(class_tbl, ...)
        local obj = {}
        setmetatable(obj, class_tbl)

        if init then
            init(obj, ...)
        else
            -- make sure that any stuff from the base class is initialized!
            if base and base.init then
                base.init(obj, ...)
            end
        end

        return obj
    end

    -- Other functions on any class-like object by default

    --- Returns a new instance of this class, initialized with the given arguments
    class.init = init

    --- Returns whether this object or its base classes are an instance of the given class
    --- @param self table  The object to check
    --- @param klass table  The class to check against
    class.is_a = function(self, klass)
        local m = getmetatable(self)

        while m do
            if m == klass then return true end
            m = m.base
        end

        return false
    end

    setmetatable(class, mt)

    return class
end

return {
    class = class
}