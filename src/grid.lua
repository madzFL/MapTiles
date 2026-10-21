-- src/grid.lua: builds the lattice, object fills, wall edges and mapsquare borders around the player as four
-- ShapeList instances, from the game's ground heights and the packed map, all drawn inside the scene with the
-- game's depth; terrain-blocked tiles (water, cliffs) simply end the lattice. Every tile owns its four
-- corners, sampled just inside its edges, so a tile whose surface steps away from its neighbour (a bridge
-- deck beside water) keeps its own height.
local Map = require("src/map")

local M = {}

local TILE = 512
local HALF_TILE = TILE // 2
local INSET = 1
local LIFT = 20.0
local FILL_DROP = 4.0
local STEP_TOLERANCE = 1.0
local LATTICE_NAME = "tilegrid.lattice"
local BLOCKED_NAME = "tilegrid.blocked"
local WALLS_NAME = "tilegrid.walls"
local REGIONS_NAME = "tilegrid.regions"
local MAPSQUARE = 64
local LATTICE_WIDTH = 1.5
local WALL_WIDTH = 4.0
local REGION_WIDTH = 3.0
local LATTICE_RGBA = 0xFFFFFF66
local BLOCKED_RGBA = 0x1A0A1A8C
local WALL_RGBA = 0xFF5050FF
local REGION_RGBA = 0xFFB400FF
local WHITE = 0xFFFFFFFF
local REFRESH_TICKS = 100
local HEIGHT_CACHE_MAX = 6000

local instances = {}
local lastKey = nil
local lastTick = -REFRESH_TICKS
local missingHeights = false
local heightCache = {}
local heightCacheSize = 0

local function instance(name)
    local found = instances[name]
    if found ~= nil then return found end
    pcall(function()
        local existing = ShapeList.GetInstance(name)
        if existing ~= nil and existing.isValid ~= false then found = existing end
    end)
    if found == nil then found = ShapeList.CreateInstance(name) end
    instances[name] = found
    return found
end

local function groundHeight(level, x, z)
    local ok, height, available = pcall(World.GetGroundHeight, level, x, z)
    if ok and available and type(height) == "number" then return height end
    return nil
end

local function tileHeights(level, x, z)
    local key = level .. ":" .. x .. ":" .. z
    local found = heightCache[key]
    if found ~= nil then return found or nil end
    local x0, z0 = x * TILE + INSET, z * TILE + INSET
    local x1, z1 = (x + 1) * TILE - INSET, (z + 1) * TILE - INSET
    local sw, se, ne, nw = groundHeight(level, x0, z0), groundHeight(level, x1, z0), groundHeight(level, x1, z1),
        groundHeight(level, x0, z1)
    local result = false
    if sw and se and ne and nw then result = { sw, se, ne, nw } end
    if heightCacheSize >= HEIGHT_CACHE_MAX then
        heightCache, heightCacheSize = {}, 0
    end
    heightCache[key] = result
    heightCacheSize = heightCacheSize + 1
    return result or nil
end

local function playerTile()
    local ok, coord = pcall(function()
        if not Player.IsAvailable() then return nil end
        local me = Player.GetEntity()
        if me == nil or not me.isValid then return nil end
        return me.coordGrid
    end)
    if ok and coord ~= nil then return coord.level, coord.x, coord.z end
    return nil
end

local function inInstance()
    local ok, region = pcall(World.IsRegion)
    return ok and region == true
end

local function emptyShape()
    return { positions = {}, rgba = {}, tris = {}, lines = {} }
end

local function toShapeData(parts)
    local shape = ShapeData.new()
    shape.positions = parts.positions
    shape.rgba = parts.rgba
    shape.tris = parts.tris
    shape.lines = parts.lines
    return shape
end

