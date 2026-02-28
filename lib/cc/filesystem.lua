--- Returns a list of file paths for every file in the directory and its subdirectories
--- @param dir string  The absolute directory to list files from
--- @return string[] files
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

--- Returns a function that iterates over all files from the provided directory and its subdirectories, once per call
--- @param dir string  The absolute directory to list files from
--- @return fun(): string? iter
local function iterate_all_files(dir)
    local queue = { dir }
    local head = 1
    return function()
        ::next::
        if head > #queue then return nil end

        local current = queue[head]
        head = head + 1

        if fs.isDir(current) then
            -- Add the direct children of the directory to the queue
            local index = head
            for _, entry in pairs(fs.list(current) --[[@as string[]=]]) do
                table.insert(queue, index, current .. "/" .. entry)
                index = index + 1
            end

            -- Keep jumping back until a file is found
            goto next
        else
            -- The path is a file, yield it
            return current
        end
    end
end

--- Returns a function that iterates over the entries in a directory, but not its subdirectories, once per call
--- @param dir string  The absolute directory to list entries from
--- @return fun(): string? iter
local function iterate_directory(dir)
    local entries = fs.list(dir) --[[@as string[]=]]
    local index = 1
    return function()
        if index > #entries then return nil end
        local entry = entries[index]
        index = index + 1
        return dir .. "/" .. entry
    end
end

return {
    list_all = list_all,
    iterate_all_files = iterate_all_files,
    iterate_directory = iterate_directory
}