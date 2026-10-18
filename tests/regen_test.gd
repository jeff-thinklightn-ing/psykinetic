extends Node
## Regenerating levels (decision 465): a level marked "regenerate" is laid
## again by its generator, its anchors verbatim, when its days are up and
## nobody is in it, or before anyone travels into it. Generations differ
## outside the anchors and match inside; the anchors reach each other; the
## same seed gives the same map; an awake zone is never regenerated; floor
## items outside the anchors are lost and those inside kept; the level goes
## to the overlay, so clients are sent its terrain and the "map" message
## says its generation; coming back at a newer generation is told; a player
## saved in what is now rock comes back at the nearest anchor's spawn, their
## companion beside them; an edited, unmarked level is never written over;
## the castle is never marked. Run it with tests/run.ps1 or tests/run.sh.

const BO := 2
const BO_ID := "b0b0b0b0-0000-4000-8000-0000000000b1"
const SIZE := Vector2i(25, 17)
const GATE := Rect2i(1, 1, 5, 5)
const DEEP := Rect2i(19, 11, 5, 5)
const ANCHORS := [{"rect": [1, 1, 5, 5], "name": "gatehouse"}, {"rect": [19, 11, 5, 5], "name": "deep"}]
const SHIFTED := "The ways have shifted since you were last here."

var _failures := 0
var _main: Node
var _party: Array[String] = []
var _period := 0


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17860)
	Net.companions = true
	Net.map_name = "rg_castle"
	Net.state_path = preload("res://tests/test_ports.gd").scratch_path("regen_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	# The overlay of this test's own: never the shared user://levels.
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("regen_overlay/")
	for level_name in ["rg_halls", "rg_edited"]:
		BuilderHost.remove_overlay(level_name)
	_register_levels()
	_period = 3 * DayNight.day_steps
	Net.message_received.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			_party.append(str(data.get("text", ""))))
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_main.load_map("rg_castle")
	for i in 3:
		World.step()

	_test_generator()
	_test_marking()
	await _test_travel_when_due()
	_test_never_awake()
	await _test_asleep_regenerates()
	await _test_back_at_a_newer_generation()
	await _test_returning_player_placed()
	_test_edited_level_refused()
	_test_saved()
	_test_castle_never_marked()

	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Levels made in code ------------------------------------------------------------

## Rows in Terrain's double resolution, SIZE cells, floor in [param rects]
## and void elsewhere.
static func _rows(rects: Array[Rect2i]) -> Array[String]:
	var rows: Array[String] = []
	for py in SIZE.y * 2 - 1:
		var row := ""
		for px in SIZE.x * 2 - 1:
			var floor_here := false
			if px % 2 == 0 and py % 2 == 0:
				for rect in rects:
					if rect.has_point(Vector2i(px / 2, py / 2)):
						floor_here = true
			row += "." if floor_here else " "
		rows.append(row)
	return rows


static func _halls_config() -> Dictionary:
	return {"name": "The Halls", "starts": [[3, 3]], "spawn_points": {"from_castle": [3, 4], "deep": [21, 12]},
		"links": [{"at": [2, 2], "to_map": "rg_castle", "to_spawn": "from_halls"}],
		"entities": [{"at": [21, 13], "name": "DeepChest", "props": {"slots": ["bandaging_kit", "", "", ""]}}],
		"places": {"gatehouse": {"at": [3, 3], "kind": "gate", "radius": 2}, "shrine": {"at": [10, 8], "kind": "other", "radius": 2}},
		"regenerate": {"generator": "maze", "every_days": 3, "anchors": ANCHORS, "monsters": {"imp": 3}}}


