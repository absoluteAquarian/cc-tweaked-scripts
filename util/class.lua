-- Based on: http://lua-users.org/wiki/SimpleLuaClasses

-- class.lua
-- Compatible with Lua 5.1 (not 5.0).

--- @class __Classlike
--- @field __fields { [string] : boolean }  A set of field names that are defined on this class-like object
--- @field base __Classlike?  The base class-like object
--- @field class ClassDefinition  The class definition for this class-like object
--- @field instanceof fun(self: __Classlike, other: ClassDefinition) : boolean  A function to check if this class-like object's class definition is the same as or inherits from another class definition
local __Classlike = nil

--- @class ClassDefinition : __Classlike
--- (Overrides)
--- @field base ClassDefinition?  The base class definition
--- (Defines)
--- @field __make_instance fun(self: ClassDefinition, ...) : ClassInstance  A function to create a new class instance from the class definition
--- @field new fun(self: ClassDefinition, ...) : ClassInstance  A function to create a new class instance from the class definition
local __ClassDefinition = nil

--- @class ClassInstance : __Classlike
--- (Overrides)
--- @field base ClassInstance?  The class instance of the class definition's base class definition
local __ClassInstance = nil

--- Attempts to find the class-like object that defines the given field, or returns nil if no such object exists
--- @param klass __Classlike  The class-like object to start searching from
--- @param name string  The name of the field to find
--- @return __Classlike|nil
local function find_field_in_class(klass, name)
    if klass.__fields[name] then
        return klass
    elseif klass.base then
        local current = klass.base
        while current do
            if current.__fields[name] then return current end
            current = current.base
        end
    end
end

--- Attempts to assign a value to a field on an object, following the rules for field assignment
--- @param obj __Classlike  The object to assign the field on
--- @param name string  The name of the field to assign
--- @param value any  The value to assign to the field
local function assign_field(obj, name, value)
    if obj.base then
        local defining_class = find_field_in_class(obj, name)
        if defining_class then
            -- The field is defined either on the class or a base class, so modify it directly
            rawset(defining_class, name, value)
        else
            -- The field is not defined on any base class, so add it to this instance
            obj.__fields[name] = true
            rawset(obj, name, value)
        end
    else
        -- No base class, so any new field must be added to this instance
        obj.__fields[name] = true
        rawset(obj, name, value)
    end
end

--- Attempts to read a field from an object, following the rules for field access
--- @param obj __Classlike  The object to read the field from
--- @param name string  The name of the field to read
--- @return any
local function get_field(obj, name)
    -- Since this function indexes the object, it will trigger the __index metamethod
    -- This will result in a stack overflow because the metamethod will call this function again
    -- To fix this, certain indices must bypass the special code
    if name == "class" or name == "base" or name == "__fields" then
        return rawget(obj, name)
    end

    if obj.base then
        local defining_class = find_field_in_class(obj, name)
        return defining_class and rawget(defining_class, name) or nil
    else
        return obj.__fields[name] and rawget(obj, name) or nil
    end
end

--- Returns whether the given class inherits from another class (or is the same class)
--- @param klass __Classlike  The class-like object to check
--- @param other ClassDefinition  The class to check against
--- @return boolean
local function instanceof(klass, other)
    if klass.class == other then return true end
    if klass.base then
        local current = klass.base.class
        while current do
            if current == other then return true end
            current = current.base
        end
    end
    return false
end

--- Defines a table representing an object-oriented class, which can be instantiated by calling it like a function.
--- @param base ClassDefinition?  An optional base class to inherit from
--- @param def fun(klass: ClassDefinition)? An optional function to add additional fields or methods to the class definition
--- @return ClassDefinition
local function class(base, def)
    --- @param name string  The name of the field being accessed
    --- @param action string  The type of action being attempted on the field
    local function error_field_defined_on_class(name, action)
        error("Attempted to " .. action .. " field '" .. name .. "' on a class instance when it is defined on the class definition instead.")
    end

    --- @param name string  The name of the field being accessed
    local function error_field_readonly(name)
        error("Attempted to modify read-only field '" .. name .. "'.")
    end

    --- @param name string
    --- @return boolean
    local function is_classlike(name)
        return name == "class" or name == "base" or name == "__fields" or name == "instanceof"
    end

    --- @param klass ClassDefinition
    --- @return ClassInstance
    local function create_instance(klass, ...)
        local instance = {
            __fields = {
                ["class"] = true,
                ["base"] = true,
                ["__fields"] = true
            },
            class = klass
        }

        if klass.base then
            instance.base = klass.base:new(...)
        end

        return instance
    end

    --- @param klass ClassDefinition
    local function create_instance_metatable(klass)
        return {
            --- @param self ClassInstance
            --- @param name string
            __index = function(self, name)
                if (not is_classlike(name)) and self.class[name] ~= nil then
                    error_field_defined_on_class(name, "get")
                end
                return get_field(self, name)
            end,
            --- @param self ClassInstance
            --- @param name string
            --- @param value any
            __newindex = function(self, name, value)
                if name == "class" or name == "base" or name == "__fields" then
                    error_field_readonly(name)
                elseif (not is_classlike(name)) and self.class[name] ~= nil then
                    error_field_defined_on_class(name, "set")
                else
                    assign_field(self, name, value)
                end
            end
        }
    end

    --- @return ClassDefinition
    local function create_definition()
        local definition = {
            __fields = {
                ["__fields"] = true,
                ["__make_instance"] = true,
                ["base"] = true,
                ["new"] = true
            },
            base = base
        }

        --- @cast definition ClassDefinition
        
        function definition:__make_instance(...)
            --- @type ClassInstance
            local instance = setmetatable(create_instance(self, ...), create_instance_metatable(self));

            function instance:instanceof(klass) return instanceof(self, klass) end
            
            return instance
        end

        function definition:new(...) return self:__make_instance(...) end

        function definition:instanceof(klass) return instanceof(self, klass) end

        return definition
    end

    local function create_definition_metatable()
        return {
            --- @param self ClassDefinition
            --- @param name string
            __index = function(self, name) return get_field(self, name) end,
            --- @param self ClassDefinition
            --- @param name string
            --- @param value any
            __newindex = function(self, name, value)
                if name == "base" or name == "__fields" or name == "__instance" then
                    error_field_readonly(name)
                else
                    assign_field(self, name, value)
                end
            end
        }
    end

    --- @type ClassDefinition
    local class = setmetatable(create_definition(), create_definition_metatable())

    if def then def(class) end

    return class
end

return {
    class = class,
    instanceof = instanceof
}