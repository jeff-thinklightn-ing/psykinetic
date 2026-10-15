extends Node
## A short clip of monsters' senses at work: a scenario in a room of its own
## (registered in memory, never saved), played as a host with a window,
## its player walked by a script, with a caption for each part. Recorded by
## Godot's movie maker (--write-movie, frames at a fixed rate, so the sim
## runs in step with them); tools/clip.sh runs it and stitches the frames
## with ffmpeg. A log line a tick: where the player is, its lantern, and
## what the monster faces, sees, hears and how alert it is.
##   godot --path . --write-movie <dir>/frame.png --fixed-fps 30 --scene res://tools/clip.tscn -- --scenario=sneak [--clip-max-seconds=60]
## Whatever happens it stops after --clip-max-seconds of game time (60 by
## default; the movie maker's frames are game time): a scenario that never
## gets to its end does not record for ever.
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
##   items: a lit room, a chest with a bandaging kit and a sack of ore, an
##     imp on guard. The player takes the kit into a hand, puts it down (G),
##     picks it up (F), throws it across the room (T), then throws the sack
##     at the imp, who staggers; the pack (I) is open throughout.
##   items_icons: the pack's icons (ItemIcons): a chest of four things
##     opened, one taken into the hands, three into the pack; each box its
##     item's icon over its name.
##   items_use: using things: a locked door rattles; from a chest a coin
##     purse, opened into gold, and the key, which opens the door; a sack
##     of ore put down beyond it, and the imp there hears the thud.
##   sounds: the sound slots heard in play (SoundKit): the player walks
##     (footsteps), opens a chest, opens a door into the next room and
##     fights the imp there to its death; each caption names the slot it
##     plays, and the log every sound played.
##   sound_hearing: what you hear is what monsters hear (decision 269). A
##     door opens and shuts again and again while the player backs away
##     from it: loud beside it, fainter, gone past its 6 cells. Then, the
##     door shut, blows land on an imp beyond it: heard muffled close to
##     the wall (half a fight's 5 cells), not at all further off.
##   door_hide: an imp chases the player down a corridor; they go through
##     the door at its end, shut it and keep quiet: it comes, finds
##     nothing beyond, and goes back.
##   door_noise: the same, and a word behind the door brings it in.
##   door_brute: the same with a brute, which cannot open doors and is
##     slower: a shout behind the door and it breaks the door down.
##   pack: four imps round a camp, a coward, two cautious and a bold one.
##     The coward sees the player and calls; the rest come. Hurt, each breaks
##     at its temperament's mark, and its rout breaks the coward and the
##     hurt; the bold one fights on.

const NAME := "clip"

