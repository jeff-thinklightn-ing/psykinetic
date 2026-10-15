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
##   items_weapons: the seven weapons (Items.VERBS): sword and shield in
##     the hands, hammer, spear and dagger in the pack, the giant axe and
##     the bow in a chest; each caption names the verb.
##   items_controls: the right button as the off hand (decision 329): a
##     shield raised while held ("shield raised"), E opening a chest, a bow
##     from it drawn ("bow drawn 50%") and let go at the imp.
##   items_loot: loot tables (decision 330): the level names "supplies"
##     for its chest and "armoury" for its brutes; the chest opened, stocked
##     from its table; the brute, carrying what its table gave, fought and
##     beaten, drops it where it falls.
##   items_bow: the bow shoots (decision 335): at dusk, the lantern
##     covered, a rabbit shot at a full draw and killed; the deer runs from
##     the kill, comes back, and is shot (4) as it comes in range: it bolts.
##   items_blows: the weapon in the blow (decision 338): a war hammer
##     knocks a brute back a cell a blow, where a fist would not move it;
##     then a dagger, quick, in the back of an imp that faces away.
##   items_block: block (decision 340): between an imp and a brute, the
##     shield raised toward the imp takes its blows for stamina while the
##     brute behind, outside the arc, lands its own; out of stamina, the
##     guard gives way and the player staggers.
##   items_axe: the giant axe (decision 343): slow, both hands; one swing
##     at three imps in an arc strikes all three and knocks them down;
##     they lie a moment, then get up.
##   items_spear: the spear (decision 344): a boar shot from 6 cells turns
##     and charges (enemy-ai's 345); the hunter, standing still with a
##     spear (braced), stops the charge and throws it back.
##   items_pickup: monsters take up weapons (decision 347): a dagger is
##     dropped by an imp; it takes it up (its AI's call, made here by
##     item_pick: World.try_pick_up_weapon), heavier by it, and fights
##     with it.
##   items_buffs: a travel ration from a chest, eaten from the pack: the HUD
##     shows "Fed +10" and its time running down; the log, the mass.
##   sounds: the sound slots heard in play (SoundKit): the player walks
##     (footsteps), opens a chest, opens a door into the next room and
##     fights the imp there to its death; each caption names the slot it
##     plays, and the log every sound played.
##   sound_hearing: what you hear is what monsters hear (decision 269). A
##     door opens and shuts again and again while the player backs away
##     from it: loud beside it, fainter, gone past its 6 cells. Then, the
##     door shut, blows land on an imp beyond it: heard muffled close to
##     the wall (half a fight's 5 cells), not at all further off.
##   sound_ambience: the beds under it all (decision 270), outdoors: the
##     clock run from dawn through noon and dusk to midnight, then rain and
##     a storm; the player walks up to a fire to hear it crackle. The log
##     says each bed's level every second.
##   sound_reel: a listening reel of the slots given (--slots=a,b,...; else
##     every slot with third-party takes, SoundKit.takes): each played
##     beside the player once per take, its name and source as the caption,
##     for Jeff to keep or veto by ear.
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
## fights the nearest monster that is not running), "raid" ([group, arrival,
## town cell]: a raid group comes into the room, Raids.enter).
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
## Ticks between two plays of the sound reel.
const REEL_TICKS := 12
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
		"items_buffs":
			_items_buffs()
		"items_weapons":
			_items_weapons()
		"items_controls":
			_items_controls()
		"items_loot":
			_items_loot()
		"items_bow":
			_items_bow()
		"items_blows":
			_items_blows()
		"items_block":
			_items_block()
		"items_axe":
			_items_axe()
		"items_spear":
			_items_spear()
		"items_pickup":
			_items_pickup()
		"sounds":
			_sounds()
		"sound_hearing":
			_sound_hearing()
		"sound_reel":
			_sound_reel()
		"sound_ambience":
			_sound_ambience()
		"door_hide", "door_noise", "door_brute":
			_door(scenario)
		"pack":
			_pack()
		"raid":
			_raid()
		"wild":
			_wild()
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
	if scenario in ["sneak", "sounds", "pack", "sound_hearing", "sound_reel", "raid", "sound_ambience", "wild"]:
		_player.max_hp = 1000000
		_player.hp = _player.max_hp
	if scenario in ["sound_hearing", "sound_reel", "sound_ambience"]:
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