func _register_levels() -> void:
	# The halls: two anchor rooms, a link and a spawn point in the
	# gatehouse, a chest and a spawn point in the deep room, and, outside
	# every anchor, an imp marker and a shrine the generation drops.
	var halls := Level.image_from_rows(_rows([GATE, DEEP, Rect2i(10, 8, 1, 1)]),
		{Vector2i(2, 2): "link", Vector2i(21, 13): "chest", Vector2i(10, 8): "monster_imp"})
	Level.register("rg_halls", halls, null, _halls_config())
	# The castle above: persistent, a link down to the halls.
	Level.register("rg_castle", Level.image_from_rows(_rows([Rect2i(1, 1, 6, 6)]), {Vector2i(2, 2): "start", Vector2i(5, 5): "link"}), null,
		{"name": "The Castle", "spawn_points": {"from_halls": [4, 4]}, "links": [{"at": [5, 5], "to_map": "rg_halls", "to_spawn": "from_castle"}]})
	# A marked level that also sits in the overlay, edited there without the
	# mark (as builder mode leaves a level): never written over.
	var edited := Level.image_from_rows(_rows([GATE, DEEP]), {Vector2i(3, 3): "start"})
	Level.register("rg_edited", edited, null, {"starts": [[3, 3]], "regenerate": {"anchors": ANCHORS}})
	var folder := ProjectSettings.globalize_path(Level.overlay_dir + "rg_edited")
	DirAccess.make_dir_recursive_absolute(folder)
	edited.save_png(folder.path_join("layout.png"))
	var json := FileAccess.open(folder.path_join("level.json"), FileAccess.WRITE)
	json.store_string("{\"name\": \"Edited by hand\"}\n")
	json.close()


# --- Tests ----------------------------------------------------------------------

func _test_generator() -> void:
	print("\n== the maze generator: anchors verbatim, the rest new each generation, joined up, reproducible ==")
	var first := Regen.generate("rg_halls", 1)
	var second := Regen.generate("rg_halls", 2)
	_check(not first.is_empty() and not second.is_empty(), "generations 1 and 2 are made (%d and %d tries)" % [first.get("tries", 0), second.get("tries", 0)])
	if first.is_empty() or second.is_empty():
		return
	var config: Dictionary = first["config"]
	var template := LevelMap.from_image(Level.template("rg_halls")["layout"], config)
	var a := LevelMap.from_image(first["layout"], config)
	var b := LevelMap.from_image(second["layout"], config)
	var inside_same := true
	var outside_differ := 0
	var outside_floor := 0
	for y in SIZE.y:
		for x in SIZE.x:
			var cell := Vector2i(x, y)
			if GATE.has_point(cell) or DEEP.has_point(cell):
				if a.cell(cell) != template.cell(cell) or b.cell(cell) != template.cell(cell):
					inside_same = false
				for side in [Terrain.EAST, Terrain.SOUTH]:
					var key := Vector3i(x, y, side)
					if a.edge(key) != template.edge(key) or b.edge(key) != template.edge(key):
						inside_same = false
			else:
				if a.cell(cell) != b.cell(cell):
					outside_differ += 1
				if a.walkable(cell):
					outside_floor += 1
	_check(inside_same, "inside the anchors both are the template, cell for cell and edge for edge")
	_check(outside_differ > 20, "outside them they differ (%d cells)" % outside_differ)
	_check(outside_floor > 40, "the corridors fill the rock between (%d cells carved)" % outside_floor)
	var anchors: Array = Level.regenerate_from(config, []).get("anchors", [])
	_check(Regen.connected(a, anchors) and Regen.connected(b, anchors), "every anchor reaches every other in both")
	var again := Regen.generate("rg_halls", 1)
	_check(again["seed"] == first["seed"] and again["layout"].get_data() == first["layout"].get_data(),
		"the same seed gives the same map (seed %d)" % first["seed"])
	_check(first["seed"] != second["seed"], "another generation, another seed")
	var level := Level.parse(first["layout"], null, config)
	var imps: Array = level["entities"].filter(func(spec: Dictionary) -> bool: return spec.get("kind", "") == "imp" or str(spec["name"]).begins_with("Imp"))
	var chests: Array = level["entities"].filter(func(spec: Dictionary) -> bool: return spec["name"] == "DeepChest")
	_check(imps.size() == 3 and imps.all(func(spec: Dictionary) -> bool: return not Level.in_anchors(anchors, spec["tile"])),
		"three imps laid from the config's monsters, in the corridors (%s)" % [imps.map(func(spec: Dictionary) -> Vector2i: return spec["tile"])])
	_check(chests.size() == 1 and chests[0]["tile"] == Vector2i(21, 13), "the deep room's chest is there, as listed")
	_check(level["links"].size() == 1 and level["spawn_points"].size() == 2 and level["starts"] == [Vector2i(3, 3)],
		"the link, both spawn points and the start are kept (%s)" % [level["warnings"]])
	_check(config["places"].keys() == ["gatehouse"] and not config["entities"].any(func(entry: Dictionary) -> bool: return entry["at"] == [10, 8]),
		"the shrine and the imp outside every anchor are dropped from level.json (%s)" % [config["places"].keys()])
	_check(level["warnings"].is_empty() and int(config["generation"]) == 1, "no warnings, generation 1 written in (%s)" % [level["warnings"]])


