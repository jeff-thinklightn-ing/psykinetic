extends Node
## A short clip of monsters' senses at work: a scenario in a room of its own
## (registered in memory, never saved), played as a host with a window,
## its player walked by a script, with a caption for each part. Recorded by
## Godot's movie maker (--write-movie, frames at a fixed rate, so the sim
## runs in step with them); tools/clip.sh runs it and stitches the frames
## with ffmpeg. A log line a tick: where the player is, its lantern, and
## what the monster faces, sees and last heard.
##   godot --path . --write-movie <dir>/frame.png --fixed-fps 30 --scene res://tools/clip.tscn -- --scenario=sneak
##
## Scenarios:
##   sneak: a dark room, an imp on guard facing north. The player, lantern
##     covered, walks behind it (out of its cone, beyond its hearing), up
##     its side and round in front of it in the dark, unseen; lights the
##     lantern and is seen at once.

const NAME := "clip"

var scenario := "sneak"
var _main: Node
var _player: Player
var _monster: Monster
## [kind, value, caption]: "say" (a caption, held value ticks), "lantern"
## (true lit), "walk" (to a tile), "wait" (ticks).
var _script: Array = []
var _at := 0
var _wait_until := -1
var _caption: Label
var _end_tick := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() == 2 and pair[0] == "scenario":
			scenario = pair[1]
	match scenario:
		"sneak":
			_sneak()
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
	World.ticked.connect(_on_tick)


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
	var markers := {Vector2i(1, 8): "start", Vector2i(8, 4): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.12,
		"entities": [{"at": [8, 4], "facing": [0, -1], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
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
			var to: Vector2i = step[1]
			if _player.tile != to:
				if tick >= _player.next_move_tick:
					var path := World.find_path(_player.tile, to, false, null, 400)
					if not path.is_empty():
						World.try_move(_player, path[0] - _player.tile)
				return
	_at += 1
	_wait_until = -1


func _log(tick: int) -> void:
	var heard := "" if _monster.senses.heard.is_empty() else "%s at %s (tick %d)" % [
		_monster.senses.heard.back()["kind"], _monster.senses.heard.back()["at"], _monster.senses.heard.back()["tick"]]
	print("[clip] tick %d: player %s lantern %s; %s at %s facing %s, target %s, heard %s" % [tick, _player.tile,
		"lit" if _player.emit_light > 0.0 else "covered", _monster.name, _monster.tile, _monster.facing,
		_monster.target.name if _monster.target != null else "none", heard])
