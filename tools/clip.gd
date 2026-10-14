extends Node
## A short clip of monsters' senses at work: a scenario in a room of its own
## (registered in memory, never saved), played as a host with a window,
## its player walked by a script, with a caption for each part. Recorded by
## Godot's movie maker (--write-movie, frames at a fixed rate, so the sim
## runs in step with them); tools/clip.sh runs it and stitches the frames
## with ffmpeg. A log line a tick: where the player is, its lantern, and
## what the monster faces, sees, hears and how alert it is.
##   godot --path . --write-movie <dir>/frame.png --fixed-fps 30 --scene res://tools/clip.tscn -- --scenario=sneak
##
## Scenarios:
##   sneak: a dark room, an imp on guard facing north. The player, lantern
##     covered, walks behind it (out of its cone, beyond its hearing), up
##     its side and round in front of it in the dark, unseen; lights the
##     lantern and is seen at once.
##   escape: an imp on guard sees the player, who runs down a corridor and
##     round two corners; the imp hunts to where it last saw them and on,
##     looks round, gives up and walks home.
##   leash: in a long hall the player keeps just ahead of an imp; LEASH
##     tiles from where it took up the chase it gives up and walks home,
##     the player in plain sight.

const NAME := "clip"

var scenario := "sneak"
var _main: Node
var _player: Player
var _monster: Monster
## [kind, value, caption]: "say" (a caption, held value ticks), "lantern"
## (true lit), "walk" (to a tile), "lure" ([tile, n]: toward it, a step
## only while the monster is within n, till the monster gives up), "wait"
## (ticks).
var _script: Array = []
var _at := 0
var _wait_until := -1
var _caption: Label
var _end_tick := -1
## The lure has the monster after the player.
var _lured := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() == 2 and pair[0] == "scenario":
			scenario = pair[1]
	match scenario:
		"sneak":
			_sneak()
		"escape":
			_escape()
		"leash":
			_leash()
		_:
			push_error("unknown scenario %s" % scenario)
			get_tree().quit(1)
			return
	Net.port = preload("res://tests/test_ports.gd").of(17960)
	Net.companions = false
	Net.state_path = ""
	Net.map_name = NAME
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_player = _main._local_player()
	for entity in World.monsters():
		_monster = entity
	_player.max_hp = 1000000
	_player.hp = _player.max_hp
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	if _main.hint_panel != null:
		_main.hint_panel.visible = false  # The controls list would cover the caption.
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.offset_top = -96
	_caption.offset_bottom = -48
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 44)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(_caption)
	if _main._client3d != null:
		_main._client3d._zoom_to = _main._client3d.ZOOM_MAX
	World.ticked.connect(_on_tick)


## The camera on the middle of the player and the monster, so both are seen.
func _process(delta: float) -> void:
	var view: Node = _main._client3d if _main != null else null
	if view == null or _player == null or _monster == null:
		return
	var at: Node3D = view._puppets.get(_player.get_instance_id())
	var monster: Node3D = view._puppets.get(_monster.get_instance_id())
	if at != null and monster != null:
		var middle: Vector3 = (monster.position - at.position) * 0.5
		view.pan = view.pan.lerp(middle, 1.0 - exp(-3.0 * delta)).limit_length(view.PAN_MAX)