func _test_marking() -> void:
	print("\n== marking: level.json \"regenerate\", read and checked ==")
	var warnings: Array[String] = []
	var read := Level.regenerate_from(_halls_config(), warnings)
	_check(read["generator"] == "maze" and read["every_days"] == 3 and read["anchors"].size() == 2 and read["anchors"][1]["rect"] == DEEP
		and read["monsters"] == {"imp": 3} and warnings.is_empty(), "the block reads back (%s; %s)" % [read, warnings])
	_check(Level.regenerate_from({}, warnings).is_empty() and Regen.marked("rg_halls") and not Regen.marked("rg_castle"),
		"a level without it does not regenerate; the halls do, the castle does not")
	var bad: Array[String] = []
	Level.regenerate_from({"regenerate": {"generator": "no such thing!", "anchors": [{"name": "x"}]}}, bad)
	var bad_text := "\n".join(bad)
	_check(bad.size() == 3 and bad_text.contains("plain word") and bad_text.contains("no \"rect\"") and bad_text.contains("no anchors"),
		"a generator that is no word, an anchor with no rect and no anchors left are said (%s)" % [bad])
	var outside := Level.image_from_rows(_rows([GATE, Rect2i(12, 8, 3, 3)]), {Vector2i(13, 9): "link", Vector2i(3, 3): "start"})
	var level := Level.parse(outside, null, {"links": [{"at": [13, 9], "to_map": "rg_castle", "to_spawn": ""}],
		"spawn_points": {"out": [12, 8]}, "regenerate": {"anchors": [{"rect": [1, 1, 5, 5]}]}})
	var said: Array = level["warnings"].filter(func(text: String) -> bool: return text.contains("outside every anchor"))
	_check(said.size() == 2 and str(said).contains("link at (13, 9)") and str(said).contains("spawn point out"),
		"a link and a spawn point outside every anchor warn (%s)" % [level["warnings"]])
	_check(Regen.due({"generation": 0, "at_step": 0}, read, 0) and not Regen.due({"generation": 1, "at_step": 100}, read, 100 + _period - 1)
		and Regen.due({"generation": 1, "at_step": 100}, read, 100 + _period) and not Regen.due({"generation": 0, "at_step": 50}, read, 60),
		"due: never made, or every_days gone by since the last generation or try")


