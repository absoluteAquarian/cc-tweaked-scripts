-- Based on: http://lua-users.org/wiki/SimpleLuaClasses

local readonly = require "lib.readonly"
local R_table = require "lib.table"
local trace = require "lib.trace"

--- @private
--- @class Classlike  A table representing common fields for class-like objects
--- @field __fields FieldTracker  A set of field names that are defined on this class-like object
--- @field __type "definition"|"instance"  The classification of this class-like object
--- @field base Classlike?  The base class-like object
--- @field class ClassDefinition  The class definition for this class-like object
--- @field instanceof fun(self: Classlike, klass: ClassDefinition) : boolean  Whether this class-like object is an instance of the given class definition or any of its base classes

--- Returns whether the given class-like object defines the given field directly on itself, without checking base classes
--- @param klass Classlike  The class-like object to check
--- @param field string  The name of the field to check for
--- @return boolean
local function __has_field_directly(klass, field)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    return rawget(klass, "__fields")[field] == true
end

--- @param klass Classlike  The class-like object to define the field on
--- @param field string  The name of the field to define
local function __define_field(klass, field)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    rawget(klass, "__fields")[field] = true
end

--- Attempts to find the class-like object that defines the given field, or returns nil if no such object exists
--- @param klass Classlike  The class-like object to start searching from
--- @param field string  The name of the field to find
--- @return Classlike?
local function __find_defining_class(klass, field)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    if __has_field_directly(klass, field) then
        return klass
    else
        local base = rawget(klass, "base")
        while base do
            if __has_field_directly(base, field) then return base end
            base = rawget(base, "base")
        end
        return nil
    end
end

--- Returns whether the class-like object defines the given field, either directly or through a base class
--- @param klass Classlike  The class-like object to check
--- @param field string  The name of the field to check for
--- @return boolean
local function __has_field(klass, field)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    return __find_defining_class(klass, field) ~= nil
end

--- Returns whether the given field is read-only on the given class-like object
--- @param klass Classlike  The class-like object to check
--- @param field string  The name of the field to check
--- @return boolean
local function __is_readonly_field(klass, field)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    return klass.__fields.readonly[field] == true
end

--- Tags a field on a class-like object as read-only or not, for use with internal assignments of readonly fields after instance creation
--- @param klass Classlike  The class-like object to tag the field on
--- @param field string  The name of the field to tag
--- @param is_readonly boolean  Whether the field should be tagged as read-only or not
local function __tag_field_readonly(klass, field, is_readonly)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    if not __has_field(klass, field) then
        error("Field '" .. field .. "' is not defined on class " .. klass.__type .. " '" .. klass.class:nameof() .. "'", 2)
    else
        klass.__fields.readonly[field] = is_readonly
    end
end

--- Attempts to assign a value to a field on a class-like object, checking base classes if necessary
--- @param klass Classlike  The class-like object to assign the field on
--- @param field string  The name of the field to assign
--- @param value any  The value to assign to the field
local function __assign_field(klass, field, value)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    if rawget(klass, "base") then
        local defining_class = __find_defining_class(klass, field)
        if defining_class then
            -- The field is defined either on the class or a base class, so modify it directly
            rawset(defining_class, field, value)
        else
            -- The field is not defined on any base class, so add it to this instance
            __define_field(klass, field)
            rawset(klass, field, value)
        end
    else
        -- No base class, so any new field must be added to this instance
        __define_field(klass, field)
        rawset(klass, field, value)
    end
end

--- Attempts to read a field from a class-like object, checking base classes if necessary
--- @param obj Classlike  The object to read the field from
--- @param field string  The name of the field to read
--- @return any
local function __get_field(obj, field)
    local oop_proxy = rawget(obj, "__proxy_target")
    if oop_proxy then obj = oop_proxy end

    if rawget(obj, "base") then
        local defining_class = __find_defining_class(obj, field)
        return defining_class and rawget(defining_class, field) or nil
    else
        return __has_field_directly(obj, field) and rawget(obj, field) or nil
    end
end

--- Returns whether the given class inherits from another class (or is the same class)
--- @param klass Classlike  The class-like object to check
--- @param other ClassDefinition  The class to check against
--- @return boolean
local function __instanceof(klass, other)
    local oop_proxy = rawget(klass, "__proxy_target")
    if oop_proxy then klass = oop_proxy end

    if rawget(klass, "class") == other then return true end

    --- @type Classlike?
    local base = rawget(klass, "base")
    while base do
        if base == other then return true end
        base = rawget(base, "base")
    end

    return false
