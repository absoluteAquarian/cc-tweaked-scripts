-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/installer.lua

local REPOSITORY = "https://api.github.com/repos/absoluteAquarian/cc-tweaked-scripts/contents/"

local function contains(str, text, plain)
    return string.find(str, text, 1, plain or true) ~= nil
end

local function ends_with(str, text)
    return text == "" or str:sub(-#text) == text
end

local function load_files(root, subroot)
    local path = REPOSITORY .. "/" .. root
    if subroot then
        path = path .. "/" .. subroot
    end
    local json = http.get(path).readAll()

    if not json then
        error("Could not connect to " .. path)
        return nil
    end

    local files = textutils.unserialiseJSON(json)
    local result = {}

    for _, file in pairs(files) do
        local type = file['type']
        local name = file['name']
        -- If the "file" is a Lua file, add it to the result
        if type == 'file' and ends_with(name, '.lua') then
            table.insert(result, {name = name, url = file['download_url']})
        -- Otherwise, if it's a directory, recursively load files from it
        elseif type == 'dir' then
            local subsubroot = subroot and (subroot .. "/" .. name) or name
            local subfiles = load_files(root, subsubroot)

            if subfiles then
                for _, subfile in pairs(subfiles) do
                    subfile.name = subsubroot .. "/" .. subfile.name  -- Prepend the directory name
                    table.insert(result, subfile)
                end
            end
        end
    end

    return result
end

if not http.get(REPOSITORY) then
    error("Could not connect to " .. REPOSITORY)
end

local available = load_files("programs")
local util = load_files("util")

if not available or not util then
    error("Failed to load file list from repository")
end

print("Available Scripts (type number to download):")

local options = {}

for index, script in ipairs(available) do
    print(index .. ') ' .. script['name'])
    table.insert(options, index)
end

local index = tonumber(read(nil, options))
local selection = available[index]

print("Target directory: ")

local directory = read()

if not fs.exists(directory) then
    fs.makeDir(directory)
end

local program = selection['name']

shell.run("wget", selection['url'], directory .. "/" .. program)

-- Check for utility files and download them if they don't exist
for _, file in pairs(util) do
    local name = file['name']
    local path = directory .. "/util/" .. name

    if not fs.exists(path) then
        print("Downloading utility file: " .. name)
        shell.run("wget", file['url'], path)
    end
end

print("Script has been downloaded: " .. program)