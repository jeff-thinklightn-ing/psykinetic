extends Node2D
## Builds the test room, hands it to World, and turns clicks into orders.
## This is view/input glue: it never touches entity state itself.

const FLOOR_SOURCE := 0
const WALL_SOURCE := 1
const FIRE_SOURCE := 2
## 14x14. '#' wall, '.' floor, '~' fire. The corridor is row 8, x 1..5, with
## its dead end at x 1. Entities are placed in main.tscn via start_tile.
const LEVEL: Array[String] = [
	"##############",
	"#............#",
	"#............#",
	"#............#",
	"#............#",
	"#......~~~...#",
	"#............#",
	"######.......#",
	"#............#",
	"######.......#",
	"#............#",
	"#............#",
	"#............#",
	"##############",
]

@onready var ground: TileMapLayer = $Ground
@onready var walls: TileMapLayer = $YSort/Walls
@onready var entities: Node2D = $YSort/Entities
@onready var player: Player = $YSort/Entities/Player
@onready var cursor: Polygon2D = $Cursor
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $HUD/Label


func _ready() -> void:
	var probe := Vector2i(3, 5)
	if not ground.map_to_local(probe).is_equal_approx(Iso.tile_to_local(probe)):
		push_error("Iso math disagrees with the TileSet: %s vs %s" % [
			Iso.tile_to_local(probe), ground.map_to_local(probe)])

	_paint_level()
	World.reset()
	World.load_terrain(ground.get_used_cells(), walls.get_used_cells(),
			ground.get_used_cells_by_id(FIRE_SOURCE))
	# Child order is spawn order is entity id order.
	for child in entities.get_children():
		var entity := child as GridEntity
		if entity != null:
			World.spawn(entity, entity.start_tile)

	var last_tile := Vector2i(LEVEL[0].length() - 1, LEVEL.size() - 1)
	camera.position = (Iso.tile_to_local(Vector2i.ZERO) + Iso.tile_to_local(last_tile)) * 0.5
	World.ticked.connect(_on_world_ticked)


func _process(_delta: float) -> void:
	var tile := _mouse_tile()
	cursor.visible = World.is_walkable(tile)
	cursor.position = Iso.tile_to_local(tile)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		# Restart: _ready() resets World when the scene comes back.
		if multiplayer.is_server():
			get_tree().reload_current_scene()
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if not is_instance_valid(player) or not player.spawned:
		return
	var tile := _mouse_tile()
	var target := World.get_entity_at(tile)
	var in_reach := target != null and target != player and World.can_melee(player.tile, tile)
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			# Adjacent creature: attack. Anything else: walk there (and push).
			if in_reach and target.is_creature():
				World.order_action(player, GridEntity.Order.ATTACK, target)
			else:
				World.order_move(player, tile)
		MOUSE_BUTTON_RIGHT:
			if in_reach:
				World.order_action(player, GridEntity.Order.SHOVE, target)


## Screen -> grid: the canvas transform (camera, stretch) is undone by
## get_global_mouse_position(), then Iso inverts the diamond projection.
func _mouse_tile() -> Vector2i:
	return Iso.local_to_tile(ground.to_local(get_global_mouse_position()))


func _paint_level() -> void:
	for y in LEVEL.size():
		for x in LEVEL[y].length():
			var tile := Vector2i(x, y)
			var symbol := LEVEL[y][x]
			ground.set_cell(tile, FIRE_SOURCE if symbol == "~" else FLOOR_SOURCE, Vector2i.ZERO)
			if symbol == "#":
				walls.set_cell(tile, WALL_SOURCE, Vector2i.ZERO)


func _on_world_ticked(tick: int) -> void:
	var hp_text := "dead"
	if is_instance_valid(player) and player.spawned:
		hp_text = "%d/%d" % [player.hp, player.max_hp]
	hud.text = "HP %s   tick %d   LMB move / attack   RMB shove   R restart" % [hp_text, tick]
