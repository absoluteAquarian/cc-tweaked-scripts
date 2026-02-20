local completion = require "cc.completion"

local R_table = require "lib.table"

local directory = fs.getDir(shell.getRunningProgram())

local programs = fs.list(directory) --[[@as string[]=]]

R_table.remove_values(programs, "launcher.lua", "lib")

if #programs == 0 then
    print("No programs were installed, aborting")
    return
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

local pid = shell.openTab(directory .. "/" .. program)
multishell.setTitle(pid, program)
multishell.setFocus(pid)