func _items_weapons() -> void:
	var rows: Array[String] = [
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(3, 1): "chest", Vector2i(7, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [3, 1], "props": {"slots": ["giant_axe", "bow", "", ""]}},
			{"at": [7, 3], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["walk", Vector2i(3, 2), "Weapons are verbs, not damage tiers."],
		["item_give", ["sword", Player.RIGHT_HAND], "Sword: a light guard ahead (block, half a blow)."],
		["wait", 15, ""],
		["item_give", ["shield", Player.LEFT_HAND], "Shield: a guard three cells wide (block, a whole blow)."],
		["wait", 15, ""],
		["item_give", ["hammer", 0], "Hammer: knockback (three times the push)."],
		["wait", 15, ""],
		["item_give", ["spear", 1], "Spear: reach, two cells; braced, it stops a charge."],
		["wait", 15, ""],
		["item_give", ["dagger", 2], "Dagger: quick, light; twice from behind (backstab)."],
		["wait", 15, ""],
		["item_open", true, "Giant axe: slow, both hands, knocks down. Bow: both hands, ranged; the longer the draw, the stronger."],
		["wait", 40, ""],
	]


func _items_controls() -> void:
	var rows: Array[String] = [
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(3, 1): "chest", Vector2i(7, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [3, 1], "props": {"slots": ["bow", "", "", ""]}},
			{"at": [7, 3], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["walk", Vector2i(3, 2), "The right button is the off hand."],
		["item_give", ["shield", Player.LEFT_HAND], "A shield in the left hand."],
		["wait", 10, ""],
		["item_raise", null, "Right button held: the shield is raised."],
		["wait", 25, ""],
		["item_lower", null, "Let go: lowered."],
		["wait", 10, ""],
		["item_clear", Player.LEFT_HAND, "Opening is E now: a tap with the cursor on the chest."],
		["item_e", null, ""],
		["wait", 15, ""],
		["item_take", [0, Player.RIGHT_HAND], "A bow from it, in both hands."],
		["item_open", false, ""],
		["wait", 10, ""],
		["item_raise", null, "Right button held: the bow draws."],
		["wait", 25, ""],
		["item_lower", Vector2i(7, 3), "Let go: loosed at the imp (what it does in a fight comes with combat)."],
		["wait", 25, ""],
	]


func _items_loot() -> void:
	var rows: Array[String] = [
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(3, 1): "chest", Vector2i(6, 2): "monster_brute"}
	var config := {"name": "Clip", "ambient": 0.9, "loot": {"chest": "supplies", "brute": "armoury"},
		"entities": [{"at": [6, 2], "facing": [-1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["walk", Vector2i(3, 2), "Loot tables: this level names \"supplies\" for chests, \"armoury\" for brutes."],
		["item_open", true, "The chest, stocked from its table as the level was built."],
		["wait", 30, ""],
		["item_open", false, "The brute carries what its table gave it."],
		["walk", "beside the monster", ""],
		["brawl", 260, ""],
		["wait", 40, "Beaten, it drops what it carried where it fell."],
	]


func _items_bow() -> void:
	var rows: Array[String] = ["##########################"]
	for y in 9:
		rows.append("#........................#")
	rows.append("##########################")
	var markers := {Vector2i(1, 5): "start", Vector2i(13, 4): "monster_rabbit", Vector2i(15, 6): "monster_deer"}
	var config := {"name": "Clip", "zone": "outdoors", "ambient": 0.35,
		"entities": [{"at": [13, 4], "facing": [1, 0]}, {"at": [15, 6], "facing": [1, 0]}],
		"legend": {"monster_rabbit": "#b0a080", "monster_deer": "#c08040"}}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["lantern", false, "Dusk, the lantern covered, the game facing away."],
		["item_give", ["bow", Player.RIGHT_HAND], "A hunting bow, in both hands. The right button draws it."],
		["walk", Vector2i(7, 5), "Up on them, quietly, from behind."],
		["item_raise", null, "Drawn: the longer, the stronger (full at 2 s)."],
		["wait", 22, ""],
		["item_lower", "rabbit", "Let go at the rabbit: a full draw, 4. It falls."],
		["wait", 25, ""],
		["say", 1, "The deer heard the kill and ran. Wait, still."],
		["item_raise", null, "Draw and hold it, standing still (a step would spoil it)."],
		["item_wait_near", ["deer", 8], ""],
		["item_lower", "deer", "At 8 cells, the bow's reach: loosed. Hit for 4; it bolts, wounded."],
		["wait", 50, ""],
	]


func _items_blows() -> void:
	var rows: Array[String] = [
		"###############",
		"#.............#",
		"#.............#",
		"#.............#",
		"#.............#",
		"###############",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(5, 2): "monster_brute", Vector2i(12, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [5, 2], "facing": [-1, 0], "idle": {"mode": "guard"}},
			{"at": [12, 3], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["item_give", ["hammer", Player.RIGHT_HAND], "A war hammer: no more damage than a fist, three times the push."],
		["walk", Vector2i(4, 2), "A brute, 70 kg: a fist would not move it."],
		["brawl", 90, "Each blow knocks it back."],
		["item_clear", Player.RIGHT_HAND, "A dagger: quick, light."],
		["item_give", ["dagger", Player.RIGHT_HAND], ""],
		["walk", Vector2i(11, 3), "Up behind the imp, which faces away."],
		["brawl", 40, "Quick blows; in the back, twice the damage (2, not 1)."],
		["wait", 20, ""],
	]


func _items_block() -> void:
	var rows: Array[String] = [
		"#############",
		"#...........#",
		"#...........#",
		"#...........#",
		"#############",
	]
	var markers := {Vector2i(3, 2): "start", Vector2i(6, 2): "monster_imp", Vector2i(11, 2): "monster_brute"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [6, 2], "facing": [-1, 0]}, {"at": [11, 2], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["item_bold", "imp", "A round shield in the left hand."],
		["item_give", ["shield", Player.LEFT_HAND], ""],
		["walk", "beside the monster", "Up between an imp and a brute."],
		["item_face", "imp", ""],
		["item_raise", null, "Shield up, toward the imp: its blows are taken on it, for stamina."],
		["wait", 70, ""],
		["say", 80, "The brute is behind, outside the shield's arc: its blows land."],
		["say", 40, "Out of stamina, the guard gives way: a stagger."],
	]


func _items_axe() -> void:
	var rows: Array[String] = [
		"###########",
		"#.........#",
		"#.........#",
		"#.........#",
		"#.........#",
		"#.........#",
		"###########",
	]
	var markers := {Vector2i(2, 3): "start", Vector2i(5, 2): "monster_imp", Vector2i(5, 3): "monster_imp", Vector2i(5, 4): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [5, 2], "facing": [-1, 0], "idle": {"mode": "guard"}}, {"at": [5, 3], "facing": [-1, 0], "idle": {"mode": "guard"}},
			{"at": [5, 4], "facing": [-1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["item_give", ["giant_axe", Player.RIGHT_HAND], "A giant axe: both hands, slow."],
		["walk", Vector2i(4, 3), "Three imps in a row."],
		["item_strike", Vector2i(5, 3), "One swing takes the cell ahead and the two beside it."],
		["wait", 12, "All three knocked down: lying, they cannot act."],
		["wait", 25, "1.5 s later they are up."],
		["item_strike", Vector2i(5, 3), "And again."],
		["wait", 30, ""],
	]


func _items_spear() -> void:
	var rows: Array[String] = ["################"]
	for y in 7:
		rows.append("#..............#")
	rows.append("################")
	var markers := {Vector2i(3, 4): "start", Vector2i(7, 4): "monster_boar"}
	var config := {"name": "Clip", "zone": "outdoors", "ambient": 0.9,
		"entities": [{"at": [7, 4], "facing": [1, 0]}], "legend": {"monster_boar": "#705040"}}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["item_give", ["bow", Player.RIGHT_HAND], "A boar runs from you, into a corner."],
		["walk", Vector2i(8, 4), ""],
		["item_raise", null, "Draw, standing still..."],
		["wait", 22, ""],
		["item_lower", "boar", "...and shoot: struck, it turns and charges."],
		["item_clear", Player.RIGHT_HAND, ""],
		["item_give", ["spear", Player.RIGHT_HAND], "The spear, still standing: braced."],
		["item_face", "boar", ""],
		["say", 100, "The charge breaks on the spear, and the boar is thrown back."],
	]


func _items_pickup() -> void:
	var rows: Array[String] = [
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(6, 2): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9, "entities": [{"at": [6, 2], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["item_give", ["dagger", Player.RIGHT_HAND], "A dagger in hand; an imp, facing away."],
		["walk", Vector2i(4, 2), ""],
		["item_key", ["drop", null], "G: the dagger put down beside it."],
		["walk", Vector2i(2, 2), ""],
		["item_pick", null, "The imp takes it up: it has a hand for it."],
		["wait", 60, "Armed, and heavier by it."],
	]


func _items_buffs() -> void:
	var rows: Array[String] = [
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(3, 1): "chest", Vector2i(7, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9,
		"entities": [{"at": [3, 1], "props": {"slots": ["ration", "", "", ""]}},
			{"at": [7, 3], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["walk", Vector2i(3, 2), "A chest: a travel ration."],
		["item_open", true, ""],
		["item_take", [0, 0], "Into the pack."],
		["item_open", false, ""],
		["wait", 20, ""],
		["item_use", 0, "Right click it: eaten. Fed: 10 kg heavier, harder to shove (top left)."],
		["wait", 60, "It wears off in three minutes; buffs never take you below what you were."],
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


func _wild() -> void:
	var rows: Array[String] = ["########################################"]
	for y in 12:
		rows.append("#......................................#")
	rows.append("########################################")
	var markers := {Vector2i(3, 6): "start"}
	var entities: Array = []
	for at: Vector2i in [Vector2i(16, 5), Vector2i(17, 7), Vector2i(15, 7)]:
		markers[at] = "monster_deer"
		entities.append({"at": [at.x, at.y], "facing": [1, 0]})
	markers[Vector2i(18, 6)] = "monster_stag"
	entities.append({"at": [18, 6], "facing": [1, 0]})
	markers[Vector2i(36, 6)] = "monster_wolf"
	entities.append({"at": [36, 6], "facing": [-1, 0]})
	# Animals are placed by herds, not markers: the clip's own legend has them.
	var config := {"name": "Clip", "zone": "outdoors", "entities": entities,
		"legend": {"monster_deer": "#c08040", "monster_stag": "#a06030", "monster_wolf": "#808890"}}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	_script = [
		["say", 60, "A herd grazes, heads down between strolls. Far off, a wolf."],
		["walk", Vector2i(10, 6), "Walk up on them: a step heard, a head comes up (?)..."],
		["walk", Vector2i(12, 6), "...seen, one bolts (~), and the herd with it."],
		["say", 200, "Running from you, toward the wolf: it goes for a doe."],
	]


func _raid() -> void:
	var rows: Array[String] = [
		"################################",
		"#..............................#",
		"#..............................#",
		"#..............................#",
		"#..............................#",
		"#..............................#",
		"################################",
	]
	var config := {"name": "Clip", "ambient": 1.0, "entities": []}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(rows), {Vector2i(22, 3): "start"}, config), null, config)
	_script = [
		["say", 20, "A raiding party comes in from the west, for the town's store in the east."],
		["raid", [{"id": "clip_raid", "faction": "goblins", "strength": 6.0, "town": "clip_town"}, Vector2i(2, 3), Vector2i(29, 3)],
			"Real goblins, as many as the party is strong."],
		["say", 120, "They march on the town."],
		["brawl", 400, "Stand in their way: they fight like any goblin; all down or running, the raid is beaten."],
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


## A plain room and the player; the script plays the reel's slots.
func _sound_reel() -> void:
	var cells: Array[String] = ["#######", "#.....#", "#.....#", "#.....#", "#######"]
	var markers := {Vector2i(3, 2): "start", Vector2i(5, 3): "monster_imp"}
	var config := {"name": "Clip", "ambient": 0.9, "entities": [{"at": [5, 3], "facing": [-1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(cells), markers, config), null, config)
	var slots: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slots="):
			slots = Array(arg.trim_prefix("--slots=").split(",", false))
	if slots.is_empty():
		slots = SoundKit.all_takes().keys()
		slots.sort()
	_script = [["say", 20, "Sound reel: %d slots, each take once." % slots.size()]]
	for slot: String in slots:
		var takes := SoundKit.takes(slot)
		var from: String = str(takes[0].get("original", "")) if not takes.is_empty() else "no takes"
		_script.append(["sound_reel_play", slot, "%s (%d)\n%s" % [slot, takes.size(), str(from).get_file().left(70)]])


## An open field, outdoors, a fire at its east end, an imp held at the far
## side; the script runs the clock and the weather.
func _sound_ambience() -> void:
	var cells: Array[String] = [
		"#################",
		"#...............#",
		"#.............~.#",
		"#...............#",
		"#################",
	]
	var markers := {Vector2i(2, 2): "start", Vector2i(2, 1): "monster_imp"}
	var config := {"name": "Clip", "zone": "outdoors", "ambient": 0.9,
		"entities": [{"at": [2, 1], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	Level.register(NAME, Level.image_from_rows(Terrain.expand(cells), markers, config), null, config)
	_script = [
		["sound_hour", 6.2, "Dawn, outdoors: the dawn chorus."],
		["wait", 50, ""],
		["sound_hour", 12.0, "Noon: the forest by day."],
		["wait", 50, ""],
		["sound_hour", 19.5, "Dusk: day giving way to night."],
		["wait", 40, ""],
		["sound_hour", 0.0, "Midnight: crickets and owls."],
		["wait", 50, ""],
		["sound_hour", 12.0, ""],
		["sound_weather", "rain", "Rain (hurried for the clip): the birds go quiet."],
		["wait", 60, ""],
		["sound_weather", "storm", "A storm."],
		["wait", 60, ""],
		["sound_weather", "clear", "Clear again."],
		["walk", Vector2i(13, 2), "To the fire: it crackles within 4 cells."],
		["wait", 40, ""],
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
		"item_give":
			World.put_item(_player, _player, int(step[1][1]), World.items.mint(str(step[1][0]), "built", "clip"))
		"item_raise":
			# Raised by command, not through Main, which would turn the body to
			# wherever the clip's cursor happens to be.
			World.command(_player, "stance", {"kind": World.off_hand(_player)})
		"item_lower":
			var aim: Variant = step[1]
			if aim is String:
				aim = null
				for entity in World.monsters():
					if str(entity.spawn_spec.get("kind", "")) == step[1]:
						aim = entity.tile
			if aim is Vector2i and _player.raised == "draw":
				World.command(_player, "loose", {"at": [aim.x, aim.y]})
			else:
				World.command(_player, "stance", {"kind": ""})
		"item_wait_near":
			# Waits until a monster of kind step[1][0] is within step[1][1] cells.
			var near := false
			for entity in World.monsters():
				if str(entity.spawn_spec.get("kind", "")) == step[1][0] and World.distance(_player.tile, entity.tile) <= int(step[1][1]):
					near = true
			if not near:
				return
		"item_face":
			# The player turns to the first monster of kind step[1].
			for entity in World.monsters():
				if str(entity.spawn_spec.get("kind", "")) == step[1]:
					World.face(_player, Vector2i(signi(entity.tile.x - _player.tile.x), signi(entity.tile.y - _player.tile.y)))
					break
		"item_strike":
			# A blow at whoever stands on cell step[1], once the player can strike.
			var struck: GridEntity = World.get_entity_at(step[1])
			if struck != null and not World.try_attack(_player, struck):
				return
		"item_pick":
			# The first monster takes up a weapon beside it, when there is one.
			if not World.try_pick_up_weapon(_monster):
				return
		"item_bold":
			# The clip's monsters of kind step[1] made bold, so they close in.
			for entity in World.monsters():
				if str(entity.spawn_spec.get("kind", "")) == step[1]:
					(entity as Monster).temper = Monster.Temper.BOLD
		"item_clear":
			World.items.end(World.take_item(_player, _player, int(step[1])), "gone")
		"item_e":
			_main._e_target = _chest()
			_main._e_held = true
			_main._e_since = Time.get_ticks_msec()
			_main._release_e()
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
		"sound_reel_play":
			# Each take of the slot once, REEL_TICKS apart.
			var count := maxi(SoundKit.takes(step[1]).size(), 1)
			if _repeat_until < 0:
				_repeat_until = tick + REEL_TICKS * (count + 1)
			if tick < _repeat_until:
				var played := count + 1 - ceili(float(_repeat_until - tick) / REEL_TICKS)
				if (_repeat_until - tick) % REEL_TICKS == 0 and played < count:
					var view: Client3D = _main._client3d
					view.sfx.hear_everything = true
					view.sfx.next_take[str(step[1])] = played
					view.play_at(str(step[1]), _player)
				return
			_repeat_until = -1
		"sound_hour":
			DayNight.set_hour(float(step[1]))
		"sound_weather":
			# Hurried for the clip: the override backdated, so it is in full
			# at once (in play a turn takes minutes).
			Weather.set_override("all", str(step[1]), 30.0)
			for region: String in Weather.overrides:
				Weather.overrides[region]["from"] = World.steps - 1000000
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
		"raid":
			var town: Vector2i = step[1][2]
			World.raids.town_cell = func(_town: String, _area: String) -> Vector2i: return town
			World.raids.on_town = func(_town: String, cell: Vector2i) -> bool: return World.distance(cell, town) <= 1
			World.raids.arrive = func(at: String, group: Dictionary) -> Dictionary:
				print("[clip] tick %d: the raid reaches %s with %.1f" % [World.tick, at, group["strength"]])
				return {"repelled": false, "took": {"items": []}, "captives": []}
			World.raids.raid_beaten.connect(func(id: String, _area: String, cell: Vector2i) -> void:
				print("[clip] tick %d: %s beaten at %s" % [World.tick, id, cell]))
			World.raids.enter(step[1][0], World.zone.name, step[1][1])
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
	if scenario in ["pack", "raid", "wild"]:
		var each: Array[String] = []
		for entity in World.monsters():
			var monster := entity as Monster
			each.append("%s %s at %s hp %d %s" % [monster.name, Monster.Temper.keys()[monster.temper], monster.tile, monster.hp,
				Monster.Alert.keys()[monster.alert]])
		print("[clip] tick %d: player %s; %s" % [tick, _player.tile, "; ".join(each)])
		return
	if scenario in ["sounds", "sound_hearing", "sound_reel", "sound_ambience"]:
		var sfx: Sfx = _main._client3d.sfx if _main._client3d != null else null
		if sfx != null:
			for entry: Array in sfx.played.slice(_sounds_logged):
				print("[clip] tick %d: played %s (%s) on %s, heard from %s" % [tick, entry[0], str(entry[1]).get_file() if entry[1] != "" else "placeholder", entry[2], sfx.listener])
			_sounds_logged = sfx.played.size()
			if scenario == "sound_ambience" and tick % 10 == 0:
				var beds: Array[String] = []
				for bed: String in _main._client3d.ambience.levels:
					if _main._client3d.ambience.levels[bed] >= 0.05:
						beds.append("%s %.2f" % [bed, _main._client3d.ambience.levels[bed]])
				var torch: AudioStreamPlayer3D = _main._client3d.ambience._torch
				print("[clip] tick %d: hour %.1f, weather %s; beds %s; torch %s" % [tick, DayNight.hour(DayNight.now()),
					World.fields.weather.get("kind", "?"), ", ".join(beds),
					"%.1f dB" % torch.volume_db if torch != null and torch.playing else "off"])
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
	if scenario == "items_buffs":
		print("[clip] tick %d: player slots %s mass %.1f buffs %s" % [tick, _player.slots, _player.mass, _player.buffs])
		return
	if scenario == "items_icons":
		var shown: Array[String] = []
		for i in _player.slots.size():
			shown.append("%s%s" % [_main.pack_panel.shown_in(true, i), "*" if _main.pack_panel.icon_in(true, i) != null else ""])
		print("[clip] tick %d: pack %s (* an icon)" % [tick, shown])
		return
	if scenario in ["items_axe", "items_spear"]:
		var them := []
		for entity in World.monsters():
			them.append("%s at %s hp %d %s%s" % [entity.name, entity.tile, entity.hp, Monster.Alert.keys()[entity.alert], " DOWN" if World.is_down(entity) else ""])
		print("[clip] tick %d: player %s hp %d; %s" % [tick, _player.tile, _player.hp, ", ".join(them)])
		return
	if scenario == "items_pickup":
		var hands := "gone"
		if is_instance_valid(_monster):
			hands = "%s at %s mass %.1f hands %s" % [_monster.name, _monster.tile, _monster.mass, _monster.slots]
		print("[clip] tick %d: player %s hands %s; ground %s; %s" % [tick, _player.tile, [_player.slots[Player.RIGHT_HAND], _player.slots[Player.LEFT_HAND]],
			World.zone.ground.keys(), hands])
		return
	if scenario == "items_block":
		var them := []
		for entity in World.monsters():
			them.append("%s at %s" % [entity.name, entity.tile])
		print("[clip] tick %d: player %s hp %d stamina %d raised %s%s; %s" % [tick, _player.tile, _player.hp, _player.stamina,
			_player.raised, " stunned" if World.is_stunned(_player) else "", ", ".join(them)])
		return
	if scenario in ["items_bow", "items_blows"]:
		var game := []
		for entity in World.monsters():
			game.append("%s at %s hp %d %s" % [entity.name, entity.tile, entity.hp, Monster.Alert.keys()[entity.alert]])
		print("[clip] tick %d: player %s %s %.2f; %s" % [tick, _player.tile, _player.raised, World.draw_of(_player), ", ".join(game)])
		return
	if scenario == "items_loot":
		var lying := []
		for cell: Vector2i in World.zone.ground:
			lying.append([cell, World.ground_at(cell)])
		print("[clip] tick %d: player %s; %s; ground %s" % [tick, _player.tile,
			"%s at %s carries %s" % [_monster.name, _monster.tile, _monster.slots] if is_instance_valid(_monster) else "the brute fallen", lying])
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