func _test_travel_when_due() -> void:
	print("\n== travel into a level never made: laid first, then arrived in ==")
	_check(_main.generation_of("rg_halls") == 0 and not Level.overlaid("rg_halls"), "nothing made yet")
	# The world map read the template (as a level under levels/ is at boot):
	# the shrine outside every anchor is a place, and the host knows it.
	var names := Level.names()
	names.append_array(["rg_halls", "rg_castle"])
	World.holdings.rebind(WorldMap.build(names))
	_check(World.holdings.places_in("rg_halls") == ["rg_halls/gatehouse", "rg_halls/shrine"], "the template's places are held (%s)" % [World.holdings.places_in("rg_halls")])
	var record: PlayerRecord = _main._records[Net.player_id]
	record.known_places = ["rg_halls/gatehouse", "rg_halls/shrine"]
	_main.world_state["known_places"] = ["rg_halls/gatehouse", "rg_halls/shrine"]
	_check(_main.travel(Net.local_id, "rg_halls", "from_castle"), "the host goes down")
	await get_tree().process_frame
	var host := _player(Net.local_id)
	_check(_main.generation_of("rg_halls") == 1, "generation 1 was laid first (%d)" % _main.generation_of("rg_halls"))
	_check(host != null and host.zone == "rg_halls" and GATE.has_point(host.tile), "the host arrives in the gatehouse (%s)" % [host.tile if host else null])
	_check(record.known_places == ["rg_halls/gatehouse"] and _main.world_state["known_places"] == ["rg_halls/gatehouse"],
		"the shrine, outside, left the host's known places and map (%s)" % [_main.world_state["known_places"]])
	_check(Level.overlaid("rg_halls") and FileAccess.file_exists(Level.overlay_dir + "rg_halls/level.json"),
		"the level is in the overlay, so Level.overlaid sends the terrain message")
	var message: Dictionary = _main.map_message("rg_halls")
	_check(message["name"] == "rg_halls" and message["generation"] == 1 and _main.map_message("rg_castle")["generation"] == 0,
		"the \"map\" message says generation 1 (0 for the castle): %s" % [message])
	var made := Regen.generate("rg_halls", 1)
	_check(_same_floor(made["layout"]), "the zone's floor is generation 1's map")
	var level := Level.load_level("rg_halls")
	_check(level["entities"].size() == 4 and World.zones["rg_halls"].entities.filter(func(e: GridEntity) -> bool: return e is Monster).size() == 3,
		"its chest and three imps stand in it")
	_check(_party.is_empty(), "a first visit says nothing of shifting (%s)" % [_party])
	_check(World.holdings.places_in("rg_halls") == ["rg_halls/gatehouse"], "the holdings have the gatehouse, not the shrine outside (%s)" % [World.holdings.places_in("rg_halls")])


func _test_never_awake() -> void:
	print("\n== never while awake: the host stands in it, its days are up ==")
	World.steps += _period
	_main._regenerate_due()
	_check(_main.generation_of("rg_halls") == 1, "due, but the host is in it: still generation 1")
	for i in World.WORLD_TICK_STEPS:
		World.step()
	_check(_main.generation_of("rg_halls") == 1, "the slow tick passes it over too")


