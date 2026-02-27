local completion = require "cc.completion"

local config = require "lib.config"
local R_string = require "lib.string"
local R_table = require "lib.table"

local function print_launcher_actions()
    print("Usage: launcher <action>")
    print("  run - Executes a chosen program")
    print("  config - Opens the config file for a chosen program")
    print()
end

print()

if #arg ~= 1 then
    print_launcher_actions()
    print()
    return
end

local action = arg[1]

--- @type string
local directory = fs.getDir(shell.getRunningProgram())
if directory == "" then directory = "." end

local programs = fs.list(directory) --[[@as string[]=]]

R_table.remove_values(programs, "installer.lua", "launcher.lua", "lib", config.DIRECTORY)
R_table.remove_values_where(programs, function(file) return not R_string.ends_with(file, ".lua") end)
R_table.transform_values(programs, function(file) return file:sub(1, -5) end)

if #programs == 0 then
    print("No programs were installed, aborting")
    return
end

if action == "config" then
    R_table.remove_values_where(programs, function(file) return not fs.exists(directory .. "/" .. config.get_relative_path(file)) end)

    if #programs == 0 then
        print("No programs with configs were installed, aborting")
        return
    end
end

print("Choose a program:")
for _, file in ipairs(programs) do
    print("  " .. file)
end
print()
write("? ")

local program = read(nil, nil, function(text) return completion.choice(text, programs) end)

if not R_table.has_value(programs, program) then
    error("Unknown program")
end

if action == "run" then
    local pid = shell.openTab(directory .. "/" .. program .. ".lua")
    multishell.setTitle(pid, program)
    multishell.setFocus(pid)
elseif action == "config" then
    local path = directory .. "/" .. config.get_relative_path(program)
    if not fs.exists(path) then
        print()
        print("No config file found for: " .. program)
        print()
        return
    end

    local pid = shell.openTab("edit", config)
    multishell.setTitle(pid, program .. " [config]")
    multishell.setFocus(pid)
else
    print_launcher_actions()
end

print()