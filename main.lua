-- Tile Grid: the walkable tile lattice, blocked tiles and wall edges around the player, drawn in the
-- world from packed map data (src/map) and the game's own ground heights. Ctrl+Shift+G toggles it;
-- the settings page holds the toggles and the radius.
local Map = require("src/map")
local Grid = require("src/grid")
local Settings = require("src/settings")

local EVENT_ID = "tilegrid"
local LOG_PREFIX = "[Tile Grid] "
local SAVE_TICKS = 50
local TOGGLE_KEY = "G"

local settings = Settings.load()
local dirtyAt = nil
local failed = {}

local function say(fmt, ...)
    print(LOG_PREFIX .. string.format(fmt, ...))
end

local function guarded(place, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not failed[place] then
            failed[place] = true
            say("FAIL %s: %s", place, tostring(err))
        end
    end
end

local function changed()
    dirtyAt = 0
    Grid.update(settings, 0, true)
end

Event.SettingsLayerReady.Subscribe(EVENT_ID, guarded("settings layer", function(ev)
    Settings.build(ev.component, settings, changed)
end))

Event.Logic.Subscribe(EVENT_ID, guarded("Logic", function(ev)
    local tick = ev.logicTick
    Grid.update(settings, tick, false)
    if dirtyAt ~= nil and tick - dirtyAt >= SAVE_TICKS then
        Settings.save(settings)
        dirtyAt = nil
    end
end))

Event.KeyDown.Subscribe(EVENT_ID, guarded("KeyDown", function(ev)
    if ev.isRepeat or not (Keyboard.IsControlDown() and Keyboard.IsShiftDown()) then return end
    if ev.gameKey ~= GameKey[TOGGLE_KEY] then return end
    settings.enabled = not settings.enabled
    Settings.refresh(settings)
    changed()
end))

Event.GameStateChanged.Subscribe(EVENT_ID, guarded("GameStateChanged", function(ev)
    if ev.newState ~= GameState.GAME then Grid.clear() end
    Map.forgetInstance()
end))

Event.RegionCreated.Subscribe(EVENT_ID, guarded("RegionCreated", function() Map.forgetInstance() end))
Event.RegionUpdated.Subscribe(EVENT_ID, guarded("RegionUpdated", function() Map.forgetInstance() end))

function PluginShutdown()
    for _, name in ipairs({ "SettingsLayerReady", "Logic", "KeyDown", "GameStateChanged", "RegionCreated", "RegionUpdated" }) do
        pcall(function() Event[name].Unsubscribe(EVENT_ID) end)
    end
    Grid.destroy()
    Settings.save(settings)
end

say("loaded 0.1.0, radius %d, %s", settings.radius, settings.enabled and "on" or "off")