end

--- Defines a new table for tracking fields in a class-like object
--- @param ... string  A list of the readonly fields in the class-like object
--- @return FieldTracker
local function __create_fields_stringset(...)
    --- @class FieldTracker  A set of field names that are defined on a class-like object, with protections against modifying certain reserved field names
    local set = {
        --- @type { [string]: boolean }  The set of field names that are read-only on this class-like object
        readonly = {},
        --- @type { [string]: boolean }  The set of field names.  If true, the class-like object has defined a field with this name, even if its value is nil.
        names = {}
    }

    for _, name in ipairs({ ... }) do
        if type(name) ~= "string" or name == "" then error("Field names must be non-empty strings", 2) end
        set.readonly[name] = true
        set.names[name] = true
    end

    set.readonly = readonly.proxy(set.readonly)

    --- @type FieldTracker
    return setmetatable(
        {
            __proxy_target = set
        },
        {
            __index = trace.wrap(
                function(self, name)
                    --- @type FieldTracker
                    local target = rawget(self, "__proxy_target")

                    if name == "readonly" then
                        return target.readonly
                    end

                    local defined = target.names[name]
                    if defined == nil then
                        target.names[name] = false
                        return false
                    else
                        return defined
                    end
                end
            ),
            __newindex = trace.wrap(
                function(self, name, value)
                    if name == "readonly" then
                        error("Field definition 'readonly' is reserved and cannot be modified.", 2)
                    end

                    --- @type FieldTracker
                    local target = rawget(self, "__proxy_target")

                    if target.readonly[name] then
                        error("Field definition '" .. name .. "' is reserved and cannot be modified.", 2)
                    else
                        target.names[name] = value
                    end
                end
            )
        }
    )
end

--- @param proxy ObjectProxy
--- @return Classlike
local function __target(proxy)
    local target = rawget(proxy, "__proxy_target")
    if not target then error("Object proxy had a nil target object", 2) end
    return target
end

