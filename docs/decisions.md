# Decisions

Short record of choices that are settled. Add new entries at the bottom; if one
is reversed, say so in a new entry rather than editing the old one.

## 1. 2:1 isometric at 32×16

Tiles are 2:1 diamonds, 32 px wide by 16 px tall (TileSet: isometric,
diamond-down). All art, grid ↔ screen math (`sim/iso.gd`), and the
TileMapLayers assume this size.

## 2. GDScript

All game code is GDScript, targeting Godot 4.7 APIs (`TileMapLayer`, typed
dictionaries). No C#, no GDExtension.

## 3. Host-authoritative discrete grid sim, no continuous physics

The game state is a grid: every entity occupies exactly one tile, and `World`
owns the tile → entity map. Movement is whole-tile steps through
`World.try_move`. There are no physics bodies, no collision shapes, and no
continuous positions in the sim; on-screen motion is interpolation only.

The host is the single authority. All state mutation is gated behind
`multiplayer.is_server()`, from the start, even though there is no networking
yet.

## 4. 10 Hz tick

The sim advances at a fixed 10 ticks per second, independent of frame rate.
Durations in the sim (move time, attack cooldown) are counted in ticks.
Rendering interpolates between ticks.