var scenario := "sneak"
var max_seconds := 60.0
var _elapsed := 0.0
var _main: Node
var _player: Player
var _monster: Monster
## [kind, value, caption]: "say" (a caption, held value ticks), "lantern"
## (true lit), "walk" (to a tile), "lure" ([tile, n]: toward it, a step
## only while the monster is within n, till the monster gives up), "wait"
## (ticks), "work_door" (a door's edge: the player works it, as a click does),
## "speak" (words the player says, as typed), "brawl" (ticks: the player
## fights the nearest monster that is not running).
var _script: Array = []
var _at := 0
var _wait_until := -1
var _caption: Label
var _end_tick := -1
## The lure has the monster after the player.
var _lured := false
## Sounds already logged (the sounds scenario).
var _sounds_logged := 0
## Unheard sounds already logged (the sound_hearing scenario).
var _unheard_logged := 0
## The tick a sound_slam or sound_blows step ends (its own: _wait_until
## would hold the script still meanwhile).
var _repeat_until := -1
## How often sound_slam swings the door and sound_blows strikes.
const SLAM_TICKS := 20
## The tick a "sound_fight" step gives up by.
var _fight_until := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() == 2 and pair[0] == "scenario":
			scenario = pair[1]
		elif pair.size() == 2 and pair[0] == "clip-max-seconds":
			max_seconds = pair[1].to_float()
	match scenario:
		"sneak":
			_sneak()
		"escape":
			_escape()
		"leash":
			_leash()
		"items":
			_items()
		"items_icons":
			_items_icons()
		"items_use":
			_items_use()
		"sounds":
			_sounds()
		"sound_hearing":
			_sound_hearing()
		"door_hide", "door_noise", "door_brute":
			_door(scenario)
		"pack":
			_pack()
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
	if scenario in ["sneak", "sounds", "pack", "sound_hearing"]:
		_player.max_hp = 1000000
		_player.hp = _player.max_hp
	if scenario == "sound_hearing":
		# The imp only stands there to be struck: it neither dies nor moves.
		_monster.max_hp = 1000000
		_monster.hp = _monster.max_hp
		_monster.stunned_until_tick = 1 << 30
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	if _main.hint_panel != null:
		_main.hint_panel.visible = false  # The controls list would cover the caption.
	if scenario.begins_with("items"):
		_main.pack_panel.shown = true
	if scenario == "items_use":
		World.get_doors()[0].lock = "cellar"
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
	_elapsed += delta
	if _elapsed > max_seconds:
		push_warning("clip: %s ran past %d s; stopped" % [scenario, max_seconds])
		get_tree().quit(1)
		return
	var view: Node = _main._client3d if _main != null else null
	if view == null or _player == null or not is_instance_valid(_monster):
		return
	var at: Node3D = view._puppets.get(_player.get_instance_id())
	var monster: Node3D = view._puppets.get(_monster.get_instance_id())
	if at != null and monster != null:
		var middle: Vector3 = (monster.position - at.position) * 0.5
		view.pan = view.pan.lerp(middle, 1.0 - exp(-3.0 * delta)).limit_length(view.PAN_MAX)


## Registers the scenario's room: [param rows] of cells, a start, one
## monster of [param kind] at [param at] on guard facing [param facing];
## [param doors]: cells whose east edge is a door.
func _room(rows: Array[String], start: Vector2i, at: Vector2i, facing: Vector2i, ambient := 1.0, kind := "imp",
		doors: Array[Vector2i] = []) -> void:
	var markers := {start: "start", at: "monster_" + kind}
	var config := {"name": "Clip", "ambient": ambient,
		"entities": [{"at": [at.x, at.y], "facing": [facing.x, facing.y], "idle": {"mode": "guard"}}]}
	var expanded := Terrain.expand(rows)
	for cell in doors:
		var row := expanded[cell.y * 2]
		expanded[cell.y * 2] = row.substr(0, cell.x * 2 + 1) + "+" + row.substr(cell.x * 2 + 2)
	Level.register(NAME, Level.image_from_rows(expanded, markers, config), null, config)


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