local function show(name, parts, anchor, width)
    local inst = instance(name)
    if not inst:SetShapeData(toShapeData(parts)) then
        print(string.format("[Tile Grid] %s refused: %d vertices, %d line indices, %d triangle indices",
            name, #parts.positions, #parts.lines, #parts.tris))
        return false
    end
    inst.translation = anchor
    inst.lineWidth = width
    inst.ignoreDepth = false
    inst.colour = WHITE
    inst.visible = true
    return true
end

local function hide(name)
    local inst = instances[name]
    if inst ~= nil then pcall(function() inst.visible = false end) end
end

local function build(settings, level, px, pz)
    local radius = settings.radius
    local span = 2 * radius + 1
    local minX, minZ = px - radius, pz - radius
    local instanced = inInstance()
    local anchorHeight = groundHeight(level, px * TILE + HALF_TILE, pz * TILE + HALF_TILE)
    if anchorHeight == nil then return nil end
    local anchor = Vector3.new(px * TILE + HALF_TILE, anchorHeight, pz * TILE + HALF_TILE)
    missingHeights = false
    local shapes = { lattice = emptyShape(), blocked = emptyShape(), walls = emptyShape(), regions = emptyShape() }
    local colours = { lattice = LATTICE_RGBA, blocked = BLOCKED_RGBA, walls = WALL_RGBA, regions = REGION_RGBA }
    local flags, heights, firstVertex = {}, {}, {}
    local count = 0
    for i = 0, span - 1 do
        for j = 0, span - 1 do
            local at = i * span + j
            flags[at] = Map.flags(level, minX + i, minZ + j, instanced)
            local h = tileHeights(level, minX + i, minZ + j)
            heights[at] = h
            if h == nil then
                missingHeights = true
            else
                firstVertex[at] = count
                local x0, z0 = (minX + i) * TILE - anchor.x, (minZ + j) * TILE - anchor.z
                local corners = { { x0, h[1], z0 }, { x0 + TILE, h[2], z0 }, { x0 + TILE, h[3], z0 + TILE }, { x0, h[4], z0 + TILE } }
                for c = 1, 4 do
                    local position = Vector3.new(corners[c][1], corners[c][2] + LIFT - anchorHeight, corners[c][3])
                    for name, shape in pairs(shapes) do
                        shape.positions[count + c] = position
                        shape.rgba[count + c] = colours[name]
                    end
                end
                count = count + 4
            end
        end
    end
    local function shown(i, j)
        if i < 0 or j < 0 or i >= span or j >= span then return false end
        return flags[i * span + j] & Map.BLOCKED == 0
    end
    local function stepsFrom(i, j, ni, nj, a, b, na, nb)
        local h, nh = heights[i * span + j], heights[ni * span + nj]
        if nh == nil then return true end
        return math.abs(h[a] - nh[na]) > STEP_TOLERANCE or math.abs(h[b] - nh[nb]) > STEP_TOLERANCE
    end
    local function line(shape, a, b)
        local n = #shape.lines
        shape.lines[n + 1] = a
        shape.lines[n + 2] = b
    end
    local function quad(shape, sw, se, ne, nw)
        local n = #shape.tris
        shape.tris[n + 1], shape.tris[n + 2], shape.tris[n + 3] = sw, se, ne
        shape.tris[n + 4], shape.tris[n + 5], shape.tris[n + 6] = sw, ne, nw
    end
    for i = 0, span - 1 do
        for j = 0, span - 1 do
            local at = i * span + j
            local base = firstVertex[at]
            if base ~= nil then
                local f = flags[at]
                local sw, se, ne, nw = base, base + 1, base + 2, base + 3
                local full = f & Map.BLOCKED ~= 0
                if settings.blocked and f & Map.SOLID ~= 0 then
                    quad(shapes.blocked, sw, se, ne, nw)
                    line(shapes.lattice, sw, se)
                    line(shapes.lattice, se, ne)
                    line(shapes.lattice, ne, nw)
                    line(shapes.lattice, nw, sw)
                end
                if settings.lattice and not full then
                    line(shapes.lattice, sw, se)
                    line(shapes.lattice, sw, nw)
                    if not shown(i + 1, j) or stepsFrom(i, j, i + 1, j, 2, 3, 1, 4) then line(shapes.lattice, se, ne) end
                    if not shown(i, j + 1) or stepsFrom(i, j, i, j + 1, 4, 3, 1, 2) then line(shapes.lattice, nw, ne) end
                end
                if settings.walls then
                    if f & Map.EDGE_S ~= 0 then line(shapes.walls, sw, se) end
                    if f & Map.EDGE_N ~= 0 then line(shapes.walls, nw, ne) end
                    if f & Map.EDGE_W ~= 0 then line(shapes.walls, sw, nw) end
                    if f & Map.EDGE_E ~= 0 then line(shapes.walls, se, ne) end
                end
                if settings.regions then
                    if (minX + i) % MAPSQUARE == 0 then line(shapes.regions, sw, nw) end
                    if (minZ + j) % MAPSQUARE == 0 then line(shapes.regions, sw, se) end
                end
            end
        end
    end
    shapes.anchor = anchor
    return shapes
end

function M.clear()
    for _, name in ipairs({ LATTICE_NAME, BLOCKED_NAME, WALLS_NAME, REGIONS_NAME }) do hide(name) end
    lastKey = nil
end

function M.destroy()
    for name, inst in pairs(instances) do
        pcall(function() inst.visible = false end)
        pcall(function() inst:Destroy() end)
        instances[name] = nil
    end
    lastKey = nil
end

function M.update(settings, tick, force)
    if not settings.enabled then
        if lastKey ~= nil then M.clear() end
        return
    end
    local level, px, pz = playerTile()
    if level == nil then
        if lastKey ~= nil then M.clear() end
        return
    end
    local key = string.format("%d:%d:%d:%d:%s:%s:%s:%s", level, px, pz, settings.radius,
        tostring(settings.lattice), tostring(settings.blocked), tostring(settings.walls), tostring(settings.regions))
    local stale = missingHeights and tick - lastTick >= REFRESH_TICKS
    if key == lastKey and not force and not stale then return end
    if stale or force then
        heightCache, heightCacheSize = {}, 0
    end
    local built = build(settings, level, px, pz)
    if built == nil then return end
    lastKey, lastTick = key, tick
    local fillAnchor = Vector3.new(built.anchor.x, built.anchor.y - FILL_DROP, built.anchor.z)
    if #built.lattice.lines > 0 then show(LATTICE_NAME, built.lattice, built.anchor, LATTICE_WIDTH) else hide(LATTICE_NAME) end
    if #built.blocked.tris > 0 then show(BLOCKED_NAME, built.blocked, fillAnchor, LATTICE_WIDTH) else hide(BLOCKED_NAME) end
    if #built.walls.lines > 0 then show(WALLS_NAME, built.walls, built.anchor, WALL_WIDTH) else hide(WALLS_NAME) end
    if #built.regions.lines > 0 then show(REGIONS_NAME, built.regions, built.anchor, REGION_WIDTH) else hide(REGIONS_NAME) end
end

return M
