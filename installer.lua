-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/installer.lua

local REPOSITORY = "https://api.github.com/repos/absoluteAquarian/cc-tweaked-scripts/contents/"

--- @class GitHubFile
--- @field name string  The name of the file, used to determine where to save it locally
--- @field url string  The URL to download the file from
local GitHubFile = {}

--- @param str string
--- @param text string
--- @return boolean
local function ends_with(str, text)
    return text == "" or str:sub(-#text) == text
end

--- @param root string
--- @param subroot string?
--- @return GitHubFile[]?
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
    --- @type GitHubFile[]
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

--- @param url string
--- @param destination string
local function download_and_overwrite(url, destination)
    if fs.exists(destination) then fs.delete(destination) end
    shell.run("wget", url, destination)
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

print()
print("Target directory: ")

local directory = read()

print()

local program = selection['name']

download_and_overwrite(selection['url'], directory .. "/" .. program)

for _, file in pairs(util) do
    download_and_overwrite(file['url'], directory .. "/util/" .. file['name'])
end

print()
print("Script has been downloaded: " .. program)
print()