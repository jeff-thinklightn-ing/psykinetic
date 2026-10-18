extends Node
## Snagfin's round trip (decision 471, npc's side): a save shaped like
## today's box holds the imp as a level monster at his marker, with things
## in his slots; the level now says that marker "became" the settled
## resident (enemy-ai's hand-over), so one load seats him in his town
## through economy's door, banks what he carried in the store in his name,
## and spawns no monster; a second save and load finds one resident, no
## monster, no respawn and nothing handed over again. Run it with
## tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion and quits
## with exit code 1 if any assertion failed, 0 otherwise.

const LEVEL := "settled_test"
const STORE := "settled_test/store"
const WIDTH := 16
const HEIGHT := 7
const IMP := Vector2i(8, 2)
const ID := "snag-test"
const MARKERS := {Vector2i(1, 2): "start", IMP: "monster_imp"}

var _failures := 0
var _main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	_register(false)
	Net.port = preload("res://tests/test_ports.gd").of(17870)
	Net.companions = false
	Net.map_name = LEVEL
	var path: String = preload("res://tests/test_ports.gd").scratch_path("settled_test_world.json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	Net.state_path = path
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	var names := Level.names()
	if LEVEL not in names:
		names.append(LEVEL)
	World.holdings.rebind(WorldMap.build(names))
	_main._world_map = WorldMap.build(names)
	for i in 3:
		World.step()
	_test_round_trip(path)
	DirAccess.remove_absolute(path)
	Net.state_path = ""
	Net.map_name = ""
	Townsfolk.use_days({})
	Level.unregister(LEVEL)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The level: a room with the start, the imp's marker (unless [param became],
## when the marker is gone and level.json says what it became) and the
## town's store at (12, 3).
func _register(became: bool) -> void:
	Level.unregister(LEVEL)
	var markers := MARKERS.duplicate()
	if became:
		markers.erase(IMP)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(WIDTH * 2 + 1, HEIGHT * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("void"))
	var ground: Color = colour.call(Level.GROUNDS[0])
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			image.set_pixel(x * 2, y * 2, colour.call(markers[cell]) if markers.has(cell) else ground)
			if x + 1 < WIDTH:
				image.set_pixel(x * 2 + 1, y * 2, ground)
			if y + 1 < HEIGHT:
				image.set_pixel(x * 2, y * 2 + 1, ground)
	var spec := {"name": "Settled", "centre": [8, 3], "starts": [[1, 2]], "entities": [],
		"places": {"store": {"at": [12, 3], "kind": "stockpile", "radius": 2, "holder": "town", "name": "the stockpile"}}}
	if became:
		spec["became"] = {"%d,%d" % [IMP.x, IMP.y]: ID}
	Level.register(LEVEL, image, null, spec)


func _test_round_trip(path: String) -> void:
	print("\n== a save with the imp at his marker, loaded under a level that says he became the settled merchant (decision 471) ==")
	var imp := _monster()  # Spawned at his marker; he may have wandered a cell by now.
	_check(imp != null, "(the imp is in the world as saved: %s)" % [imp.name if imp != null else "nobody"])
	var item_id: String = "dagger" if not Items.def("dagger").is_empty() else Items.ids()[0]
	if imp != null:
		imp.slots = [item_id, item_id]  # An imp has no hands of its own: two slots for the test, filled as a save would.
		imp.slot_items = PackedInt32Array([0, 0])
		World.set_slots(imp, [item_id, item_id], [])
	var carried := Array(World.slot_uids(imp)) if imp != null else []
	_check(carried.size() == 2, "(two things in his slots: %s)" % [carried])
	_check(World.towns.note_rescue(STORE, "st-ada", "Ada", "hauler"), "(Ada, the town's first resident: a town to come to)")
	_main._save_state()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var keys := (data["zones"][LEVEL]["entities"] as Array).map(func(entry: Dictionary) -> String: return str(entry.get("spawn_key", "")))
	_check("%d,%d" % [IMP.x, IMP.y] in keys, "(the save holds him as a level entity by his marker's key: %s)" % [keys])
	# The level as it is now: his marker gone, "became" naming the settled resident; residents.json's table for the test.
	_register(true)
	var table := Townsfolk.days().duplicate(true)
	table["settled"] = {ID: {"name": "Snagfin", "town": STORE, "trade": "merchant", "type": "merchant", "kind": "imp", "home": [IMP.x, IMP.y],
		"came": "came to the town from the goblins and stays, somewhat outcast but tolerated",
		"fact": "Snagfin is a goblin among humans; the town tolerates him, which is more than most do.", "outcast": true}}
	Townsfolk.use_days(table)
	_main.became_handed.clear()
	_main._load_level(LEVEL)
	_main._start_level(true)
	var handed: Array = _main.became_handed.map(func(each: Dictionary) -> String: return str(each["id"]))
	_check(handed == [ID], "handed over once, to npc (%s)" % [handed])
	var who := World.production.worker(ID)
	_check(not who.is_empty() and who.get("trades", []) == ["merchant"] and str(who.get("type", "")) == "merchant" and str(who.get("origin", "")) == "settled",
		"seated through economy's door: a merchant, type merchant, origin settled (%s)" % [{"trades": who.get("trades"), "type": who.get("type"), "origin": who.get("origin")}])
	_check(World.towns.residents(STORE).count(ID) == 1 and "st-ada" in World.towns.residents(STORE), "one of the town's residents, beside Ada (%s)" % [World.towns.residents(STORE)])
	var card := Townsfolk.card_of(World.production, ID)
	_check(str(card.get("came", "")).begins_with("came to the town from the goblins") and bool(card.get("outcast", false)), "his card in Jeff's words")
	_check(_monster() == null and World.record_list().is_empty() and _main._dead_since.is_empty(), "no monster, no record, no respawn waiting (%s)" % [_names()])
	var banked: Array = Array(World.stockpile.items(STORE))
	_check(carried.all(func(uid: int) -> bool: return uid in banked), "what he carried is in the store (%s of %s)" % [banked, carried])
	_check(carried.all(func(uid: int) -> bool: return STORE in World.items.at_of(uid)), "and the item book says so (%s)" % [carried.map(func(uid: int) -> String: return World.items.at_of(uid))])
	print("-- saved again and loaded again --")
	_main._save_state()
	_main.became_handed.clear()
	_main._load_level(LEVEL)
	_main._start_level(true)
	_check(_main.became_handed.is_empty(), "nothing handed over the second time")
	_check(World.towns.residents(STORE).count(ID) == 1 and not World.production.worker(ID).is_empty(), "still one resident Snagfin (%s)" % [World.towns.residents(STORE)])
	_check(_monster() == null and _main._dead_since.is_empty(), "still no monster and no respawn")
	_check(carried.all(func(uid: int) -> bool: return uid in Array(World.stockpile.items(STORE))), "his things still in the store")


## The one spawned entity that is not a player (the imp), or null.
func _monster() -> GridEntity:
	for entity in World.get_entities():
		if entity.spawned and not entity is Player:
			return entity
	return null


func _names() -> Array:
	var out: Array = []
	for entity in World.get_entities():
		if entity.spawned and not entity is Player:
			out.append("%s@%s" % [entity.name, entity.tile])
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