func _items() -> void:
	var rows: Array[String] = [
		"#############",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#############",
	]
	var markers := {Vector2i(2, 3): "start", Vector2i(3, 1): "chest", Vector2i(10, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [3, 1], "props": {"slots": ["bandaging_kit", "ore_sack", "", ""]}},
			{"at": [10, 3], "facing": [-1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["say", 30, "A chest: a bandaging kit and a sack of ore."],
		["walk", Vector2i(3, 2), "To the chest."],
		["item_open", true, "Opened: the chest above, the pack and two hands (R, L) below."],
		["wait", 25, ""],
		["item_take", [0, Player.RIGHT_HAND], "The kit into the right hand (drag, in the pack below)."],
		["wait", 25, ""],
		["item_key", ["drop", null], "G: put it down."],
		["wait", 30, ""],
		["item_key", ["pick_up", null], "F: picked up again."],
		["wait", 30, ""],
		["item_key", ["throw", Vector2i(8, 2)], "T: thrown at the cursor (a kit flies far)."],
		["wait", 40, ""],
		["item_take", [1, Player.RIGHT_HAND], "The sack of ore: 10 kg. Carried, it weighs on you."],
		["item_open", false, ""],
		["walk", "beside the monster", "Up to the imp."],
		["item_key", ["throw", "the monster"], "T: thrown at the imp: it staggers."],
		["wait", 60, ""],
	]


func _items_icons() -> void:
	var rows: Array[String] = [
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(3, 1): "chest", Vector2i(7, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [3, 1], "props": {"slots": ["bandaging_kit", "ore_sack", "wood_bundle", "coin_purse"]}},
			{"at": [7, 3], "facing": [-1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["walk", Vector2i(3, 2), "To the chest."],
		["item_open", true, "Opened: each thing's icon, drawn from its art."],
		["wait", 30, ""],
		["item_take", [2, Player.RIGHT_HAND], "The wood into the hands: two-handed."],
		["wait", 20, ""],
		["item_take", [0, 0], "The bandages into the pack."],
		["wait", 15, ""],
		["item_take", [3, 1], "The coin purse."],
		["wait", 15, ""],
		["item_take", [1, 2], "The ore."],
		["wait", 30, "The chest empty, the pack full."],
		["item_open", false, ""],
		["wait", 30, ""],
	]


## Two rooms with a locked door between (the cellar's), a chest in the
## first with a purse, the key (a catalog entry of the clip's own) and a
## sack of ore, an imp on guard in the second.
func _items_use() -> void:
	Items.add_for_test({"id": "items_clip_key", "name": "cellar key", "short": "Key", "color": "c8a050",
		"size": [0.04, 0.1, 0.01], "weight": 0.1, "opens": "cellar"})
	var cells: Array[String] = [
		"#############",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#############",
	]
	var rows := Terrain.expand(cells)
	for y in range(1, rows.size() - 1):
		rows[y] = rows[y].substr(0, 11) + ("+" if y == 6 else "#") + rows[y].substr(12)
	var markers := {Vector2i(1, 3): "start", Vector2i(3, 1): "chest", Vector2i(10, 2): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [3, 1], "props": {"slots": ["coin_purse", "items_clip_key", "ore_sack", ""]}},
			{"at": [10, 2], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(rows, markers, config), null, config)
	_script = [
		["walk", Vector2i(5, 3), "A door to the cellar."],
		["sound_door", true, "Locked: it rattles."],
		["wait", 25, ""],
		["walk", Vector2i(3, 2), "A chest."],
		["item_open", true, "A coin purse, the cellar key, a sack of ore."],
		["wait", 20, ""],
		["item_take", [0, 0], "The purse into the pack."],
		["wait", 15, ""],
		["item_use", 0, "Right click it in the pack: opened, 10 gold."],
		["wait", 30, ""],
		["item_take", [1, 1], "The key: carried, it opens the cellar."],
		["item_take", [2, Player.RIGHT_HAND], "The ore in hand."],
		["item_open", false, ""],
		["walk", Vector2i(5, 3), ""],
		["sound_door", true, "The key in the pack: the door opens."],
		["wait", 20, ""],
		["walk", Vector2i(7, 4), "Into the cellar, the imp looking away."],
		["item_key", ["drop", null], "G: the ore put down. A heavy thud: the imp hears it."],
		["wait", 50, ""],
	]


## Two rooms with a door between, a chest in the first, an imp on guard in
## the second.
func _sounds() -> void:
	var cells: Array[String] = [
		"#############",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#############",
	]
	var rows := Terrain.expand(cells)
	# The wall between cells x 5 and 6 (pixel 11), a door in it on row 3.
	for y in range(1, rows.size() - 1):
		rows[y] = rows[y].substr(0, 11) + ("+" if y == 6 else "#") + rows[y].substr(12)
	var markers := {Vector2i(1, 3): "start", Vector2i(3, 1): "chest", Vector2i(10, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [3, 1], "props": {"slots": ["bandaging_kit", "", "", ""]}},
			{"at": [10, 3], "facing": [-1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(rows, markers, config), null, config)
	_script = [
		["say", 30, "Every sound is a named slot: today's take, or a placeholder."],
		["walk", Vector2i(3, 2), "Footsteps: sfx.footstep, heard 3 cells (a monster's hearing)."],
		["open", true, "A chest: sfx.chest_open."],
		["wait", 30, ""],
		["open", false, ""],
		["walk", Vector2i(5, 3), "To the door."],
		["sound_door", true, "A door: sfx.door_wood_open, heard 6 cells."],
		["wait", 25, ""],
		["walk", "beside the monster", "Into the next room."],
		["sound_fight", 400, "A fight: sfx.swing, sfx.hit_flesh, heard 5 cells."],
		["say", 60, "Its death: sfx.goblin_death."],
	]
func _pack() -> void:
	var rows: Array[String] = [
		"####################",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"####################",
	]
	var camp := Vector2i(13, 4)
	var at: Array[Vector2i] = [Vector2i(11, 4), Vector2i(13, 2), Vector2i(15, 4), Vector2i(13, 6)]
	var tempers := ["cautious", "cautious", "cowardly", "bold"]  # The coward faces the way you come.
	var markers := {Vector2i(2, 4): "start"}
	var entities: Array = []
	for i in at.size():
		markers[at[i]] = "monster_imp"
		entities.append({"at": [at[i].x, at[i].y], "temperament": tempers[i], "idle": {"mode": "gather", "point": [camp.x, camp.y]}})
	var config := {"name": "Clip", "ambient": 1.0, "entities": entities}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["say", 20, "Four imps round a camp: a coward, two cautious, a bold one."],
		["walk", Vector2i(8, 4), "The coward sees you, and calls the others."],
		["say", 25, ""],
		["brawl", 220, "Hurt, each breaks as its temper says (~); a rout takes the rest. The bold one fights on."],
		["say", 60, ""],
	]


func _door(which: String) -> void:
	var rows: Array[String] = [
		"###########################",
		"#......##############.....#",
		"#......##############.....#",
		"#.........................#",
		"#......##############.....#",
		"#......##############.....#",
		"###########################",
	]
	var brute := which == "door_brute"
	_room(rows, Vector2i(5, 3), Vector2i(2, 3), Vector2i(1, 0), 1.0, "brute" if brute else "imp", [Vector2i(20, 3)])
	var door := [20, 3, Terrain.EAST]
	_script = [
		["say", 15, "A %s sees you." % ("brute" if brute else "imp")],
		["walk", Vector2i(21, 3), "Run for the door, out of its sight."],
		["work_door", door, "Shut it behind you..."],
		["walk", Vector2i(23, 2), "...and keep quiet."],
	]
	if which == "door_hide":
		_script.append(["say", 220, "It comes to the door. Nothing beyond it: it goes back."])
	else:
		_script.append_array([
			["say", 50, "It comes to the door." if not brute else "It loses you."],
			["speak", "OVER HERE!" if brute else "Over here!", "A shout behind the door..." if brute else "A word behind the door..."],
			["say", 120, "...and it %s." % ("breaks the door down" if brute else "opens it and comes in")],
		])


## A long room, a door at its east end into a small one with an imp in it
## (held there and made too tough to die of the blows: _ready).
func _sound_hearing() -> void:
	var cells: Array[String] = [
		"###################",
		"#.................#",
		"#.................#",
		"#.................#",
		"#.................#",
		"#.................#",
		"###################",
	]
	var rows := Terrain.expand(cells)
	# The wall between cells x 13 and 14 (pixel 27), its door on row 3.
	for y in range(1, rows.size() - 1):
		rows[y] = rows[y].substr(0, 27) + ("+" if y == 6 else "#") + rows[y].substr(28)
	var markers := {Vector2i(13, 3): "start", Vector2i(15, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [15, 3], "facing": [-1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(rows, markers, config), null, config)
	_script = [
		["say", 20, "What you hear is what monsters hear: a door carries 6 cells."],
		["sound_slam", 60, "Beside the door: loud."],
		["walk", Vector2i(10, 3), ""],
		["sound_slam", 60, "3 cells off: fainter."],
		["walk", Vector2i(8, 3), ""],
		["sound_slam", 60, "5 cells: nearly gone."],
		["walk", Vector2i(5, 3), ""],
		["sound_slam", 60, "8 cells: past its 6. Not heard, by you or a monster here."],
		["sound_shut", true, "The door shut, blows on the imp beyond it (a fight carries 5)."],
		["walk", Vector2i(13, 3), ""],
		["sound_blows", 80, "2 cells, through the wall: muffled (half as far: 2.5 cells)."],
		["walk", Vector2i(10, 3), ""],
		["sound_blows", 80, "5 cells, through the wall: not heard."],
		["walk", Vector2i(13, 3), ""],
		["sound_slam", 20, "The door open again, 2 cells: clear."],
		["sound_blows", 80, ""],
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
		"item_take":
			World.try_transfer(_player, _chest(), int(step[1][0]), _player, int(step[1][1]))
		"item_use":
			_main.use_slot(int(step[1]))
		"item_open":
			if bool(step[1]):
				_main._open_pack(_player, _chest())
			else:
				_main.close_other()
		"item_key":
			var args := {}
			var cell: Variant = _monster.tile if step[1][1] is String else step[1][1]
			if cell != null:
				args["cell"] = [cell.x, cell.y]
			World.command(_player, str(step[1][0]), args)
		"sound_door":
			var door: Door = World.get_doors()[0]
			if door.open != bool(step[1]):
				World.try_toggle_door(_player, door.key)
		"sound_slam":
			# The door swings every SLAM_TICKS ticks for step[1] ticks, as if by the
			# imp (World makes its noise where the mover stands).
			if _repeat_until < 0:
				_repeat_until = tick + int(step[1])
			if tick < _repeat_until:
				if tick % SLAM_TICKS == 0:
					var slammed: Door = World.get_doors()[0]
					World._set_door(slammed, not slammed.open, _monster)
				return
			_repeat_until = -1
		"sound_shut":
			var shut: Door = World.get_doors()[0]
			World._set_door(shut, false, _monster)
		"sound_blows":
			# A blow on the imp every SLAM_TICKS ticks for step[1] ticks, from no one.
			if _repeat_until < 0:
				_repeat_until = tick + int(step[1])
			if tick < _repeat_until:
				if tick % SLAM_TICKS == 0 and is_instance_valid(_monster):
					World.damage(_monster, 1, null, &"attack")
				return
			_repeat_until = -1
		"sound_fight":
			if is_instance_valid(_monster) and _monster.hp > 0:
				if _fight_until < 0:
					_fight_until = tick + int(step[1])
				if tick < _fight_until:
					if World.distance(_player.tile, _monster.tile) > 1:
						_walk(_beside_monster())
					else:
						World.order_attack(_player, _monster)
					return
		"work_door":
			if tick < _player.next_move_tick:
				return
			World.command(_player, "door", {"edge": step[1]})
		"speak":
			World.command(_player, "say", {"text": str(step[1])})
		"brawl":
			if _fight_until < 0:
				_fight_until = tick + int(step[1])
			if tick < _fight_until:
				var foe := _nearest_standing()
				if foe != null:
					if World.distance(_player.tile, foe.tile) > 1:
						_walk(foe.tile)
					else:
						World.order_attack(_player, foe)
				return
			_fight_until = -1
		"walk":
			if not _walk(_beside_monster() if step[1] is String else step[1]):
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


## A free cell beside the monster, on the player's side.
func _beside_monster() -> Vector2i:
	var best := _monster.tile
	for direction: Vector2i in World.DIRECTIONS:
		var cell := _monster.tile + direction
		if (World.is_free(cell) or cell == _player.tile) and World.can_melee(cell, _monster.tile) \
				and (best == _monster.tile or World.distance(cell, _player.tile) < World.distance(best, _player.tile)):
			best = cell
	return best


func _chest() -> Chest:
	for entity in World.get_entities():
		if entity is Chest:
			return entity
	return null


## The nearest monster not running, or null.
func _nearest_standing() -> Monster:
	var best: Monster = null
	for entity in World.monsters():
		var monster := entity as Monster
		if monster.alert != Monster.Alert.FLEEING and (best == null
				or World.distance(_player.tile, monster.tile) < World.distance(_player.tile, best.tile)):
			best = monster
	return best


func _log(tick: int) -> void:
	if scenario == "pack":
		var each: Array[String] = []
		for entity in World.monsters():
			var monster := entity as Monster
			each.append("%s %s at %s hp %d %s" % [monster.name, Monster.Temper.keys()[monster.temper], monster.tile, monster.hp,
				Monster.Alert.keys()[monster.alert]])
		print("[clip] tick %d: player %s; %s" % [tick, _player.tile, "; ".join(each)])
		return
	if scenario == "sounds" or scenario == "sound_hearing":
		var sfx: Sfx = _main._client3d.sfx if _main._client3d != null else null
		if sfx != null:
			for entry: Array in sfx.played.slice(_sounds_logged):
				print("[clip] tick %d: played %s (%s) on %s, heard from %s" % [tick, entry[0], str(entry[1]).get_file() if entry[1] != "" else "placeholder", entry[2], sfx.listener])
			_sounds_logged = sfx.played.size()
			for slot: String in sfx.unheard.slice(_unheard_logged):
				print("[clip] tick %d: not heard %s (from %s)" % [tick, slot, sfx.listener])
			_unheard_logged = sfx.unheard.size()
		if tick % 30 == 0:
			print("[clip] tick %d: player %s hp %d; %s" % [tick, _player.tile, _player.hp,
				"%s at %s hp %d %s" % [_monster.name, _monster.tile, _monster.hp, Monster.Alert.keys()[_monster.alert]] if is_instance_valid(_monster) else "monster gone"])
		return
	if scenario == "items_use":
		var door: Door = World.get_doors()[0]
		print("[clip] tick %d: player %s slots %s gold %d key %s; door %s; %s at %s %s, heard %s" % [tick, _player.tile, _player.slots,
			World.gold_of(_player.get("player_id")), World.has_key(_player, door.lock), "open" if door.open else "shut",
			_monster.name, _monster.tile, Monster.Alert.keys()[_monster.alert],
			_monster.senses.heard.back()["kind"] if not _monster.senses.heard.is_empty() else "-"])
		return
	if scenario == "items_icons":
		var shown: Array[String] = []
		for i in _player.slots.size():
			shown.append("%s%s" % [_main.pack_panel.shown_in(true, i), "*" if _main.pack_panel.icon_in(true, i) != null else ""])
		print("[clip] tick %d: pack %s (* an icon)" % [tick, shown])
		return
	if scenario == "items":
		print("[clip] tick %d: player %s mass %.1f hands %s; ground %s (%d piles, %d drawn); %s hp %d%s" % [tick, _player.tile, _player.mass,
			[_player.slots[Player.RIGHT_HAND], _player.slots[Player.LEFT_HAND]], World.zone.ground.keys(), World.zone.piles.size(),
			_main._client3d._pile_nodes.size() if _main._client3d != null else -1, _monster.name + " at %s" % _monster.tile,
			_monster.hp, " stunned" if World.is_stunned(_monster) else ""])
		return
	var heard := "" if _monster.senses.heard.is_empty() else "%s at %s (tick %d)" % [
		_monster.senses.heard.back()["kind"], _monster.senses.heard.back()["at"], _monster.senses.heard.back()["tick"]]
	print("[clip] tick %d: player %s lantern %s; %s at %s facing %s, %s, target %s, heard %s" % [tick, _player.tile,
		"lit" if _player.emit_light > 0.0 else "covered", _monster.name, _monster.tile, _monster.facing,
		Monster.Alert.keys()[_monster.alert], _monster.target.name if _monster.target != null else "none", heard])
