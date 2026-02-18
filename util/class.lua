-- Based on: http://lua-users.org/wiki/SimpleLuaClasses

-- class.lua
-- Compatible with Lua 5.1 (not 5.0).

--- @alias ClassPopulator fun(class: PublicClassDefinition, ...)
--- @alias ClassFunctionNew fun(self: PublicClassDefinition, ...) : PublicClassInstance
--- @alias ClassFunctionInstanceCtor fun(self: PublicClassDefinition, instance: PublicClassInstance, ...)
--- @alias ClassFunctionInstanceof fun(self: PublicClassDefinition, klass: PublicClassDefinition) : boolean
--- @alias ClassFunctionBase fun(self: PublicClassDefinition) : PublicClassDefinition?

--- @alias ClassInstanceFunctionInstanceof fun(self: PublicClassInstance, klass: PublicClassDefinition) : boolean
--- @alias ClassInstanceFunctionBase fun(self: PublicClassInstance) : PublicClassDefinition?

--- @alias FieldNames table<string, boolean>

--- @alias BaseClassDefinition { __fields: FieldNames, new: ClassFunctionNew }
--- @alias ClassDefinition { __base: BaseClassDefinition?, __fields: FieldNames, new: ClassFunctionNew, ctor: ClassFunctionInstanceCtor, instanceof: ClassFunctionInstanceof, base: ClassFunctionBase }

--- @alias PublicClassDefinition { new: ClassFunctionNew, ctor: ClassFunctionInstanceCtor, instanceof: ClassFunctionInstanceof, base: ClassFunctionBase, [any]: any }

--- @alias BaseClassInstance { __fields: FieldNames }
--- @alias ClassInstance { class: ClassDefinition, __base: BaseClassInstance?, __fields: FieldNames, instanceof: ClassInstanceFunctionInstanceof, base: ClassInstanceFunctionBase }

--- @alias PublicClassInstance { instanceof: ClassInstanceFunctionInstanceof, base: ClassInstanceFunctionBase, [any]: any }

--- Attempts to find the class that defines the given field, or returns nil if no such class exists
--- @param klass ClassDefinition|ClassInstance  The class to start searching from
--- @param name string  The name of the field to find
--- @return ClassDefinition|BaseClassDefinition|ClassInstance|BaseClassInstance|nil
local function find_field_in_class(klass, name)
    if klass.__fields[name] then
        return klass
    elseif klass.__base then
        local current = klass.__base
        while current do
            if current.__fields[name] then return current end
            current = current.__base
        end
    end
end

--- Attempts to assign a value to a field on an object, following the rules for field assignment
--- @param obj ClassDefinition|ClassInstance  The object to assign the field on
--- @param name string  The name of the field to assign
--- @param value any  The value to assign to the field
local function assign_field(obj, name, value)
    if obj.__base then
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
--- @param obj ClassDefinition|ClassInstance  The object to read the field from
--- @param name string  The name of the field to read
--- @return any
local function get_field(obj, name)
    if obj.__base then
        local defining_class = find_field_in_class(obj, name)
        return defining_class and rawget(defining_class, name) or nil
    else
        return obj.__fields[name] and rawget(obj, name) or nil
    end
end

--- Returns whether the given class inherits from another class (or is the same class)
--- @param klass ClassDefinition  The class to check
--- @param other ClassDefinition  The class to check against
--- @return boolean
local function instanceof(klass, other)
    if klass == other then return true end
    if klass.__base then
        local current = klass.__base
        while current do
            if current == other then return true end
            current = current.__base
        end
    end
    return false
end

--- Defines a table representing an object-oriented class, which can be instantiated by calling it like a function.
--- @param base BaseClassDefinition?  An optional base class to inherit from
--- @param def ClassPopulator? An optional function to add additional fields or methods to the class definition
--- @return PublicClassDefinition
function class(base, def)
    --- @param name string  The name of the field being accessed
    --- @param action string  The type of action being attempted on the field
    local function error_field_defined_on_class(name, action)
        error("Attempted to " .. action .. " field '" .. name .. "' on a class instance when it is defined on the class definition instead.")
    end

    --- @param name string  The name of the field being accessed
    local function error_field_readonly(name)
        error("Attempted to modify read-only field '" .. name .. "'.")
    end

    --- @param klass ClassDefinition
    --- @return ClassInstance
    local function create_instance(klass, ...)
        local instance = {
            class = klass,
            __fields = {
                ["class"] = true,
                ["__base"] = true,
                ["__fields"] = true
            }
        }

        if klass.__base then
            instance.__base = (klass.__base --[[@as ClassDefinition]]):new(...)
        end

        return instance
    end

    --- @param klass ClassDefinition  The class definition to create the metatable from
    local function create_instance_metatable(klass)
        return {
            --- @param self table
            --- @param name string
            __index = function (self, name)
                if klass[name] ~= nil then error_field_defined_on_class(name, "get") end
                return get_field(self, name)
            end,
            --- @param self table
            --- @param name string
            --- @param value any
            __newindex = function (self, name, value)
                if name == "class" or name == "__base" or name == "__fields" then
                    error_field_readonly(name)
                elseif klass[name] ~= nil then
                    error_field_defined_on_class(name, "set")
                else
                    assign_field(self, name, value)
                end
            end
        }
    end

    --- @return ClassDefinition
    local function create_definition()
        return {
            --- @type BaseClassDefinition?
            __base = base,
            --- @type FieldNames
            __fields = {
                ["__base"] = true,
                ["__fields"] = true,
                ["new"] = true,
                ["ctor"] = true
            },
            --- @param self ClassDefinition
            --- @param ... any
            --- @return ClassInstance
            new = function(self, ...)
                --- @type ClassInstance
                local instance = setmetatable(create_instance(self, ...), create_instance_metatable(self));

                function instance:instanceof(klass) return instanceof(self.class, klass) end

                function instance:base() return self.__base --[[@as PublicClassDefinition]] end

                self:ctor(instance --[[@as PublicClassInstance]], ...)
                
                return instance
            end
        }
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
                if name == "__base" or name == "__fields" or name == "new" then
                    error_field_readonly(name)
                else
                    assign_field(self, name, value)
                end
            end
        }
    end

    -- The new class definition
    --- @type ClassDefinition
    local class = setmetatable(create_definition(), create_definition_metatable())

    --- @param self PublicClassDefinition
    --- @param instance PublicClassInstance  The instance to initialize
    --- @param ... any  The arguments to pass to the initializer function
    function class:ctor(instance, ...) end

    --- @param self PublicClassDefinition
    --- @param klass PublicClassDefinition The class to check against
    --- @return boolean
    function class:instanceof(klass) return instanceof(self, klass) end

    --- @param self PublicClassDefinition
    --- @return PublicClassDefinition?
    function class:base() return self.__base end

    if def then def(class) end

    return class --[[@as PublicClassDefinition]]
end

return {
    class = class,
    instanceof = instanceof
}