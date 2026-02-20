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
local __HttpResponse = nil

--- @class MetaTable
--- @field programs MetaFile[]
--- @field lib MetaFile[]
--- @field __lookup_programs { [string]: MetaFile }
--- @field __lookup_libs { [string]: MetaFile }
--- @field __versions VersionFile
local __MetaTable = nil

--- @class MetaFile
--- @field name string
--- @field version integer
--- @field url string
--- @field install string
--- @field deps string[]
local __MetaFile = nil

--- @alias VersionFile { [string]: integer }

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
    handle.write(textutils.serialise(file, { compact = true, allow_repetitions = false }))
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
    local seen = {}

    --- @param current string
    local function visit(current)
        if seen[current] then return end
        seen[current] = true

        local deps = get_dependencies(current, meta)
        for _, dep in pairs(deps) do
            visit(dep)
        end
    end

    visit(name)

    local files = {}
    for dep, _ in pairs(seen) do
        table.insert(files, dep)
    end
    return files
end

--- @param name string
--- @param meta MetaTable
--- @param callback fun(file: MetaFile)
local function foreach_file_and_dependency(name, meta, callback)
    --- @type { [string]: boolean }
    local seen = {}

    --- @param current string
    local function visit(current)
        if seen[current] then return end
        seen[current] = true

        local file = meta.__lookup_programs[current] or meta.__lookup_libs[current]
        if file then callback(file) end

        local deps = get_dependencies(current, meta)
        for _, dep in pairs(deps) do
            visit(dep)
        end
    end

    visit(name)
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

local function download_program_and_dependencies(program, meta, directory)
    foreach_file_and_dependency(
        program,
        meta,
        function(file)
            if (not meta.__versions[file.install]) or meta.__versions[file.install] < file.version then
                -- Allow files from this repository to have shorter URLs
                local url = starts_with(file.url, "$REPO$") and file.url:gsub("%$REPO%$", REPOSITORY) or file.url
                download_and_overwrite(url, directory .. "/" .. file.install)
                meta.__versions[file.install] = file.version
            end
        end
    )
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

if #arg < 2 then
    print_installer_actions()
    return
end

local directory = arg[2]

if starts_with(directory, "rom") then
    error("Installer does not support installing to ROM")
end

directory = ends_with(directory, "/") and directory:sub(1, -2) or directory

local meta = load_meta()
meta.__versions = load_local_versions(directory)

if arg[1] == "clean" then
    --- @type { [string]: boolean }
    local keep = {}
    foreach_file_and_dependency(
        "launcher",
        meta,
        function(file) keep[file.install] = true end
    )

    for _, file in pairs(list_all(directory)) do
        if not keep[file] then
            fs.delete(directory .. "/" .. file)
            meta.__versions[file] = nil
        end
    end

    save_local_versions(directory, meta.__versions)

    print("Installed programs have been deleted.")
elseif arg[1] == "refresh" then
    --- @type string[]
    local installed = {}

    for _, file in pairs(fs.list(directory) --[[@as string[]=]]) do
        if ends_with(file, ".lua") then table.insert(installed, file) end
    end

    for _, program in ipairs(installed) do
        download_program_and_dependencies(program, meta, directory)
    end

    save_local_versions(directory, meta.__versions)

    print("Installed programs have been refreshed.")
elseif arg[1] == "install" then
    print("Choose a script:")

    local options = {}
    foreach_program(
        meta,
        function(file)
            print("  " .. file.name)
            table.insert(options, file.name)
        end
    )

    print()
    write("? ")

    local request = read(nil, nil, function(text) return completion.choice(text, options) end) or error("Unknown script")

    local selection
    for _, script in pairs(options) do
        if script.name == request then
            selection = script
            break
        end
    end
    if not selection then error("Unknown script") end

    print()

    download_program_and_dependencies(selection.name, meta, directory)

    -- Ensure that the launcher is also installed
    download_program_and_dependencies("launcher", meta, directory)

    save_local_versions(directory, meta.__versions)

    print()
    print("Script has been downloaded.")
    print("Programs can be launched via the launcher application in the same directory.")
    print()
else
    -- Unknown installer action
    print_installer_actions()
    return
end