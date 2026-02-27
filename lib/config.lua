local class = require "lib.class"
local R_json = require "lib.json"

local DIRECTORY = "configs"
local EXTENSION = ".json"

--- Gets the relative path to the config file for a given program
--- @param program string  The name of the program to get the config path for
--- @return string path  The path to the config file for the given program
local function get_relative_path(program)
    return DIRECTORY .. "/" .. program .. EXTENSION
end

--- @param program string  The name of the program to load the config for
--- @return { [string]: any } config  The config for the given program, or an empty table if no config is found
local function load_config(program)
    local path = fs.getDir(shell.getRunningProgram()) .. "/" .. get_relative_path(program)
    if not fs.exists(path) then return {} end

    local handle = fs.open(path, "r")
    if not handle then return {} end

    local file = textutils.unserialiseJSON(handle.readAll(), { nbt_style = true, allow_repetitions = false })
    handle.close()
    return file or {}
end

--- @param program string  The name of the program to save the config for
--- @param config { [string]: any }  The config to save for the given program
local function save_config(program, config)
    local path = fs.getDir(shell.getRunningProgram()) .. "/" .. get_relative_path(program)
    if fs.exists(path) then fs.delete(path) end

    local json = textutils.serialiseJSON(config, { nbt_style = true, allow_repetitions = false })

    local handle = fs.open(path, "w")
    -- textutils.serializeJSON() returns a compacted JSON string, so it needs to be cleaned up before writing
    handle.write(R_json.prettify(json))
    handle.flush()
    handle.close()
end

--- @class ConfigTableEntry  A table with string keys
--- @field [string] any  The value of the config entry, indexed by the config key

--- @class ConfigFileDefinition : ClassDefinition
local ConfigFile = class.class("ConfigFile")

--- [override] Creates a new ConfigFile instance for the given program
--- @param program string  The name of the program this config file is for
function ConfigFile:new(program)
    --- @class ConfigFile : ClassInstance
    local instance = ConfigFile:create_instance(program)

    --- The name of the program this config file is for
    instance.program = program
    --- The raw contents of the config file
    instance.file = load_config(program)

    --- Reloads the config file from disk, discarding any unsaved changes
    function instance:reload()
        self.file = load_config(self.program)
    end

    --- Saves the config file to disk
    function instance:save()
        save_config(self.program, self.file)
    end

    --- Gets the config value for the given key as an integer, or nil if it doesn't exist or isn't an integer
    --- @param key string  The key of the config value to get
    function instance:getInt(key)
        local value = self.file[key]
        if type(value) == "number" then
            local floor = math.floor(value)
            if floor == value then return floor end
        end
        return nil
    end

    --- Gets the config value for the given key as a floating-point number, or nil if it doesn't exist or isn't a floating-point number
    --- @param key string  The key of the config value to get
    function instance:getNumber(key)
        local value = self.file[key]
        if type(value) == "number" then return value end
        return nil
    end

    --- Gets the config value for the given key as a string, or nil if it doesn't exist or isn't a string
    --- @param key string  The key of the config value to get
    function instance:getString(key)
        local value = self.file[key]
        if type(value) == "string" then return value end
        return nil
    end

    --- Gets the config value for the given key as a boolean, or nil if it doesn't exist or isn't a boolean
    --- @param key string  The key of the config value to get
    function instance:getBoolean(key)
        local value = self.file[key]
        if type(value) == "boolean" then return value end
        return nil
    end

    --- Gets the config value for the given key as a table, or nil if it doesn't exist or isn't a table
    --- @param key string  The key of the config value to get
    function instance:getTable(key)
        local value = self.file[key]
        if type(value) == "table" then return value end
        return nil
    end

    --- Sets the config value for the given key to an integer
    --- @param key string  The key of the config value to set
    --- @param value integer  The integer value
    function instance:setInt(key, value)
        self.file[key] = value
    end

    --- Sets the config value for the given key to a floating-point number
    --- @param key string  The key of the config value to set
    --- @param value number  The floating-point number value
    function instance:setNumber(key, value)
        self.file[key] = value
    end

    --- Sets the config value for the given key to a string
    --- @param key string  The key of the config value to set
    --- @param value string  The string value
    function instance:setString(key, value)
        self.file[key] = value
    end

    --- Sets the config value for the given key to a boolean
    --- @param key string  The key of the config value to set
    --- @param value boolean  The boolean value
    function instance:setBoolean(key, value)
        self.file[key] = value
    end

    --- Sets the config value for the given key to a table
    --- @param key string  The key of the config value to set
    --- @param value ConfigTableEntry  The table value
    function instance:setTable(key, value)
        self.file[key] = value
    end

    return instance
end

--- Loads a config file from disk
--- @param program string  The name of the program to load the config for
--- @return ConfigFile file  The loaded config file
local function unserialize(program)
    return ConfigFile:new(program)
end

--- Saves a config file to disk
--- @param file ConfigFile  The config file to save
local function serialize(file)
    file:save()
end

return {
    DIRECTORY = DIRECTORY,
    EXTENSION = EXTENSION,
    class = ConfigFile,
    get_relative_path = get_relative_path,
    unserialize = unserialize,
    serialize = serialize,
}