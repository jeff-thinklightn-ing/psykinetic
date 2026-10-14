class_name Zone
extends RefCounted
## One loaded map on the server: its own terrain, doors, entities and tick.
## World holds every zone and works on one at a time (World.enter): its
## state is swapped into World's own fields, so everything that asks World
## anything asks the zone it is in. A client has one zone, the one its
## player is in. Main keeps its own per-zone state here too (main).
##
## A zone with no player in it sleeps (World.step skips it): only the slow
## world tick moves it on (World.world_tick), with nobody connected too.
## asleep_since is when it fell asleep (msec; World._woke).

var name := ""
var tick := 0
var floor: Dictionary[Vector2i, bool] = {}
var fire: Dictionary[Vector2i, bool] = {}
var height: Dictionary[Vector2i, int] = {}
var stairs: Dictionary[Vector2i, Vector2i] = {}
var water: Dictionary[Vector2i, bool] = {}
var torches: Dictionary[Vector2i, bool] = {}
var fields := Fields.new()
var north := Vector2i(0, -1)
var outdoor := false
var edges: Dictionary[Vector3i, int] = {}
var doors: Dictionary[Vector3i, Door] = {}
var occupancy: Dictionary[Vector2i, GridEntity] = {}
var entities: Array[GridEntity] = []
var hits: Array = []
## World.find_path's grid and its memo of what the terrain allows: see
## World._grid_rect.
var grid_rect := Rect2i()
var grid_steps := PackedByteArray()
## Main's state for this zone (its level, spawn table, respawn timers, the
## node its entities are under and their spawner).
var main := {}
var awake := true
## Counts every coming and going of its entities (a spawn, a despawn, a
## reset): what was measured before a change may be out of date after it.
var comings := 0
var asleep_since := -1
## Where its players and companions last stood (World._tier_origins).
var tier_origins: Array[Vector2i] = []


func _init(zone_name := "") -> void:
	name = zone_name
