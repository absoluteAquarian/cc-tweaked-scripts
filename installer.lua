-- Based on: https://github.com/Poeschl/computercraft-scripts/blob/main/installer.lua

local REPOSITORY = "https://api.github.com/repos/absoluteAquarian/cc-tweaked-scripts/contents/"

local function contains(str, text, plain)
    return string.find(str, text, 1, plain or true) ~= nil
end

local function ends_with(str, text)
    return text == "" or str:sub(-#text) == text
end

local json = http.get(REPOSITORY).readAll()

if not json then
    error("Could not connect to " .. REPOSITORY)
end

local files = textutils.unserialiseJSON(json)

local available = {}
local util = {}

for _, file in pairs(files) do
    if file['type'] == 'file' and ends_with(file['name'], '.lua') then
        local download = file['download_url']
        
        local target

        if contains(file['name'], "/util/") then
            target = util
        elseif contains(file['name'], "/programs/") then
            target = available
        else
            goto skip
        end

        table.insert(target, {name = file['name'], url = download})
    end

    ::skip::
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