-- Based on: http://lua-users.org/wiki/SimpleLuaClasses

--- @class __Classlike
--- @field __fields { [string] : boolean }  A set of field names that are defined on this class-like object
--- @field base __Classlike?  The base class-like object
--- @field class ClassDefinition  The class definition for this class-like object
--- @field instanceof fun(self: __Classlike, other: ClassDefinition) : boolean  A function to check if this class-like object's class definition is the same as or inherits from another class definition

--- @class ClassDefinition : __Classlike
--- (Overrides)
--- @field base ClassDefinition?  The base class definition
--- (Defines)
--- @field __make_instance fun(self: ClassDefinition, ...) : ClassInstance  A function to create a new class instance from the class definition
--- @field new fun(self: ClassDefinition, ...) : ClassInstance  A function to create a new class instance from the class definition

--- @class ClassInstance : __Classlike
--- (Overrides)
--- @field base ClassInstance?  The class instance of the class definition's base class definition

--- Returns whether the given class-like object has a field with the given name defined on it (not including base classes)
--- @param klass __Classlike  The class-like object to check
--- @param name string  The name of the field to check for
--- @return boolean
local function __has_field(klass, name)
    return rawget(klass, "__fields")[name]
end

--- Marks the given field name as being defined on the given class-like object
--- @param klass __Classlike  The class-like object to mark the field as being defined on
--- @param name string  The name of the field to mark as being defined on the class-like object
local function __define_field(klass, name)
    rawget(klass, "__fields")[name] = true
end

--- Returns the base class-like object for the given class-like object
--- @param klass __Classlike  The class-like object to get the base of
--- @return __Classlike?
local function __get_base(klass)
    return rawget(klass, "base")
end

--- Returns the class definition for the given class-like object
--- @param klass __Classlike  The class-like object to get the class definition of
--- @return ClassDefinition
local function __get_class(klass)
    return rawget(klass, "class")
end

--- Attempts to find the class-like object that defines the given field, or returns nil if no such object exists
--- @param klass __Classlike  The class-like object to start searching from
--- @param name string  The name of the field to find
--- @return __Classlike?
local function find_field_in_class(klass, name)
    if __has_field(klass, name) then
        return klass
    elseif __get_base(klass) then
        local current = __get_base(klass)
        while current do
            if __has_field(current, name) then return current end
            current = __get_base(current)
        end
    end
end

--- Attempts to assign a value to a field on an object, following the rules for field assignment
--- @param obj __Classlike  The object to assign the field on
--- @param name string  The name of the field to assign
--- @param value any  The value to assign to the field
local function assign_field(obj, name, value)
    if __get_base(obj) then
        local defining_class = find_field_in_class(obj, name)
        if defining_class then
            -- The field is defined either on the class or a base class, so modify it directly
            rawset(defining_class, name, value)
        else
            -- The field is not defined on any base class, so add it to this instance
            __define_field(obj, name)
            rawset(obj, name, value)
        end
    else
        -- No base class, so any new field must be added to this instance
        __define_field(obj, name)
        rawset(obj, name, value)
    end
end

--- Attempts to read a field from an object, following the rules for field access
--- @param obj __Classlike  The object to read the field from
--- @param name string  The name of the field to read
--- @return any
local function get_field(obj, name)
    if __get_base(obj) then
        local defining_class = find_field_in_class(obj, name)
        return defining_class and rawget(defining_class, name) or nil
    else
        return __has_field(obj, name) and rawget(obj, name) or nil
    end
end

--- Returns whether the given class inherits from another class (or is the same class)
--- @param klass __Classlike  The class-like object to check
--- @param other ClassDefinition  The class to check against
--- @return boolean
local function instanceof(klass, other)
    if __get_class(klass) == other then return true end

    local base = __get_base(klass)
    if base then
        --- @type __Classlike?
        local current = __get_class(base)
        while current do
            if current == other then return true end
            current = __get_base(current)
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
        return name == "base" or name == "class" or name == "__fields" or name == "instanceof"
    end

    --- @param klass ClassDefinition
    --- @return ClassInstance
    local function create_instance(klass, ...)
        local instance = {
            __fields = {
                ["base"] = true,
                ["class"] = true,
                ["instanceof"] = true,
                ["__fields"] = true
            },
            class = klass
        }

        --- @cast instance ClassInstance

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
                if is_classlike(name) then
                    error_field_readonly(name)
                elseif not not get_field(__get_class(self), name) then
                    error_field_defined_on_class(name, "get")
                end
                return get_field(self, name)
            end,
            --- @param self ClassInstance
            --- @param name string
            --- @param value any
            __newindex = function(self, name, value)
                if is_classlike(name) then
                    error_field_readonly(name)
                elseif not not get_field(__get_class(self), name) then
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
                ["base"] = true,
                ["class"] = true,
                ["instanceof"] = true,
                ["new"] = true,
                ["__fields"] = true,
                ["__make_instance"] = true
            },
            base = base
        }

        --- @cast definition ClassDefinition

        definition.class = definition

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
                if is_classlike(name) or name == "__make_instance" then
                    error_field_readonly(name)
                else
                    assign_field(self, name, value)
                end
            end
        }
    end

    --- @type ClassDefinition
    local klass = setmetatable(create_definition(), create_definition_metatable())

    if def then def(klass) end

    return klass
end

return {
    class = class,
    instanceof = instanceof
}