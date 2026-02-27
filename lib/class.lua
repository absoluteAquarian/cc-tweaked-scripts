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

--- @param proxy Classlike
--- @return Classlike
local function __resolve_proxy(proxy)
    local target = rawget(proxy, "__proxy_target")
    return target ~= nil and target or proxy
end

--- Returns whether the given class-like object defines the given field directly on itself, without checking base classes
--- @param klass Classlike  The class-like object to check
--- @param field string  The name of the field to check for
--- @return boolean
local function __has_field_directly(klass, field)
    return rawget(__resolve_proxy(klass), "__fields")[field] == true
end

--- @param klass Classlike  The class-like object to define the field on
--- @param field string  The name of the field to define
local function __define_field(klass, field)
    rawget(__resolve_proxy(klass), "__fields")[field] = true
end

--- Iterates through the class-like object's hierarchy to find a class-like object that satisfies the given predicate, and returns that object or nil if no such object exists
--- @param klass Classlike  The class-like object to start searching from
--- @param predicate fun(klass: Classlike) : boolean  Whether the given class-like object satisfies the condition to be returned
--- @return Classlike?
local function __find_in_hierarchy(klass, predicate)
    local proxy_target = __resolve_proxy(klass)

    if predicate(proxy_target) then
        return klass
    else
        local base = rawget(proxy_target, "base")
        while base do
            proxy_target = __resolve_proxy(base)
            if predicate(proxy_target) then return base end
            base = rawget(proxy_target, "base")
        end
    end
end

--- Iterates through the class-like object's hierarchy to perform the given action on each class-like object
--- @param klass Classlike  The class-like object to start iterating from
--- @param action fun(klass: Classlike)  The action to perform on each class-like object in the hierarchy
--- @param include_self boolean  Whether to include the given class-like object in the iteration
local function __foreach_in_hierarchy(klass, action, include_self)
    local proxy_target = __resolve_proxy(klass)

    if include_self then action(proxy_target) end

    local base = rawget(proxy_target, "base")
    while base do
        proxy_target = __resolve_proxy(base)
        action(proxy_target)
        base = rawget(proxy_target, "base")
    end
end

--- Attempts to find the class-like object that defines the given field, or returns nil if no such object exists
--- @param klass Classlike  The class-like object to start searching from
--- @param field string  The name of the field to find
--- @return Classlike?
local function __find_defining_class(klass, field)
    return __find_in_hierarchy(klass, function(c) return __has_field_directly(c, field) end)
end

--- Returns whether the class-like object defines the given field, either directly or through a base class
--- @param klass Classlike  The class-like object to check
--- @param field string  The name of the field to check for
--- @return boolean
local function __has_field(klass, field)
    return __find_defining_class(klass, field) ~= nil
end

--- Returns whether the given field is read-only on the given class-like object
--- @param klass Classlike  The class-like object to check
--- @param field string  The name of the field to check
--- @return boolean
local function __is_readonly_field(klass, field)
    return __resolve_proxy(klass).__fields.readonly[field] == true
end

--- Tags a field on a class-like object as read-only or not, for use with internal assignments of readonly fields after instance creation
--- @param klass Classlike  The class-like object to tag the field on
--- @param field string  The name of the field to tag
--- @param is_readonly boolean  Whether the field should be tagged as read-only or not
local function __tag_field_readonly(klass, field, is_readonly)
    local proxy_target = __resolve_proxy(klass)

    if not __has_field(proxy_target, field) then
        error("Field '" .. field .. "' is not defined on class " .. proxy_target.__type .. " '" .. proxy_target.class:nameof() .. "'", 2)
    else
        proxy_target.__fields.readonly[field] = is_readonly
    end
end

--- Attempts to assign a value to a field on a class-like object, checking base classes if necessary
--- @param klass Classlike  The class-like object to assign the field on
--- @param field string  The name of the field to assign
--- @param value any  The value to assign to the field
local function __assign_field(klass, field, value)
    if type(value) == "function" then value = trace.wrap(value) end

    local defining_class = __find_defining_class(klass, field)
    if defining_class then
        -- The field is defined either on the class or a base class, so modify it directly
        rawset(__resolve_proxy(defining_class), field, value)
    else
        -- The field is not defined on any base class nor the original object, so add it to the original object
        __define_field(klass, field)
        rawset(__resolve_proxy(klass), field, value)
    end
end

--- Attempts to read a field from a class-like object, checking base classes if necessary
--- @param obj Classlike  The object to read the field from
--- @param field string  The name of the field to read
--- @return any
local function __get_field(obj, field)
    local defining_class = __find_defining_class(obj, field)
    return defining_class and rawget(__resolve_proxy(defining_class), field) or nil
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
    return (base and __instanceof(base, other)) == true
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

--- @param klass Classlike  The class-like object to create a proxy for
--- @param newindex fun(target: Classlike, key: any, value: any)  The __newindex metamethod for the proxy
--- @return ObjectProxy
local function __create_oop_proxy(klass, newindex)
    --- @type table
    return setmetatable(
        --- @private
        --- @class ObjectProxy : Classlike  A proxy for a class-like object
        --- @field __proxy_target Classlike  The class-like object this is a proxy for
        {
            __proxy_target = klass
        },
        {
            __index = trace.wrap(function(self, key) return __resolve_proxy(self)[key] end),
            __newindex = trace.wrap(function(self, key, value) newindex(__resolve_proxy(self), key, value) end),
            __pairs = trace.wrap(function(self) return pairs(__resolve_proxy(self)) end),
            __ipairs = trace.wrap(function(self) return R_table.create_ipairs(__resolve_proxy(self)) end),
            __len = trace.wrap(function(self) return #__resolve_proxy(self) end),
            __tostring = trace.wrap(function(self) return tostring(__resolve_proxy(self)) end),
            __call = trace.wrap(function(self, ...) return __resolve_proxy(self)(...) end)
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
            "instanceof"
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
                    if __is_readonly_field(self, key) then
                        -- Field must be defined on this instance, so just access it directly
                        -- This allows both class definitions and class instances to have the same common read-only fields
                        return rawget(self, key)
                    elseif __has_field(rawget(self, "class"), key) then
                        error("Field '" .. key .. "' is defined on class definition '" .. rawget(self, "class"):nameof() .. "' and cannot be accessed through a class instance", 2)
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
    definition.this = definition

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
                "castclass",
                "class",
                "instanceof",
                "this"
            ),
            --- @private
            --- The classification of this class-like object
            __type = "instance",
            --- @type ClassInstance?  The class instance of the class definition's base class definition
            base = nil,
            class = self
        }

        --- A reference to the actual class instance, even when accessed through a base class instance
        instance.this = instance

        if self.base then
            instance.base = self.base:new(...)

            -- Ensure that the "this" field on all base class instances in the hierarchy points to this instance, to allow upcasting to work properly
            __foreach_in_hierarchy(
                instance.base,
                --- @param c ClassInstance
                function(c)
                    __tag_field_readonly(c, "this", false)
                    rawset(c, "this", instance)
                    __tag_field_readonly(c, "this", true)
                end,
                true
            )
        end

        --- Retrieves the class instance from this class instance's hierarchy whose class field matches the given class definition, or returns nil if no such instance exists<br/>
        --- If this class instance is a base class instance, upcasting to deriving classes is possible
        --- @param klass ClassDefinition  The class definition to look for
        --- @return ClassInstance?
        function instance:castclass(klass)
            --- @type ClassInstance?
            return trace.scall(__find_in_hierarchy, rawget(self, "this"), function(c) return rawget(__resolve_proxy(c), "class") == klass end)
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