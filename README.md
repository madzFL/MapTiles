# Tile Grid

<img width="1665" height="837" alt="image" src="https://github.com/user-attachments/assets/9214fb4f-6e23-4f2e-a6e6-6132c8e33c77" />


A RuneScape client plugin (Lua) that draws the tile grid around your character in the world: a lattice over walkable tiles, a dark box on tiles blocked by objects, red lines on wall edges and orange lines on the 64 x 64 mapsquare borders. Water, cliffs and other unwalkable terrain simply end the lattice.

The grid follows you as you move, uses the game's own ground heights, and is drawn inside the scene, so it climbs stairs, follows bridge decks and is hidden by scenery and characters like the game's own markers.

## Install

From the plugin hub, or as a developer plugin: put this folder in your dev plugins directory, then `plugins_setpath <dir>` and `pon <folder name>` in the client console.

Requires nothing and asks for no permissions.

## Use

- Ctrl+Shift+G toggles the grid.
- The settings page has checks for the lattice, the object fills, wall edges and mapsquare borders, and the radius (3 to 12 tiles).

Legend: thin white lattice = walkable tile; dark box with a white outline = blocked by an object; no lattice = water, cliff or other unwalkable terrain; red line = wall edge; orange line = mapsquare border.

## Files

| File | Role |
|---|---|
| `plugin.json` | Manifest |
| `main.lua` | Events, keys, settings persistence |
| `src/grid.lua` | Builds the four shape layers from ground heights and the map data |
| `src/map.lua` | Loads map blocks on demand, decodes planes, answers tile flags, maps instance tiles to their source |
| `src/settings.lua` | Saved options and the settings page |
| `src/map/index.lua` | The list of map blocks shipped |
| `src/map/b<x>_<y>.lua` | Map data, one module per block of 16 x 16 mapsquares |

## Map data

The map modules are generated offline from the game cache and cover 5,210 mapsquares. Each module returns a table keyed `"<mapsquare x>_<mapsquare y>_<plane>"`. A value is a run-length string:

- one character per run, `chr(48 + value)`, where value is a bit set of N 1, S 2, E 4, W 8 (wall edges), 16 (unwalkable terrain) or 32 (blocked with an object standing on the tile); value 44 is written `~`;
- a run longer than one tile is followed by its length in base 26, `a` = 0 to `z` = 25, most significant digit first;
- an entry identical to an earlier entry of the same module is `#<that key>`.

Decoded, a plane is 4,096 characters indexed `(local x * 64) + local z + 1`. Planes with nothing set are left out, and a mapsquare absent from every module is fully walkable.

Lookups cost one string index after the one-time decode of a plane, and only the blocks around the player are loaded.
