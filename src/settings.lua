-- src/settings.lua: the saved options (PersistentDB) and the settings page: four checks and the radius slider.
local M = {}

local DEFAULTS = { enabled = true, lattice = true, blocked = true, walls = true, regions = true, radius = 10 }
local CHECKS = { "enabled", "lattice", "blocked", "walls", "regions" }
local LEGEND = {
    "Legend: thin white lattice = walkable tile",
    "dark box with white outline = blocked by an object",
    "no lattice = water, cliff or other unwalkable terrain",
    "red line = wall edge, orange line = mapsquare border",
}
local RADIUS_MIN, RADIUS_MAX = 3, 12
local MARGIN = 12
local ROW = 30
local CHECK_WIDTH = 260
local BUTTON_SIZE = 20
local SLIDER_WIDTH = 260
local SLIDER_HEIGHT = 44
local SLIDER_GAP = 12
local NOTE_WIDTH = 520
local WHITE = 0xFFFFFFFF
local CHECK_STYLE = "CHECKBOX_DEFAULT_LEFT_ALIGNED"
local SLIDER_STYLE = "SLIDER_DEFAULT"
local FONT = nil
pcall(function() FONT = id.Font.MUSEO_SANS_15PT_REGULAR end)

local view = {}

local function styleText(text)
    if FONT ~= nil then text.font = FONT end
    text.rgba = WHITE
    text.isShadowed = true
end

local function applyStyle(comp, name)
    local ok, sheet = pcall(function() return id.StyleSheet[name] end)
    if ok and type(sheet) == "number" and sheet >= 0 then comp.stylesheetID = sheet end
end

local function clampRadius(value)
    return math.max(RADIUS_MIN, math.min(RADIUS_MAX, math.floor(value)))
end

function M.load()
    local s = {}
    for key, default in pairs(DEFAULTS) do
        local ok, value = pcall(function()
            if not PersistentDB:CheckExists(key) then return nil end
            if type(default) == "boolean" then return PersistentDB:GetBool(key) end
            return PersistentDB:GetInt(key)
        end)
        if ok and type(value) == type(default) then s[key] = value else s[key] = default end
    end
    s.radius = clampRadius(s.radius)
    return s
end

function M.save(s)
    pcall(function()
        for key, default in pairs(DEFAULTS) do
            if type(default) == "boolean" then PersistentDB:SetBool(key, s[key]) else PersistentDB:SetInt(key, s[key]) end
        end
    end)
end

local function addText(parent, y, content, width)
    local text = ui.Text.new(parent)
    text:SetPos(MARGIN, y)
    text:SetSize(width or NOTE_WIDTH, ROW)
    styleText(text)
    text.content = content
    return text
end

local function addCheck(parent, y, label, key, s, onChange)
    local check = ui.Check.new(parent)
    check:SetPos(MARGIN, y)
    check:SetSize(CHECK_WIDTH, ROW)
    applyStyle(check, CHECK_STYLE)
    check.label = label
    check.buttonSize = BUTTON_SIZE
    styleText(check.text)
    check.value = s[key]
    check:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
        local value = check.value == true
        if value == s[key] then return end
        s[key] = value
        onChange()
    end)
    view[key] = check
end

function M.build(parent, s, onChange)
    view = {}
    local y = MARGIN
    addText(parent, y, "Tile Grid")
    y = y + ROW
    addCheck(parent, y, "Enabled (Ctrl+Shift+G)", "enabled", s, onChange)
    y = y + ROW
    addCheck(parent, y, "Lattice over walkable tiles", "lattice", s, onChange)
    y = y + ROW
    addCheck(parent, y, "Fill tiles blocked by objects", "blocked", s, onChange)
    y = y + ROW
    addCheck(parent, y, "Wall edges", "walls", s, onChange)
    y = y + ROW
    addCheck(parent, y, "Mapsquare borders (64 x 64)", "regions", s, onChange)
    y = y + ROW
    local label = addText(parent, y, "Radius: " .. s.radius .. " tiles", SLIDER_WIDTH)
    y = y + ROW
    local slider = ui.Slider.new(parent)
    slider:SetPos(MARGIN, y)
    slider:SetSize(SLIDER_WIDTH, SLIDER_HEIGHT)
    applyStyle(slider, SLIDER_STYLE)
    slider:Setup(RADIUS_MIN, RADIUS_MAX, s.radius, 1, 1)
    styleText(slider.labelsText)
    slider:Subscribe(ui.Hook.ONSELECTIONCHANGED, function()
        local value = slider.value
        if type(value) ~= "number" then return end
        value = clampRadius(value)
        if value == s.radius then return end
        s.radius = value
        label.content = "Radius: " .. s.radius .. " tiles"
        onChange()
    end)
    view.radius = slider
    y = y + SLIDER_HEIGHT + SLIDER_GAP
    for _, note in ipairs(LEGEND) do
        addText(parent, y, note)
        y = y + ROW
    end
end

function M.refresh(s)
    for _, key in ipairs(CHECKS) do
        local check = view[key]
        if check ~= nil then pcall(function() check.value = s[key] end) end
    end
end

return M
