-- This file serves as a reference for common functions for safeguarding against function overrides

return {
    -- Base lua functions

    ipairs = ipairs,
    next = next,
    pairs = pairs,
    type = type,

    -- Lua library functions

    bit32 = {
        bor = bit32.bor,
        btest = bit32.btest,
        bxor = bit32.bxor,
        lshift = bit32.lshift,
    },

    debug = {
        getmetatable = debug.getmetatable,
        setmetatable = debug.setmetatable,
    },

    math = {
        abs = math.abs,
        ceil = math.ceil,
        floor = math.floor,
        huge = math.huge,
        max = math.max,
        min = math.min,
        pow = math.pow,
    },

    string = {
        byte = string.byte,
        char = string.char,
        find = string.find,
        gsub = string.gsub,
        rep = string.rep,
        reverse = string.reverse,
        sub = string.sub,
    },

    table = {
        concat = table.concat,
        insert = table.insert,
        pack = table.pack,
        remove = table.remove,
        unpack = table.unpack,
    },

    -- ComputerCraft functions

    colors = {
        --- @type fun(color: number) : string
        toBlit = colors.toBlit,
        --- @type fun(blit: string) : number
        fromBlit = colors.fromBlit,
    },

    fs = {
        --- @type fun(path: string) : boolean
        isDir = fs.isDir,
        --- @type fun(path: string) : string[]
        list = fs.list,
    },
}