-- src/map.lua: blocked flags for any tile, read from the packed map modules (one per block of 16 x 16
-- mapsquares, loaded on first use), with instance tiles mapped back to their source mapsquare.
local M = {}

local BLOCK = 16
local ALIAS = "#"
local TILES_PER_SQUARE = 64
local CHUNK = 8
local VALUE_BASE = 48
local BACKSLASH_STAND_IN = 126
local BACKSLASH_VALUE = 44
local DIGIT_BASE = 97
local DIGIT_RADIX = 26

M.EDGE_N = 1
M.EDGE_S = 2
M.EDGE_E = 4
M.EDGE_W = 8
M.FULL = 16
M.SOLID = 32
M.BLOCKED = M.FULL | M.SOLID

local blocks = {}
local planes = {}
local chunkSources = {}

local function decode(text)
    local out, n = {}, 0
    local i, len = 1, #text
    while i <= len do
        local value = text:byte(i)
        i = i + 1
        local count, digits = 0, false
        while i <= len do
            local d = text:byte(i)
            if d < DIGIT_BASE or d >= DIGIT_BASE + DIGIT_RADIX then break end
            count = count * DIGIT_RADIX + (d - DIGIT_BASE)
            digits = true
            i = i + 1
        end
        n = n + 1
        out[n] = digits and string.rep(string.char(value), count) or string.char(value)
    end
    return table.concat(out)
end

local function block(bx, bz)
    local key = bx .. "_" .. bz
    local found = blocks[key]
    if found ~= nil then return found or nil end
    local ok, module = pcall(require, "src/map/b" .. key)
    if not ok or type(module) ~= "table" then module = false end
    blocks[key] = module
    return module or nil
end

local function plane(level, msx, msz)
    local key = msx .. "_" .. msz .. "_" .. level
    local found = planes[key]
    if found ~= nil then return found or nil end
    local text = nil
    local data = block(msx // BLOCK, msz // BLOCK)
    if data ~= nil then text = data[key] end
    if type(text) == "string" and text:sub(1, 1) == ALIAS then text = data[text:sub(2)] end
    local decoded = false
    if type(text) == "string" then decoded = decode(text) end
    planes[key] = decoded
    return decoded or nil
end

function M.flagsAt(level, x, z)
    if x < 0 or z < 0 then return M.FULL end
    local tiles = plane(level, x // TILES_PER_SQUARE, z // TILES_PER_SQUARE)
    if tiles == nil then return 0 end
    local byte = tiles:byte((x % TILES_PER_SQUARE) * TILES_PER_SQUARE + (z % TILES_PER_SQUARE) + 1)
    if byte == BACKSLASH_STAND_IN then return BACKSLASH_VALUE end
    return byte - VALUE_BASE
end

function M.sourceTile(level, x, z)
    local key = level .. ":" .. (x // CHUNK) .. ":" .. (z // CHUNK)
    local source = chunkSources[key]
    if source == nil then
        local ok, coord = pcall(function()
            return World.GetRegionSourceForCoordGrid(CoordGrid.new(level, x // TILES_PER_SQUARE,
                z // TILES_PER_SQUARE, x % TILES_PER_SQUARE, z % TILES_PER_SQUARE))
        end)
        if ok and coord ~= nil then
            source = { level = coord.level, x = coord.x, z = coord.z }
        else
            source = false
        end
        chunkSources[key] = source
    end
    if not source then return level, x, z end
    return source.level, source.x + x % CHUNK, source.z + z % CHUNK
end

function M.flags(level, x, z, inInstance)
    if inInstance then
        local sl, sx, sz = M.sourceTile(level, x, z)
        return M.flagsAt(sl, sx, sz)
    end
    return M.flagsAt(level, x, z)
end

function M.forgetInstance()
    chunkSources = {}
end

function M.loadedCounts()
    local b, p = 0, 0
    for _, v in pairs(blocks) do if v then b = b + 1 end end
    for _, v in pairs(planes) do if v then p = p + 1 end end
    return b, p
end

return M
