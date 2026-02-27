-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/installer.lua

local completion = require "cc.completion"

local REPOSITORY = "https://raw.githubusercontent.com/absoluteAquarian/cc-tweaked-scripts/refs/heads/main/"

--- @class HttpResponse
--- (From fs:ReadHandle)
--- @field read fun(count: number?) : number|string?
--- @field readAll fun() : string?
--- @field readLine fun(withTrailing: boolean?) : string?
--- @field seek fun(whence: string?, offset: number?) : number?, string?
--- @field close fun()
--- (Defines)
--- @field getResponseCode fun() : number, string
--- @field getResponseHeaders fun() : { [string]: string }

--- @class MetaTable
--- @field programs MetaFile[]
--- @field lib MetaFile[]
--- @field __lookup_programs MetaFileLookup
--- @field __lookup_libs MetaFileLookup
--- @field __versions VersionFile

--- @class MetaFile
--- @field name string
--- @field version integer
--- @field url string
--- @field install string
--- @field config string
--- @field deps string[]

--- @class MetaFileLookup
--- @field [string] MetaFile  The MetaFile with the given name, or nil if no such MetaFile exists

--- @class VersionFile
--- @field [string] integer  The version number for each installed file, indexed by the file path relative to the installation directory

--- @param str string
--- @param text string
--- @return boolean
local function starts_with(str, text)
    return text == "" or str:sub(1, #text) == text
end

--- @param str string
--- @param text string
--- @return boolean
local function ends_with(str, text)
    return text == "" or str:sub(-#text) == text
end

--- @param url string
--- @return table
local function get_json(url)
    local response = http.get(url) --[[@as HttpResponse?]]

    if not response then
        error("Could not connect to " .. url)
    end

    local json = response.readAll()
    response.close()

    local tbl, msg = textutils.unserialiseJSON(json)

    --- @cast tbl table?

    if not tbl then
        error("Failed to parse JSON: " .. msg)
    end

    return tbl
end

--- @param dir string
--- @return VersionFile
local function load_local_versions(dir)
    local path = dir .. "/.versions"
    if not fs.exists(path) then return {} end

    local handle = fs.open(path, "r")
    if not handle then return {} end

    local file = textutils.unserialise(handle.readAll())
    handle.close()
    return file or {}  --[[@as VersionFile]]
end

--- @param dir string
--- @param file VersionFile
local function save_local_versions(dir, file)
    local path = dir .. "/.versions"
    if fs.exists(path) then fs.delete(path) end

    local handle = fs.open(path, "w")
    handle.write(textutils.serialise(file, { compact = false, allow_repetitions = false }))
    handle.flush()
    handle.close()
end

--- @return MetaTable
local function load_meta()
    --- @type MetaTable
    local meta = get_json(REPOSITORY .. "meta.json")

    -- Populate the lookup tables
    meta.__lookup_programs = {}
    for _, program in pairs(meta.programs) do
        meta.__lookup_programs[program.name] = program
    end

    meta.__lookup_libs = {}
    for _, lib in pairs(meta.lib) do
        meta.__lookup_libs[lib.name] = lib
    end

    return meta
end

--- @param name string
--- @param meta MetaTable
--- @return string[]
local function get_dependencies(name, meta)
    --- @type { [string]: boolean }
    local visited = {}
    --- @type string[]
    local dependencies = {}

    --- @param current string
    local function visit(current)
        local file = meta.__lookup_programs[current] or meta.__lookup_libs[current]
        if not file then error("Unknown program or library: " .. current) end

        if visited[current] then return end
        visited[current] = true

        for _, dep in ipairs(file.deps) do
            if not visited[dep] then table.insert(dependencies, dep) end
            visit(dep)
        end
    end

    visit(name)

    return dependencies
end

--- @param name string
--- @param meta MetaTable
--- @param callback fun(file: MetaFile)
local function foreach_file_and_dependency(name, meta, callback)
    local function visit(current)
        local file = meta.__lookup_programs[current] or meta.__lookup_libs[current]
        if not file then error("Unknown program or library: " .. current) end
        callback(file)
    end

    visit(name)

    for _, dep in ipairs(get_dependencies(name, meta)) do
        visit(dep)
    end
end

--- @param meta MetaTable
--- @param callback fun(file: MetaFile)
local function foreach_program(meta, callback)
    for _, program in pairs(meta.programs) do
        callback(program)
    end
end

--- @param url string
--- @param destination string
local function download_and_overwrite(url, destination)
    if fs.exists(destination) then fs.delete(destination) end
    shell.run("wget", url, destination)
end

--- @param program string
--- @param meta MetaTable
--- @param directory string
local function download_program_and_dependencies(program, meta, directory)
    foreach_file_and_dependency(
        program,
        meta,
        function(file)
            if (not meta.__versions[file.install]) or meta.__versions[file.install] < file.version then
                -- Allow files from this repository to have shorter URLs
                local url = starts_with(file.url, "$REPO$/") and (REPOSITORY .. file.url:sub(8)) or file.url
                download_and_overwrite(url, directory .. "/" .. file.install)
                meta.__versions[file.install] = file.version
            end
        end
    )

    -- If the program has default settings, apply them if the config doesn't already exist
    local program_file = meta.__lookup_programs[program]
    if program_file and program_file.config and #program_file.config > 0 then
        local path = directory .. "/configs/" .. program_file.name .. ".tbl"
        if not fs.exists(path) then
            local handle = fs.open(path, "w")
            -- Ensure that the config has the standard format, no matter how it's defined in the meta
            handle.write(textutils.serialise(textutils.unserialise(program_file.config), { compact = false, allow_repetitions = false }))
            handle.flush()
            handle.close()
        end
    end
end

local function print_installer_actions()
    print("Usage: installer <action> <dir>")
    print("  clean   - Deletes all installed programs")
    print("  refresh - Re-downloads the files for all programs")
    print("  install - Installs a program")
end

--- Returns a list of file paths relative to the given directory for every file in the directory and its subdirectories.
--- @param dir string
--- @return string[]
local function list_all(dir)
    --- @type string[]
    local files = {}
    for _, entry in pairs(fs.list(dir) --[[@as string[]=]]) do
        local path = dir .. "/" .. entry
        if fs.isDir(path) then
            local subfiles = list_all(path)
            for _, subfile in ipairs(subfiles) do
                table.insert(files, entry .. "/" .. subfile)
            end
        else
            table.insert(files, entry)
        end
    end
    return files
end

---
---  Start of program logic
---
print()

if #arg ~= 2 then
    print_installer_actions()
    print()
    return
end

local action = arg[1]
local directory = arg[2]

if starts_with(directory, "rom") then
    error("Installer does not support installing to ROM")
end

if directory == "" then
    directory = "."
elseif ends_with(directory, "/") then
    directory = directory:sub(1, -2)
end

local meta = load_meta()
meta.__versions = load_local_versions(directory)

if action == "clean" then
    --- @type { [string]: boolean }
    local keep = {}
    foreach_file_and_dependency(
        "launcher",
        meta,
        function(file) keep[file.install] = true end
    )
    keep["installer.lua"] = true

    for _, file in pairs(list_all(directory)) do
        if not keep[file] then
            fs.delete(directory .. "/" .. file)
            meta.__versions[file] = nil
        end
    end

    save_local_versions(directory, meta.__versions)

    print()
    print("Installed programs have been deleted.")
elseif action == "refresh" then
    --- @type string[]
    local installed = {}

    for _, file in pairs(fs.list(directory) --[[@as string[]=]]) do
        if ends_with(file, ".lua") and file ~= "installer.lua" then
            table.insert(installed, file:sub(1, -5))
        end
    end

    -- Ensure that the launcher script is also installed
    if not fs.exists(directory .. "/launcher.lua") then table.insert(installed, "launcher") end

    for _, program in ipairs(installed) do
        download_program_and_dependencies(program, meta, directory)
    end

    save_local_versions(directory, meta.__versions)

    print()
    print("Installed programs have been refreshed.")
elseif action == "install" then
    print("Choose a script:")

    --- @type string[]
    local options = {}
    foreach_program(
        meta,
        function(file)
            if file.name == "launcher" or file.name == "startup" then return end  -- Don't show the launcher/startup in the list of options
            print("  " .. file.name)
            table.insert(options, file.name)
        end
    )

    print()
    write("? ")

    local request = read(nil, nil, function(text) return completion.choice(text, options) end) or error("Unknown script")

    local selection
    for _, script in ipairs(options) do
        if script == request then
            selection = script
            break
        end
    end
    if not selection then error("Unknown script") end

    print()

    download_program_and_dependencies(selection, meta, directory)

    -- Ensure that the launcher script is also installed
    download_program_and_dependencies("launcher", meta, directory)

    save_local_versions(directory, meta.__versions)

    print()
    print("Script has been downloaded.")
    print("Programs can be launched via the launcher application in the same directory.")
else
    -- Unknown installer action
    print_installer_actions()
end

print()