func _test_asleep_regenerates() -> void:
	print("\n== asleep and due: laid again on the slow tick; what lies outside the anchors is lost ==")
	var was := World.enter_named("rg_halls")
	var outside := _corridor_cell()
	var lost_uid := World.items.mint("bandaging_kit", "test", "", "rg_halls", outside)
	World.put_on_ground(lost_uid, outside)
	var kept_uid := World.items.mint("bandaging_kit", "test", "", "rg_halls", Vector2i(22, 14))
	World.put_on_ground(kept_uid, Vector2i(22, 14))
	var chest: GridEntity = World.zones["rg_halls"].entities.filter(func(e: GridEntity) -> bool: return e.name == "DeepChest")[0]
	var chest_uid := World.slot_uids(chest)[0]
	World.enter(was)
	_check(_main.travel(Net.local_id, "rg_castle", "from_halls"), "the host goes back up")
	await get_tree().process_frame
	World.step()
	World.step()
	_check(not World.zones["rg_halls"].awake, "the halls sleep")
	var richness_before := World.richness
	_main._regenerate_due()
	_check(World.richness != null and World.richness != richness_before and World.herds.richness == World.richness.richness,
		"the game's richness is worked out again on the new floor, the herds pointed at it")
	_check(World.raid_groups != null and World.raid_groups.world_map == _main._world_map and World.richness.world_map == _main._world_map,
		"the raid groups and the richness hold the world map built on it")
	_check(_main.generation_of("rg_halls") == 2, "generation 2 is laid (%d)" % _main.generation_of("rg_halls"))
	_check(_same_floor(Regen.generate("rg_halls", 2)["layout"]), "the zone stands on generation 2's map")
	_check(not World.items.has(lost_uid), "the thing in the corridor is lost")
	_check(World.items.at_of(kept_uid) == "rg_halls@22,14", "the thing in the deep room lies where it was (%s)" % World.items.at_of(kept_uid))
	var again: Array = World.zones["rg_halls"].entities.filter(func(e: GridEntity) -> bool: return e.name == "DeepChest")
	_check(again.size() == 1 and World.slot_uids(again[0])[0] == chest_uid, "the chest in the deep room keeps its things (uid %d)" % chest_uid)
	_check(World.zones["rg_halls"].entities.filter(func(e: GridEntity) -> bool: return e is Monster).size() == 3, "three imps again, from the new markers")
	_check(World.holdings.places_in("rg_halls") == ["rg_halls/gatehouse"], "the gatehouse is still held, the shrine still gone")


func _test_back_at_a_newer_generation() -> void:
	print("\n== back at a newer generation: told once ==")
	_party.clear()
	_check(_main.travel(Net.local_id, "rg_halls", "from_castle"), "the host goes down again")
	await get_tree().process_frame
	_check(_party == [SHIFTED], "and is told (%s)" % [_party])
	_check(_main._records[Net.player_id].seen_generation["rg_halls"] == 2, "generation 2 seen now")
	_party.clear()
	_main.travel(Net.local_id, "rg_castle", "from_halls")
	await get_tree().process_frame
	_main.travel(Net.local_id, "rg_halls", "from_castle")
	await get_tree().process_frame
	_check(_party.is_empty(), "up and down again with no generation between: nothing said")
	_main.travel(Net.local_id, "rg_castle", "from_halls")
	await get_tree().process_frame


func _test_returning_player_placed() -> void:
	print("\n== a player saved in what is now rock comes back at the nearest anchor's spawn ==")
	_main._admit(BO, BO_ID, "Bo")
	_check(_main.travel(BO, "rg_halls", "deep"), "Bo goes down to the deep room")
	await get_tree().process_frame
	var bo := _player(BO)
	var was := World.enter_named("rg_halls")
	var corridor := _corridor_cell(Vector2i(14, 10))
	World._relocate(bo, corridor)
	World.enter(was)
	_main._on_peer_disconnected(BO)
	var record: PlayerRecord = _main._records[BO_ID]
	_check(record.zone == "rg_halls" and record.tile == corridor, "Bo leaves standing in a corridor at %s" % [corridor])
	var pet: Companion = _main._companions.get(BO_ID)
	_check(pet != null and pet.zone == "rg_halls", "his companion waits there")
	World.step()
	World.step()
	World.steps += _period
	_main._regenerate_due()
	_check(_main.generation_of("rg_halls") == 3 and not World.zones["rg_halls"].awake, "the halls, asleep, are laid again: generation 3")
	_main._admit(BO, BO_ID, "Bo")
	bo = _player(BO)
	var spawn: Variant = Regen.anchor_spawn_near(Level.load_level("rg_halls"), corridor)
	_check(spawn == Vector2i(21, 12), "the nearest anchor spawn to %s is the deep room's (%s)" % [corridor, spawn])
	_check(bo != null and bo.zone == "rg_halls" and World.distance(bo.tile, Vector2i(21, 12)) <= 1, "Bo is back there (%s)" % [bo.tile if bo else null])
	pet = _main._companions.get(BO_ID)
	_check(bo != null and pet != null and pet.zone == "rg_halls" and World.distance(pet.tile, bo.tile) <= 2, "his companion beside him (%s)" % [pet.tile if pet else null])
	_check(record.seen_generation["rg_halls"] == 3, "generation 3 seen")


