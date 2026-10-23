class_name GroundPile
extends Node2D
## What lies on one cell of ground: the ids of up to World.GROUND_PER_CELL
## things, the top last. The server keeps the things themselves (their
## ItemBook uids) in Zone.ground; Main spawns one of these through the
## zone's spawner for each cell with something on it, and frees it when
## the cell is empty, so every client in reach (Interest, by its cell)
## has it. It occupies nothing, blocks nothing and never acts.
##
## gold is the whole gold lying there besides (601 amended: gold is a count,
## never a thing; it takes no place among the ids), 0 for none; a pile may
## hold gold and nothing else.
##
## thrown_from is where its newest thing was thrown from (World.NO_CELL if
## it was put down), with thrown_tick when: the views draw the flight.
## Drawn here as a small square per thing in its catalog colour; the 3D
## view draws each thing's art slot (Client3D, World.pile_shown).

const REPLICATED := ["ids", "gold", "thrown_from", "thrown_tick"]
const SIZE := 5.0
const GOLD_COLOR := Color("e0c050")

var tile := Vector2i.ZERO
## Its zone, as an entity's (GridEntity.zone), and its synchronizer.
var zone := ""
var sync: MultiplayerSynchronizer
var ids := PackedStringArray():
	set(value):
		if ids != value:
			ids = value
			_shown_changed()
var gold := 0:
	set(value):
		if gold != value:
			gold = value
			_shown_changed()
var thrown_from := World.NO_CELL
var thrown_tick := -1


func _init() -> void:
	var config := SceneReplicationConfig.new()
	for property in REPLICATED:
		var path := NodePath(".:" + property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	synchronizer.replication_config = config
	synchronizer.add_visibility_filter(func(peer: int) -> bool: return World.peer_sees(peer, zone) and Net.interest.sees(peer, self))
	# As an entity's: asked on spawn and zone changes, not every frame.
	synchronizer.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
	add_child(synchronizer)
	sync = synchronizer


## Builds one from a spawn spec: {script, name, tile: [x, y], zone, ids,
## gold, thrown_from: [x, y] or null, thrown_tick}.
static func build(spec: Dictionary) -> GroundPile:
	var pile := GroundPile.new()
	pile.name = str(spec.get("name", "Pile"))
	var cell: Array = spec.get("tile", [0, 0])
	pile.tile = Vector2i(int(cell[0]), int(cell[1]))
	pile.zone = str(spec.get("zone", ""))
	pile.ids = PackedStringArray(spec.get("ids", []))
	pile.gold = maxi(int(spec.get("gold", 0)), 0)
	var from: Variant = spec.get("thrown_from")
	if from is Array and from.size() == 2:
		pile.thrown_from = Vector2i(int(from[0]), int(from[1]))
		pile.thrown_tick = int(spec.get("thrown_tick", -1))
	pile.position = Iso.tile_to_local(pile.tile)
	return pile


## The name a pile on [param cell] goes by (so a client finds the same node).
static func name_for(cell: Vector2i) -> String:
	return "Pile_%d_%d" % [cell.x, cell.y]


func _ready() -> void:
	World.register_pile(self)


func _exit_tree() -> void:
	World.unregister_pile(self)


func _shown_changed() -> void:
	queue_redraw()
	if is_inside_tree():
		World.pile_shown.emit(self)


func _draw() -> void:
	for i in ids.size():
		var at := Vector2((i - (ids.size() - 1) * 0.5) * (SIZE + 1.0), -SIZE * 0.5)
		draw_rect(Rect2(at - Vector2.ONE * SIZE * 0.5, Vector2.ONE * SIZE), Items.color_of(ids[i]))
		draw_rect(Rect2(at - Vector2.ONE * SIZE * 0.5, Vector2.ONE * SIZE), Color(0, 0, 0, 0.6), false, 1.0)
	if gold > 0:
		# Its gold, a small square under the things (601 amended).
		var under := Vector2(0.0, SIZE * 0.5)
		draw_rect(Rect2(under - Vector2.ONE * SIZE * 0.4, Vector2.ONE * SIZE * 0.8), GOLD_COLOR)
		draw_rect(Rect2(under - Vector2.ONE * SIZE * 0.4, Vector2.ONE * SIZE * 0.8), Color(0, 0, 0, 0.6), false, 1.0)
