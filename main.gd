extends Node2D
## Builds the test level, hands it to World, and turns clicks into move orders.
## This is view/input glue: it never touches entity state itself.

const FLOOR_SOURCE := 0
const WALL_SOURCE := 1
const LEVEL: Array[String] = [
	"################",
	"#..............#",
	"#..............#",
	"#.....##.......#",
	"#.....##.......#",
	"#..............#",
	"#.........#....#",
	"#.........#....#",
	"#...###...#....#",
	"#..............#",
	"#..............#",
	"################",
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
	World.load_terrain(ground.get_used_cells(), walls.get_used_cells())
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
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if is_instance_valid(player):
		World.order_move(player, _mouse_tile())


## Screen -> grid: the canvas transform (camera, stretch) is undone by
## get_global_mouse_position(), then Iso inverts the diamond projection.
func _mouse_tile() -> Vector2i:
	return Iso.local_to_tile(ground.to_local(get_global_mouse_position()))


func _paint_level() -> void:
	for y in LEVEL.size():
		for x in LEVEL[y].length():
			var tile := Vector2i(x, y)
			ground.set_cell(tile, FLOOR_SOURCE, Vector2i.ZERO)
			if LEVEL[y][x] == "#":
				walls.set_cell(tile, WALL_SOURCE, Vector2i.ZERO)


func _on_world_ticked(tick: int) -> void:
	var hp_text := "dead"
	if is_instance_valid(player) and player.spawned:
		hp_text = "%d/%d" % [player.hp, player.max_hp]
	hud.text = "HP %s   tick %d   click a tile to move, R to restart" % [hp_text, tick]