func _test_edited_level_refused() -> void:
	print("\n== a level edited in the game, in the overlay without the mark, is never written over ==")
	var before := FileAccess.get_file_as_string(Level.overlay_dir + "rg_edited/level.json")
	var made := Regen.generate("rg_edited", 1)
	_check(not made.is_empty() and Level.overlaid("rg_edited"), "a map is made for it, and it sits in the overlay")
	_check(not Regen.write("rg_edited", made), "the write is refused")
	_check(FileAccess.get_file_as_string(Level.overlay_dir + "rg_edited/level.json") == before, "its level.json is as it was")
	World.steps += _period
	_main._regenerate_due()
	_check(_main.generation_of("rg_edited") == 0 and _main._regen["rg_edited"]["at_step"] == World.steps,
		"the tick leaves it at generation 0 and waits a period before trying again")
	_check(_main.generation_of("rg_halls") == 3, "the halls, with Bo just come in and the step not yet taken, stay as they are")


func _test_saved() -> void:
	print("\n== saved: the generations in the snapshot, the seen generations in the records ==")
	_main._save_state()
	var snapshot := Snapshot.load(Net.state_path)
	_check(snapshot["ok"] and snapshot["regen"].get("rg_halls", {}).get("generation") == 3.0, "the snapshot's regen says generation 3 (%s)" % [snapshot.get("regen")])
	_check(Regen.states_from(snapshot["regen"])["rg_halls"] == {"generation": 3, "at_step": int(_main._regen["rg_halls"]["at_step"])}, "and reads back")
	var record := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(_main._records[BO_ID].to_dict())))
	_check(record.seen_generation == {"rg_halls": 3}, "Bo's record keeps what he saw (%s)" % [record.seen_generation])
	var old: Dictionary = _main._records[BO_ID].to_dict()
	old.erase("seen_generation")
	_check(PlayerRecord.from_dict(old).seen_generation.is_empty(), "a record from before has seen none")


func _test_castle_never_marked() -> void:
	print("\n== the castle stays persistent: no real level is marked ==")
	_check(not Regen.marked("castle"), "levels/castle is not marked \"regenerate\"")
	var marked: Array[String] = []
	for level_name in Level.names():
		if not level_name.begins_with("rg_") and Regen.marked(level_name):
			marked.append(level_name)
	_check(marked.is_empty(), "nor is any level under levels/ (%s)" % [marked])


# --- Helpers ----------------------------------------------------------------------

func _player(peer: int) -> Player:
	var player: Player = _main._players.get(peer)
	return player if is_instance_valid(player) and player.spawned else null


## Whether the halls zone's floor is [param layout]'s.
func _same_floor(layout: Image) -> bool:
	var parsed := Level.parse(layout, null, Level.source("rg_halls")["config"])
	var zone: Zone = World.zones["rg_halls"]
	var floor_cells: Dictionary = zone.floor if World.zone != zone else World._floor
	var wanted: Array = parsed["terrain"]["floor"]
	if floor_cells.size() != wanted.size():
		return false
	for cell: Vector2i in wanted:
		if not floor_cells.has(cell):
			return false
	return true


## A floor cell of the halls outside every anchor, the nearest to
## [param near]; World must be in the halls.
func _corridor_cell(near := Vector2i(12, 8)) -> Vector2i:
	var anchors: Array = [{"rect": GATE}, {"rect": DEEP}]
	var best := Vector2i(-1, -1)
	var best_d := 0
	for cell in World.floor_cells():
		if Level.in_anchors(anchors, cell) or not World.is_free(cell):
			continue
		var d := absi(cell.x - near.x) + absi(cell.y - near.y)
		if best.x < 0 or d < best_d:
			best = cell
			best_d = d
	return best


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