--- @param klass Classlike  The class-like object to create a proxy for
--- @param newindex fun(target: Classlike, key: any, value: any)  The __newindex metamethod for the proxy
--- @return table
local function __create_oop_proxy(klass, newindex)
    --- @type table
    return setmetatable(
        --- @private
        --- @class ObjectProxy  A proxy for a class-like object
        --- @field __proxy_target Classlike  The class-like object this is a proxy for
        {
            __proxy_target = klass
        },
        {
            __index = trace.wrap(function(self, key) return __target(self)[key] end),
            __newindex = trace.wrap(function(self, key, value) newindex(__target(self), key, value) end),
            __pairs = trace.wrap(function(self) return pairs(__target(self)) end),
            __ipairs = trace.wrap(function(self) return R_table.create_ipairs(__target(self)) end),
            __len = trace.wrap(function(self) return #__target(self) end),
            __tostring = trace.wrap(function(self) return tostring(__target(self)) end),
            __call = trace.wrap(function(self, ...) return __target(self)(...) end)
        }
    )
end

--- @param name string
--- @param base ClassDefinition?
--- @return ClassDefinition
local function class(name, base)
    -- Verify that the identifier is valid
    if type(name) ~= "string" or name == "" then
        error("Class name must be a non-empty string", 2)
    end

    --- @class ClassDefinition : Classlike  A class definition, which can be used to create class instances.  May optionally inherit from another class definition.
    local definition = {
        --- @private
        --- A set of field names that are defined on this class definition
        __fields = __create_fields_stringset(
            "__fields",
            "__instance",
            "__instance_mt",
            "__name",
            "__type",
            "base",
            "class",
            "create_instance",
            "instanceof",
            "name"
        ),
        --- @private
        --- The common metatable for class instances
        __instance_mt =
        {
            __index = trace.wrap(
                --- @param self ClassInstance
                --- @param key string
                --- @return any
                function(self, key)
                    if __has_field(rawget(self, "class"), key) then
                        error("Field '" .. key .. "' is defined on class definition '" .. rawget(self, "class"):nameof() .. "' and cannot be accessed through a class instance", 2)
                    elseif __is_readonly_field(self, key) then
                        -- Field must be defined on this instance, so just access it directly
                        return rawget(self, key)
                    else
                        -- Resolve the field using base classes
                        return __get_field(self, key)
                    end
                end
            )
        },
        --- @private
        --- The identifier for this class definition
        __name = name,
        --- @private
        --- The classification of this class-like object
        __type = "definition",
        --- The base class definition
        base = base
    }

    __define_field(definition, "nameof")
    __define_field(definition, "new")

    --- The class definition (itself)
    definition.class = definition

    --- @private
    --- @param self ClassDefinition
    --- @param ... any
    --- @return ClassInstance
    function definition:__instance(...)
        --- @class ClassInstance : Classlike  A class instances created by a class definition.  Does not share fields with its class definition or other instances.
        local instance = {
            --- @private
            --- A set of field names that are defined on this class instance
            __fields = __create_fields_stringset(
                "__fields",
                "__type",
                "base",
                "class",
                "instanceof"
            ),
            --- @private
            --- The classification of this class-like object
            __type = "instance",
            --- @type ClassInstance?  The class instance of the class definition's base class definition
            base = nil,
            class = self
        }

        if self.base then
            instance.base = self.base:new(...)
        end

        --- Whether this class instance is an instance of the given class definition or any of its base class definitions
        --- @param klass ClassDefinition  The class definition to check
        --- @return boolean
        function instance:instanceof(klass) return trace.scall(__instanceof, self, klass) end

        setmetatable(instance, self.__instance_mt)

        -- Wrap the instance in a proxy to handle field assignment with inheritance and protections
        --- @type ClassInstance
        return __create_oop_proxy(
            -- klass
            instance,
            -- __newindex
            function(target, key, value)
                if __has_field(target.class, key) then
                    error("Field '" .. key .. "' is defined on class definition '" .. target.class:nameof() .. "' and cannot be modified through a class instance", 3)
                elseif __is_readonly_field(target, key) then
                    error("Field '" .. key .. "' on class instance of '" .. target.class:nameof() .. "' is read-only and cannot be modified.", 3)
                else
                    __assign_field(target, key, value)
                end
            end
        )
    end

    --- @protected
    --- The native function for creating class instances
    --- @param ... any  The arguments to pass to the base class definition's new() function
    --- @return ClassInstance
    function definition:create_instance(...) return trace.scall(self.__instance, self, ...) end

    --- A function to create a new class instance from this class definition
    --- @param ... any  The arguments to pass to the class instance constructor
    --- @return ClassInstance
    function definition:new(...) return self:create_instance(...) end

    --- Gets the name assigned to this class definition
    --- @return string
    function definition:nameof() return self.__name end

    --- Whether this class definition is the same as or inherits from another class definition
    --- @param klass ClassDefinition  The class definition to check
    --- @return boolean
    function definition:instanceof(klass) return trace.scall(__instanceof, self, klass) end

    setmetatable(
        definition,
        {
            __index = trace.wrap(
                --- @param self ClassDefinition
                --- @param key string
                --- @return any
                function(self, key)
                    if __is_readonly_field(self, key) then
                        -- Field must be defined on this definition, so just access it directly
                        return rawget(self, key)
                    else
                        -- Resolve the field using base classes
                        return __get_field(self, key)
                    end
                end
            )
        }
    )

    -- Wrap the definition in a proxy to handle field assignment with inheritance and protections
    --- @type ClassDefinition
    return __create_oop_proxy(
        -- klass
        definition,
        -- __newindex
        function(target, key, value)
            if __is_readonly_field(target, key) then
                error("Field '" .. key .. "' on class definition '" .. target:nameof() .. "' is read-only and cannot be modified.", 3)
            else
                __assign_field(target, key, value)
            end
        end
    )
end

return {
    --- Defines a table representing an object-oriented class definition.
    --- @param name string  The identifier for this class definition.
    --- @param base ClassDefinition?  An optional base class to inherit from
    --- @return ClassDefinition
    class = function(name, base) return trace.scall(class, name, base) end,
    --- Returns whether the given class inherits from another class (or is the same class)
    --- @param klass Classlike  The class-like object to check
    --- @param other ClassDefinition  The class to check against
    --- @return boolean
    instanceof = function(klass, other) return trace.scall(__instanceof, klass, other) end
}