## Registers the scenario's room: [param rows] of cells, a start, one imp at
## [param imp] on guard facing [param facing].
func _room(rows: Array[String], start: Vector2i, imp: Vector2i, facing: Vector2i, ambient := 1.0) -> void:
	var markers := {start: "start", imp: "monster_imp"}
	var config := {"name": "Clip", "ambient": ambient,
		"entities": [{"at": [imp.x, imp.y], "facing": [facing.x, facing.y], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)


func _sneak() -> void:
	var rows: Array[String] = [
		"#################",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#################",
	]
	_room(rows, Vector2i(1, 8), Vector2i(8, 4), Vector2i(0, -1), 0.12)
	_script = [
		["say", 25, "A dark room. An imp on guard, facing north."],
		["lantern", false, "Lantern covered (L)."],
		["wait", 10, ""],
		["walk", Vector2i(15, 8), "Behind it, beyond its hearing: unseen."],
		["walk", Vector2i(15, 1), "Up its side, in the dark."],
		["walk", Vector2i(12, 1), "In front of it, lantern covered: still unseen."],
		["wait", 15, ""],
		["lantern", true, "Lantern lit: seen."],
		["wait", 50, ""],
	]


func _escape() -> void:
	var rows: Array[String] = [
		"##################################",
		"#..........#######################",
		"#..........#######################",
		"#..........#######################",
		"#..........#######################",
		"#.............................####",
		"#..........##################.####",
		"#..........##################.####",
		"#..........##################.####",
		"#..........##################.####",
		"#..........#..................####",
		"##################################",
	]
	_room(rows, Vector2i(4, 8), Vector2i(3, 3), Vector2i(0, 1))
	_script = [
		["say", 15, "An imp on guard sees you."],
		["walk", Vector2i(10, 5), "Run, and break its line of sight."],
		["walk", Vector2i(29, 5), ""],
		["walk", Vector2i(29, 10), "Round the corner..."],
		["walk", Vector2i(12, 10), "...and round another."],
		["say", 60, "It hunts where it last saw you, and looks round."],
		["say", 200, "It gives up, and goes back to its post."],
	]


func _leash() -> void:
	var rows: Array[String] = [
		"################################",
		"#..............................#",
		"#..............................#",
		"#..............................#",
		"################################",
	]
	_room(rows, Vector2i(6, 2), Vector2i(2, 2), Vector2i(1, 0))
	_script = [
		["say", 15, "An imp sees you."],
		["lure", [Vector2i(30, 2), 3], "You keep just ahead of it..."],
		["say", 80, "...too far from its post: it gives up, you in plain sight."],
	]


func _on_tick(tick: int) -> void:
	if _end_tick >= 0:
		if tick >= _end_tick:
			get_tree().quit()
		return
	_log(tick)
	if tick < _wait_until:
		return
	if _at >= _script.size():
		_end_tick = tick + 5
		return
	var step: Array = _script[_at]
	if str(step[2]) != "":
		_caption.text = str(step[2])
	match str(step[0]):
		"say", "wait":
			if _wait_until < 0:
				_wait_until = tick + int(step[1])
				return
		"lantern":
			if (_player.emit_light > 0.0) != bool(step[1]):
				_player.toggle_lantern()
		"walk":
			if not _walk(step[1]):
				return
		"lure":
			var after := _monster.alert == Monster.Alert.FIGHTING or _monster.alert == Monster.Alert.HUNTING
			_lured = _lured or after
			if not (_lured and not after):
				if World.distance(_player.tile, _monster.tile) <= int(step[1][1]):
					_walk(step[1][0])
				return
	_at += 1
	_wait_until = -1


## A step toward [param to] when the player may move; true once there.
func _walk(to: Vector2i) -> bool:
	if _player.tile == to:
		return true
	if World.tick >= _player.next_move_tick:
		var path := World.find_path(_player.tile, to, false, null, 400)
		if not path.is_empty():
			World.try_move(_player, path[0] - _player.tile)
	return false


func _log(tick: int) -> void:
	var heard := "" if _monster.senses.heard.is_empty() else "%s at %s (tick %d)" % [
		_monster.senses.heard.back()["kind"], _monster.senses.heard.back()["at"], _monster.senses.heard.back()["tick"]]
	print("[clip] tick %d: player %s lantern %s; %s at %s facing %s, %s, target %s, heard %s" % [tick, _player.tile,
		"lit" if _player.emit_light > 0.0 else "covered", _monster.name, _monster.tile, _monster.facing,
		Monster.Alert.keys()[_monster.alert], _monster.target.name if _monster.target != null else "none", heard])
