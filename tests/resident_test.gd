extends Node
## A companion left in town works there (decision 284): a test town (made in
## code) with a stockpile place the town holds, and a road beside it. Her
## player travels on while she is told to stay on the town's ground: she
## stays, a resident working her trade (her rolled profession's), not
## spawned on the road; her voice is told so; travelling back, she leaves
## her work and follows. Her player leaving the game while she stands there
## does the same, and coming back ends it. Off the town's ground, or not
## told to stay, she goes with them as before.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "rs_town"
const ROAD := "rs_road"
const STORE := "rs_town/store"
## The shed (decision 391): its inside, and its door's pixel in the layout.
const SHED := Rect2i(13, 1, 2, 3)
const SHED_DOOR_PIXEL := Vector2i(26, 7)

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17796)
	Net.companions = true
	Net.state_path = preload("res://tests/test_ports.gd").scratch("resident_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_register_levels()
	Net.map_name = TOWN
	await _boot()
	# Every resident here is steady: a thief's night in the square (decision
	# 404) would move the bodies these cases watch. A static method, not a
	# lambda: a lambda kept in a static Callable outlives this node and
	# crashes the engine at exit.
	Production.type_of = _steady

	_test_stays_when_told()
	_test_stays_when_left()
	_test_goes_when_not_told()
	_test_legacy_rests_in_town()
	_test_taken_by_raiders()
	_test_bodies_in_town()
	_test_healer_at_hut()
	_test_settled_goblin()
	_test_lawspeaker_mid_rounds()
	_test_strayed_body()
	_test_what_is_true()
	_test_two_sentences()
	_test_sick_body()
	_test_placed_captive()
	_test_aloud()
	_test_hails()
	_test_greet()
	_test_crypt_secrets()
	_test_offer_words()
	_test_monster_talk()
	_test_alms_run()
	_test_herbs()
	_test_resident_voices()
	_test_means_in_voice()
	_test_hearsay()
	_test_houses()
	_test_companion_hearsay()
	_test_visible_work()
	_test_bodies_only_near()  # Last: its resident would answer the voice tests.

	Production.type_of = Townsfolk.roll_type
	remove_child(_main)
	_main.free()
	World.clear_zones()
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	Net.map_name = ""
	Level.unregister(TOWN)
	Level.unregister(ROAD)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Every resident steady (see _ready).
static func _steady(_id: String) -> String:
	return Townsfolk.STEADY


## rs_town: a room of stone (30 x 20 rows of the layout) in a wall, the start
## at (2, 2), the store (a stockpile the town holds) at (5, 3), radius 2, a
## hut at (9, 5) (no walls of its own: its inside, (9, 5) to (11, 7), is a
## home), a healer's hut at (1, 6) (decision 404), and a shed (decision 391:
## no one's home) with walls of its own, its inside (13, 1) to (14, 3), its
## door on the south side between (13, 3) and (13, 4). rs_road: a bare room.
func _register_levels() -> void:
	for level_name: String in [TOWN, ROAD]:
		var rows: Array[String] = []
		for y in 20:
			rows.append("#".repeat(30) if y == 0 or y == 19 else "#" + ".".repeat(28) + "#")
		var spec := {"name": level_name, "centre": [7, 4], "starts": [[2, 2]], "entities": []}
		if level_name == ROAD:
			# A goblin camp in the road level holding a carpenter's daughter of the town (decision 518).
			spec["places"] = {"camp": {"at": [20, 10], "kind": "camp", "radius": 2, "holder": "goblins", "name": "the goblin camp",
				"holds": [{"town": STORE, "resident": "a carpenter's daughter", "name": "Tilda"}]}}
		if level_name == TOWN:
			spec["places"] = {"store": {"at": [5, 3], "kind": "stockpile", "radius": 2, "holder": "town", "name": "the stockpile"},
				"niche": {"at": [14, 10], "kind": "other", "radius": 1, "holder": "nobody", "name": "a niche in the wall"}}  # The barrow's niche, for the runner's test (546).
			# A home for residents' bodies (decision 333): a hut linked to nothing.
			# And a healer's hut (decision 404): a place of its own, no town; and a shed (decision 391).
			spec["buildings"] = [{"slot": "building.hut", "at": [9, 5]}, {"slot": "building.healers_hut", "at": [1, 6], "facing": [0, -1]},
				{"slot": "building.shed", "at": [13, 1], "facing": [0, 1]}]
			# The shed's walls: its outline's edges in the layout's double resolution, the door at (13, 3)'s south edge.
			for y in range(1, 8):
				for x in range(25, 30):
					if y == 1 or y == 7 or x == 25 or x == 29:
						rows[y] = rows[y].substr(0, x) + ("+" if Vector2i(x, y) == SHED_DOOR_PIXEL else "#") + rows[y].substr(x + 1)
		Level.register(level_name, Level.image_from_rows(rows, {Vector2i(2, 2): "start"}), null, spec)


func _boot() -> void:
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	var names := Level.names()
	names.append_array([TOWN, ROAD])
	World.holdings.rebind(WorldMap.build(names))
	_main._world_map = WorldMap.build(names)
	for i in 3:
		World.step()


func _test_stays_when_told() -> void:
	print("\n== told to stay on the town's ground, she stays and works while her player travels on ==")
	var pet := _companion()
	# Her rolled profession may have no trade (a hunter): this one has.
	_main._records[Net.player_id].companion["traits"]["trade"] = "carpenter"
	_check(pet != null and _trade() != "", "(a companion with a trade: %s, %s)" % [
		pet.name if pet != null else "none", _trade() if pet != null else ""])
	var ground := _town_cell(Vector2i(-1, -1))
	_check(ground.x >= 0, "(a walkable cell of the town's ground: %s)" % ground)
	_put(pet, ground)
	_told_to_stay(pet)
	_check(pet.stays_put(), "HOLD, standing as her player's instruction: she stays put")
	var who := "companion:%s" % _pet_name()
	var trade := _trade()
	_main.travel(Net.local_id, ROAD)
	_check(World.zone.name == ROAD and _companion() == null, "her player is on the road, and she is not with them")
	_check(who in World.towns.residents(STORE) and not World.production.worker(who).is_empty()
		and not World.production.worker(who).get("away", true), "she is one of the town's residents, working (%s)" % [World.towns.residents(STORE)])
	var record: PlayerRecord = _main._records[Net.player_id]
	_check(record.companion.get("resident", {}).get("place", "") == STORE and record.companion["resident"]["trade"] == trade,
		"her record says where she works, and at what (%s)" % [record.companion.get("resident", {})])
	var saved := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(saved.companion.get("resident", {}) == record.companion["resident"], "and keeps it through a save and a load")
	record.companion.erase("home")  # As a record from before decision 381 would be.
	_main.travel(Net.local_id, TOWN)
	pet = _companion()
	_check(pet != null and pet.tile == ground, "back in the town, she is where she worked (%s)" % [pet.tile if pet != null else "none"])
	_check(World.production.worker(who).get("away", false) and not record.companion.has("resident") and pet.works_as.is_empty(),
		"and leaves her work to go with them, her job waiting")
	_check(pet.home.get("place", "") == STORE and record.companion.get("home", {}).get("trade", "") == trade and "You rest in " in pet.standing_words(),
		"her home town stays with her as she travels (decision 381): %s" % pet.standing_words())
	var old := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	old.companion.erase("home")
	pet.home = old.companion.get("home", {})
	_check(pet.standing_words().is_empty(), "a record from before with no home: no home-town line, nothing else changed")
	pet.home = record.companion["home"]
	var kept: Dictionary = record.companion["home"].duplicate()
	record.companion.erase("home")
	_main._fill_home(record)
	_check(record.companion.get("home", {}) == kept, "a record saved with no home gets its town from her worker record (decision 400): %s" % [record.companion.get("home", {})])
	var nobody := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	nobody.companion.erase("home")
	nobody.companion["name"] = "Nobody_in_town"
	_main._fill_home(nobody)
	_check(not nobody.companion.has("home"), "and none when no worker record names a town")
	_check("You rest in the town here in " in pet.standing_words() and "You know that town well." in pet.standing_words(),
		"in her town: the town here, known well (%s)" % pet.standing_words())
	_check(pet.town_words() == " There is a town here, and you are in it." and pet.town_words() in pet.where_world(),
		"on its ground: a town here, and she is in it (decision 400)")
	var outside := Vector2i(-1, -1)
	for x in range(0, 40):
		for y in range(0, 40):
			if outside.x < 0 and World.is_free(Vector2i(x, y)) and Stockpile.place_at(World.holdings, TOWN, Vector2i(x, y)).is_empty():
				outside = Vector2i(x, y)
	if outside.x >= 0:
		_put(pet, outside)
		_check(pet.town_words() == " There is a town here.", "off its ground, in the same zone: a town here (%s)" % outside)
		_put(pet, ground)


func _test_stays_when_left() -> void:
	print("\n== her player leaves the game while she stands on the town's ground: she works until they are back ==")
	var pet := _companion()
	_settle(pet)
	_put(pet, _town_cell(pet.tile))
	var who := "companion:%s" % _pet_name()
	_main._on_peer_disconnected(Net.local_id)
	World.step()
	_check(pet.spawned and pet.works_as == _trade() and not World.production.worker(who).get("away", true),
		"she stays, as before, and works as the town's %s" % pet.works_as)
	_check("you stay in this town and work as its %s" % pet.works_as in pet.voice_prompt("test"), "her voice is told where she works")
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)
	World.step()
	_check(pet.keeper == _player() and pet.works_as.is_empty() and World.production.worker(who).get("away", false),
		"her player back: she follows again, her job waiting")


func _test_goes_when_not_told() -> void:
	print("\n== not told to stay, or off the town's ground: she goes with them ==")
	var pet := _companion()
	_settle(pet)
	_put(pet, _town_cell(Vector2i(-1, -1)))
	_main.travel(Net.local_id, ROAD)
	_check(_companion() != null, "on the town's ground but not told to stay: she goes with them")
	_main.travel(Net.local_id, TOWN)
	pet = _companion()
	_put(pet, Vector2i(3, 7))
	_told_to_stay(pet)
	_main.travel(Net.local_id, ROAD)
	var record: PlayerRecord = _main._records[Net.player_id]
	_check(_companion() != null and not record.companion.has("resident"), "told to stay off the town's ground: she goes with them")
	_main.travel(Net.local_id, TOWN)


func _test_legacy_rests_in_town() -> void:
	print("
== Wren and Nix rest in town between trips: their player gone from the game, they go to the town ==")
	var record: PlayerRecord = _main._records[Net.player_id]
	var was: String = record.companion["name"]
	record.companion["name"] = "Nix"
	_main.travel(Net.local_id, ROAD)
	var pet := _companion()
	_check(pet != null and World.zone.name == ROAD, "(her player and she are on the road)")
	_main._on_peer_disconnected(Net.local_id)
	_check(not pet.spawned and record.companion.get("resident", {}).get("zone", "") == TOWN and record.companion.get("tile") == null,
		"her player gone, she goes back to the town to rest (%s)" % [record.companion.get("resident", {})])
	var told: Array[String] = []
	var note := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			told.append(str(data.get("text", "")))
	Net.message_received.connect(note)
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)
	Net.message_received.disconnect(note)
	_check(World.zone.name == ROAD and _companion() == null, "her player back on the road: she is in the town, not with them")
	_check(told.any(func(line: String) -> bool: return line.begins_with("Nix is ") and TOWN in line), "and they are told where she is: %s" % [told])
	_main.travel(Net.local_id, TOWN)
	pet = _companion()
	_check(pet != null and World.distance(pet.tile, _player().tile) <= 2 and not record.companion.has("resident"),
		"in the town she joins them again, beside them")
	record.companion["name"] = was


func _test_taken_by_raiders() -> void:
	print("\n== beaten down by raiders, she is taken, not killed: held till freed, then she waits in the town that freed her (decision 314) ==")
	var record: PlayerRecord = _main._records[Net.player_id]
	var pet := _companion()
	_settle(pet)
	var was_spared: Callable = World.spared
	World.spared = func(target: GridEntity, _source: GridEntity, _cause: StringName) -> String:
		return "raid-7" if target is Companion else ""
	var told: Array[String] = []
	var note := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			told.append(str(data.get("text", "")))
	Net.message_received.connect(note)
	World.damage(pet, pet.hp + 5)
	World.spared = was_spared
	_check(not pet.spawned and _companion() == null and record.companion.get("alive", false)
		and record.companion.get("taken", {}).get("by", "") == "raid-7", "off the map, alive, held by the group (%s)" % [record.companion.get("taken", {})])
	_check(record.companion.get("facts", []).any(func(fact: Dictionary) -> bool: return "carried off by raiders" in str(fact["text"])),
		"carried off is a fact about her")
	_check(told.any(func(line: String) -> bool: return "carried them off" in line), "her player is told (%s)" % [told])
	var saved := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(saved.companion.get("taken", {}) == record.companion["taken"], "kept through a save and a load")
	told.clear()
	_main.travel(Net.local_id, ROAD)
	_main.travel(Net.local_id, TOWN)
	Net.message_received.disconnect(note)
	_check(_companion() == null and told.any(func(line: String) -> bool: return "held by them still" in line),
		"held, she is not spawned beside them, and they are told why (%s)" % [told])
	_check(_main.companion_freed(Net.player_id, STORE) and not record.companion.has("taken")
		and record.companion.get("resident", {}).get("place", "") == STORE, "freed by the town: she waits there (%s)" % [record.companion.get("resident", {})])
	_check(record.companion["facts"].any(func(fact: Dictionary) -> bool: return "freed from the raiders" in str(fact["text"])), "and that is a fact about her")
	_check(not _main.companion_freed(Net.player_id, STORE), "not freed twice")
	_main.travel(Net.local_id, ROAD)
	_main.travel(Net.local_id, TOWN)
	_check(_companion() != null and not record.companion.has("resident"), "her player in the town: she joins them again")
	pet = _companion()
	World.spared = func(target: GridEntity, _source: GridEntity, _cause: StringName) -> String:
		return "raid-8" if target is Companion else ""
	World.damage(pet, pet.hp + 5)
	World.spared = was_spared
	_check(_companion() == null and _main.companion_freed(Net.player_id) and _companion() != null
		and World.distance(_companion().tile, _player().tile) <= 2, "freed in the field (her captors beaten): beside her player at once")


func _test_bodies_in_town() -> void:
	print("\n== residents are bodies in their town: at work, at home or in the square by the hour, hiding from raiders, taken by them (decision 333) ==")
	var phase := DayNight.phase
	var anchor := DayNight.anchor
	DayNight.set_hour(12.0)
	_check(World.towns.note_rescue(STORE, "rs-bram", "Bram", "smith"), "(Bram the smith rescued: a resident of the town)")
	_sync()
	var bram := _body("rs-bram")
	_check(bram != null and bram.label == "Bram" and bram.town == STORE and bram.trade == "smith",
		"a body for him, named by his name alone over his head (%s)" % [bram.label if bram != null else "none"])
	_check(Resident.label_of("Odo", "medicine_man") == "Odo" and Resident.label_of("Wren", "") == "Wren",
		"the name alone whatever the trade (333 amended, 2026-10-22)")
	var look := str(bram.spawn_spec.get("look", "")) if bram != null else ""
	_check(look.begins_with("seed=") and look.contains(" build=") and look.ends_with("apron=yes trade=smith"),
		"his spawn spec carries his look for the character generator (419), the smith's apron on: %s" % look)
	_check(World.townsfolk().size() == 1 and not World.sought().has(bram), "one of the townsfolk, not sought (no monster's tier wakes for him)")
	var hut := Rect2i(9, 5, 3, 3)
	var square := Rect2i(3, 1, 5, 5)
	_check(bram.places["home"] == hut and bram.places["work"] == square, "home the hut; no forge, so he works in the square (%s)" % [bram.places])
	_step_until(func() -> bool: return bram.doing == Resident.Doing.WORK and square.has_point(bram.tile), 120)
	_check(bram.doing == Resident.Doing.WORK and square.has_point(bram.tile), "noon: at work (%s, at %s)" % [bram.doing, bram.tile])
	DayNight.set_hour(23.0)
	_step_until(func() -> bool: return bram.doing == Resident.Doing.HOME and hut.has_point(bram.tile), 150)
	_check(bram.doing == Resident.Doing.HOME and hut.has_point(bram.tile), "night: home in the hut (at %s)" % bram.tile)
	DayNight.set_hour(19.5)
	# A smith's evening is at the inn (decision 404); this town has none, so the square.
	_step_until(func() -> bool: return bram.doing == Resident.Doing.INN and square.has_point(bram.tile), 150)
	_check(bram.doing == Resident.Doing.INN and square.has_point(bram.tile), "evening, the inn's hour in a town with no inn: the square (at %s)" % bram.tile)
	var raider := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "RsRaider%d" % World.tick,
		"tile": _main._nearest_free(Vector2i(2, 7)), "props": {"sight_range": 0}}) as Monster
	_step_until(func() -> bool: return bram.doing == Resident.Doing.HIDE and hut.has_point(bram.tile), 150)
	_check(bram.doing == Resident.Doing.HIDE and hut.has_point(bram.tile), "a raider in sight: he hides at home (at %s)" % bram.tile)
	World.despawn(raider)
	World.entity_taken.emit(bram, "raid-9")
	_check(not bram.spawned and _body("rs-bram") == null, "beaten down by raiders: his body is carried off")
	_check("rs-bram" not in World.towns.residents(STORE) and World.towns.captives(STORE).any(func(each: Dictionary) -> bool:
		return each["id"] == "rs-bram" and each["by"] != ""), "and the town's records hold him captive (%s)" % [World.towns.captives(STORE)])
	_sync()
	_check(_body("rs-bram") == null, "held: no body comes back for him")
	World.towns.note_rescue(STORE, "rs-bram", "Bram", "smith")
	World.production.set_away("rs-bram", true)
	_sync()
	_check(_body("rs-bram") == null, "away: no body")
	World.production.set_away("rs-bram", false)
	for i in 14:
		World.towns.note_rescue(STORE, "rs-folk%02d" % i, "Folk%d" % i, "carpenter")
	_sync()
	_check(World.townsfolk().size() == Main.RESIDENTS_MAX, "%d residents: at most %d bodies (%d)" % [15, Main.RESIDENTS_MAX, World.townsfolk().size()])
	_check(not World.townsfolk().any(func(body: GridEntity) -> bool: return (body as Resident).worker_id.begins_with("companion:")),
		"a companion resident has her own body, not one of these")
	var saved: Array[GridEntity] = []
	saved.assign(World.get_entities())
	_check(not Snapshot._entries(saved).any(func(entry: Dictionary) -> bool: return entry["script"] == Main.RESIDENT), "never saved")
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	print("\n== a companion resting in town away from her player is a body there too; raiders taking her hold her as her player's (decision 333 amended) ==")
	var other := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(_main._records[Net.player_id].to_dict())))
	other.player_id = "rs-other"
	other.name = "Other"
	other.companion = {"name": "Wren", "alive": true, "facts": [], "resident": {"place": STORE, "zone": TOWN, "trade": ""}}
	_main._records["rs-other"] = other
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	_sync()
	var wren := _body("companion:rs-other")
	_check(wren != null and wren.label == "Wren" and wren.player_id == "rs-other", "Wren, resting (no trade), stands in the town (%s)" % [wren.label if wren != null else "none"])
	_check(_body("companion:" + Net.player_id) == null, "a companion out with her player has no body here")
	World.entity_taken.emit(wren, "raid-10")
	_check(not wren.spawned and other.companion.get("taken", {}).get("by", "") == "raid-10" and not other.companion.has("resident"),
		"beaten down by raiders: held as her player's companion (%s)" % [other.companion.get("taken", {})])
	_check(other.companion["facts"].any(func(fact: Dictionary) -> bool: return "carried off by raiders" in str(fact["text"])), "a fact about her")
	_sync()
	_check(_body("companion:rs-other") == null, "held: no body")
	_main._records.erase("rs-other")
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, false)
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	DayNight.phase = phase
	DayNight.anchor = anchor
	DayNight.update()


## The medicine man at the healer's hut (decision 404): economy seats him as
## a worker whose town is the hut's place id; the sync gives him a body at
## the hut, work and home both, by the clock, while someone is near.
func _test_healer_at_hut() -> void:
	print("\n== the medicine man has a body at the healer's hut (decision 404) ==")
	# The hut's place, at its front cell, as maps' 372 makes it for a map (a
	# registered level's places are the spec's: put it in by hand, as return_test does).
	var hut_place := ""
	for building: Dictionary in _main._world_map.areas.get(TOWN, {}).get("buildings", []):
		if str(building.get("slot", "")) == "building.healers_hut":
			var front := Level.front_cell(building["rect"], building.get("facing", Vector2i(0, 1)))
			hut_place = "%s/healers_hut@%d,%d" % [TOWN, front.x, front.y]
			World.holdings._places[hut_place] = {"id": hut_place, "area": TOWN, "key": hut_place.get_slice("/", 1), "cell": front,
				"name": "the healer's hut", "kind": "healers_hut", "radius": 1, "worth": 0, "start": Factions.NOBODY}
	_check(not hut_place.is_empty() and World.holdings.places_in(TOWN).has(hut_place), "(the test town's hut has a place of its own: %s; buildings %s)" % [hut_place,
		_main._world_map.areas.get(TOWN, {}).get("buildings", []).map(func(b: Dictionary) -> String: return str(b.get("slot", "")))])
	var cell: Vector2i = World.holdings.place(hut_place).get("cell", Vector2i.ZERO)
	# The town's folk away: the zone's RESIDENTS_MAX bodies were theirs.
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	DayNight.set_hour(12.0)
	_check(World.production.add_worker("medicine_man:" + hut_place, "Oren", ["medicine_man"], hut_place, "wilds"), "(Oren seated at the hut, as economy does)")
	_sync()
	var oren := _body("medicine_man:" + hut_place)
	_check(oren != null and oren.town == hut_place and oren.trade == "medicine_man" and oren.label == "Oren", "a body at the hut, its town the hut's place")
	_check(oren != null and oren.doing == Resident.Doing.WORK and World.distance(oren.tile, cell) <= 3, "at midday he is at his work, in or beside the hut (at %s, the front %s)" % [oren.tile if oren != null else Vector2i.ZERO, cell])
	DayNight.set_hour(23.0)
	_step_until(func() -> bool: return oren.doing == Resident.Doing.HOME, 40)
	_check(oren.doing == Resident.Doing.HOME and World.distance(oren.tile, cell) <= 3, "at night he is at home, which is the hut")
	DayNight.set_hour(12.0)
	World.production.set_away("medicine_man:" + hut_place, true)
	_sync()
	_check(_body("medicine_man:" + hut_place) == null, "away (fetched out), no body")
	World.production.set_away("medicine_man:" + hut_place, false)
	_sync()
	_check(_body("medicine_man:" + hut_place) != null, "back, his body again")
	World.production.set_away("medicine_man:" + hut_place, true)
	_sync()


## Snagfin (decision 471): a settled resident of another kind, with a stall
## for a home, a card in Jeff's words, no kin, and a neutral start with a
## player; one of the townsfolk, so raiders take him as they take anyone.
func _test_settled_goblin() -> void:
	print("\n== Snagfin, the town's goblin merchant: settled, a stall, his card, no kin (decision 471) ==")
	var table := Townsfolk.days().duplicate(true)
	table["settled"] = {"rs-snag": {"name": "Snagfin", "town": STORE, "trade": "merchant", "type": "merchant", "kind": "imp", "home": [4, 4],
		"came": "came to the town from the goblins and stays, somewhat outcast but tolerated",
		"fact": "Snagfin is a goblin among humans; the town tolerates him, which is more than most do.", "outcast": true}}
	Townsfolk.use_days(table)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	DayNight.set_hour(10.0)
	# The test town is crowded (room 3), so economy's door, Towns.move_in, which Main._seat_settled takes
	# and economy's rescue_test covers, would refuse him here: seated as a rescue, with his type set as the door sets it.
	_check(World.towns.note_rescue(STORE, "rs-snag", "Snagfin", "merchant"), "(Snagfin the merchant, a resident)")
	World.production._workers["rs-snag"]["type"] = "merchant"
	_main._write_settled_card("rs-snag", table["settled"]["rs-snag"])
	_sync()
	var snag := _body("rs-snag")
	_check(snag != null and snag.label == "Snagfin" and str(snag.spawn_spec.get("kind", "")) == "imp", "a body, labelled, with the goblin's kind in its spec (%s)" % [snag.spawn_spec.get("kind", "") if snag != null else "none"])
	_check(snag != null and snag.places["home"] == Rect2i(3, 3, 3, 3) and snag.places["work"] == Rect2i(4, 2, 3, 3), "his home the stall about the marked cell, his work the store's counter (%s)" % [snag.places if snag != null else {}])
	var card := Townsfolk.card_of(World.production, "rs-snag")
	_check(card.get("came", "") == "came to the town from the goblins and stays, somewhat outcast but tolerated" and card.get("outcast", false)
		and card.get("facts", []).any(func(f: Dictionary) -> bool: return str(f["text"]).begins_with("Snagfin is a goblin among humans")), "his card: Jeff's words, outcast")
	_check(card.get("kin", {}).is_empty() and card.get("grudge", []).is_empty(), "no kin and no grudge rolled for him")
	_check(Standing.words(card, "player-who-killed-him-often") == "stranger", "a player who fought the imp every session starts neutral with the man")
	_check(snag != null and World.townsfolk().has(snag), "one of the townsfolk: raiders take him as they take anyone")
	World.production.set_away("rs-snag", true)
	_sync()
	Townsfolk.use_days({})


## A lawspeaker (459) spawned while on his rounds starts at the hour's stop
## (a home of the town's), not in the square; found by economy's appointment.
func _test_lawspeaker_mid_rounds() -> void:
	print("\n== a lawspeaker spawned mid-rounds stands at the hour's stop (459) ==")
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	World.production.set_away("rs-snag", true)
	_check(World.towns.note_rescue(STORE, "rs-law", "Hrolf", "lawspeaker"), "(Hrolf the lawspeaker, a resident)")
	World.production.set_away("rs-folk00", false)
	World.production.set_away("rs-folk01", false)
	DayNight.set_hour(9.0)
	_sync()
	var law := _body("rs-law")
	_check(law != null and law.doing == Resident.Doing.ROUNDS, "at nine he is on his rounds (%s)" % [law.doing if law != null else -1])
	var stops: Array = law.places.get("rounds", []) if law != null else []
	_check(not stops.is_empty() and stops.all(func(s: Dictionary) -> bool: return s.get("id", "") != "rs-law"), "his stops are the others' homes, never his own: %s" % [stops.map(func(s: Dictionary) -> String: return str(s["who"]))])
	var stop := Townsfolk.round_stop(stops.size(), Townsfolk.day_of(DayNight.now()), DayNight.hour(DayNight.now())) if not stops.is_empty() else -1
	_check(law != null and stop >= 0 and (stops[stop]["rect"] as Rect2i).grow(1).has_point(law.tile), "and his body stands at (or beside) the hour's stop, not the square (%s in %s)" % [law.tile if law != null else Vector2i.ZERO, stops[stop]["rect"] if stop >= 0 else Rect2i()])
	World.production.set_away("rs-law", true)
	World.production.set_away("rs-folk00", true)
	World.production.set_away("rs-folk01", true)
	_sync()


## Lost beyond the walls (decision 487): a body at the chosen cell, far
## from the store; a word and it follows the player; home at the town's
## ground, the plea met.
func _test_strayed_body() -> void:
	print("\n== someone lost beyond the walls: a body out there, a word, walked home (decision 487) ==")
	var rules := Townsfolk.rules().duplicate(true)
	rules["strays"] = {"every": 54000, "chance": 0.0, "days": 3, "far": 6, "trades": ["hauler"]}  # The test town is 15 x 10 cells.
	Townsfolk.use_rules(rules)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	World.production.set_away("rs-snag", true)
	World.production.set_away("rs-law", true)
	var card := Townsfolk.card_of(World.production, "rs-folk02")
	card[Townsfolk.STRAYED] = {"since": World.production.now()}
	World.production.set_card("rs-folk02", card)
	World.production.set_away("rs-folk02", true)
	var kin := Townsfolk.card_of(World.production, "rs-folk03")
	kin["kin"] = {"rs-folk02": "sibling"}
	World.production.set_card("rs-folk03", kin)
	World.production.set_away("rs-folk03", false)
	DayNight.set_hour(10.0)
	_sync()
	var lost := _body("rs-folk02")
	var cell: Variant = Townsfolk.stray_cell(World.production, "rs-folk02")
	_check(lost != null and lost.strayed and lost.doing == Resident.Doing.STRAYED and cell is Vector2i and lost.tile == cell,
		"a body at the cell Main chose for her, far from the store (%s)" % [cell])
	_check(cell is Vector2i and World.distance(cell, Vector2i(5, 3)) >= 6 and World.is_walkable(cell), "at least the far distance away, on walkable ground")
	_check(lost != null and lost.facts_now().any(func(f: String) -> bool: return f.begins_with("You lost your way beyond the walls")), "her facts say she is lost and would be walked home")
	var plea := Offers.of("rs-folk03", Net.player_id)
	_check(plea.any(func(o: Dictionary) -> bool: return o.get("what", {}).get("stray", "") == "rs-folk02"), "her kin asks for her to be walked home: %s" % [plea.map(func(o: Dictionary) -> String: return str(o["title"]))])
	var player := _player()
	_check(player != null, "(a player to speak to her)")
	if lost != null and player != null:
		_main._ask_resident(lost, "Jeff", "Come with me.", player)
		_check(lost.escort_of == player.player_id, "a word, and she follows that player")
		World.step()
		_check(lost.doing == Resident.Doing.ESCORT or lost.doing == Resident.Doing.STRAYED, "(her tick ran with the player far: %s)" % [lost.doing])
		_put(lost, _town_cell(Vector2i(-1, -1)))
		_sync()
	_check(World.production.worker("rs-folk02")["away"] == false and not Townsfolk.card_of(World.production, "rs-folk02").has(Townsfolk.STRAYED),
		"at the town's ground she is home: back, not away, the card clear")
	_check(str(Townsfolk.card_of(World.production, "rs-folk02")["facts"].back()["text"]).ends_with("home from beyond the walls."), "her card: who walked her home")
	var home := _body("rs-folk02")
	_check(home != null and not home.strayed and home.doing != Resident.Doing.STRAYED, "her body is one of the town's again")
	World.production.set_away("rs-folk02", true)
	World.production.set_away("rs-folk03", true)
	Townsfolk.use_rules({})
	_sync()


## The scholar keeps the chronicle and the lawspeaker says so (decision 491).
func _test_what_is_true() -> void:
	print("\n== what is true: the scholar's chronicle in the lawspeaker's and the scholar's facts (decision 491) ==")
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	World.production.set_away("rs-snag", true)
	World.production.set_away("rs-folk05", false)
	World.production._workers["rs-folk05"]["type"] = "scholar"
	World.production.set_away("rs-law", false)
	DayNight.set_hour(10.0)
	_sync()
	var law := _body("rs-law")
	var scholar := _body("rs-folk05")
	_check(law != null and law.facts_now().any(func(f: String) -> bool: return f.begins_with("Folk5, the town's scholar, keeps the chronicle")), "the lawspeaker names the scholar as the keeper of what is true")
	_check(scholar != null and scholar.facts_now().any(func(f: String) -> bool: return f.begins_with("You keep the town's chronicle")), "the scholar knows what they keep")
	World.production._workers["rs-folk05"]["type"] = ""
	World.production.set_away("rs-folk05", true)
	World.production.set_away("rs-law", true)
	_sync()


## The voice rule held by code (336 amended, the words soak): at most two
## sentences, never the resident's own name first.
func _test_two_sentences() -> void:
	print("\n== the voice rule by code: two sentences, no name first ==")
	_check(Resident.two_sentences("Bea says: \"I'm Bea. Hauler. You?\"", "Bea") == "I'm Bea. Hauler.", "a 'Bea says:' lead and a third sentence are cut")
	_check(Resident.two_sentences("Yes. And so do rabbits. And so do most things when they're spooked.") == "Yes. And so do rabbits.", "three sentences become two")
	_check(Resident.two_sentences("I need a blade, and a shield, and more bandage.") == "I need a blade, and a shield, and more bandage.", "one sentence stands")
	_check(Resident.two_sentences("Mags: The fog is thick.", "Mags") == "The fog is thick.", "a bare name lead is cut")
	_check(Resident.two_sentences("Bandages: we have none.", "Mags") == "Bandages: we have none.", "another word before a colon stands when the name is known")


## Sick (decision 501): the body keeps to its bed; the medicine man's visit
## treats them; a remedy in hand treats them at once.
func _test_sick_body() -> void:
	print("\n== sick: in bed all day; the medicine man's visit; a remedy in hand (decision 501) ==")
	var rules := Townsfolk.rules().duplicate(true)
	rules["sick"] = {"chance": 0.0, "winter": 1, "hungry": 1, "old": 1, "days": 5, "death_old": 0.0, "visit_hours": 2, "kinds": ["a fever"]}
	Townsfolk.use_rules(rules)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	for id: String in ["rs-bram", "rs-snag", "rs-law", "rs-folk02", "rs-folk03", "rs-folk05"]:
		World.production.set_away(id, true)
	var hut: String = _main._healers_hut_of(STORE)
	if not hut.is_empty():
		World.production.set_away("medicine_man:" + hut, false)  # Back from 404's test.
	World.production.set_away("rs-folk06", false)
	Townsfolk._set_sickness(World.production, "rs-folk06", {"since": Townsfolk.day_of(World.steps), "kind": "a fever", "treated": -1, "cured_by": ""})
	DayNight.set_hour(11.0)
	_sync()
	var sick := _body("rs-folk06")
	_check(sick != null and sick.doing == Resident.Doing.BED and (sick.places.get("home", Rect2i()) as Rect2i).grow(1).has_point(sick.tile), "at eleven, when the well would call, the sick one is in bed at home (%s)" % [sick.doing if sick != null else -1])
	_check(sick != null and sick.facts_now().any(func(f: String) -> bool: return f.begins_with("You are sick with a fever")), "their facts say so")
	_check(sick != null and sick.ailing == "a fever", "the body says what they lie abed with, for the client's hint (501 amended): %s" % [sick.ailing if sick != null else "-"])
	var well := _body("medicine_man:" + hut) if not hut.is_empty() else null
	_check(well == null or well.ailing == "", "a well body names nothing")
	var player := _player()
	var healer := str(Offers._call(Offers.ctx, "healer_of", [STORE]))
	_check(not healer.is_empty() and healer != "<null>", "(the test town's hut has its medicine man: %s)" % healer)
	if sick != null and player != null and not healer.is_empty() and healer != "<null>":
		_check(_main._send_healer(healer, "rs-folk06", player.player_id), "a word sends the medicine man to the bedside")
		_check(not _main._send_healer(healer, "rs-folk06", player.player_id), "(not twice while he is on a visit)")
		World.steps += 2 * int(DayNight.day_steps / 24) + 1
		_main._visits_due()
		_check(int(Townsfolk.sickness_of(World.production, "rs-folk06").get("treated", -1)) >= 0 and str(Townsfolk.sickness_of(World.production, "rs-folk06").get("cured_by", "")) == str(World.production.worker(healer).get("name", "")),
			"two hours later the visit has treated them, by his name")
	# A remedy in hand treats at once.
	World.production.set_away("rs-folk07", false)
	Townsfolk._set_sickness(World.production, "rs-folk07", {"since": Townsfolk.day_of(World.steps), "kind": "a cough", "treated": -1, "cured_by": ""})
	_sync()
	var other := _body("rs-folk07")
	if other != null and player != null and not Items.def("remedy").is_empty():
		other.slots = ["remedy"]
		other.slot_items = PackedInt32Array([0])
		World.set_slots(other, ["remedy"], [])
		var dose := World.slot_uid(other, 0)
		_put(player, _main._nearest_free(other.tile + Vector2i(1, 0)))  # In reach, as a hand is.
		_main._on_handed(player, other, "remedy", dose)
		_check(int(Townsfolk.sickness_of(World.production, "rs-folk07").get("treated", -1)) >= 0, "a remedy put in their hands: the sickness breaks that night")
		_check(other.slots[0] == "" and World.items.id_of(dose) == "remedy", "and the dose is used up (slots %s, dose %d, player at %s, they at %s)" % [other.slots, dose, player.tile, other.tile])
	else:
		_check(true, "(items' remedy is not here yet: the remedy case is skipped)")
	# Walked to the healer: a word, at heel onto the hut's ground, and the kin's plea is met by that player's name.
	if player != null and not hut.is_empty():
		var kin := Townsfolk.card_of(World.production, "rs-folk09")
		kin["kin"] = {"rs-folk08": "sibling"}
		World.production.set_card("rs-folk09", kin)
		World.production.set_away("rs-folk08", false)
		World.production.set_away("rs-folk09", false)
		World.production.set_away("medicine_man:" + hut, true)  # No medicine man today: the plea is the walk.
		Townsfolk._set_sickness(World.production, "rs-folk08", {"since": Townsfolk.day_of(World.steps), "kind": "the shakes", "treated": -1, "cured_by": ""})
		_sync()
		var walked := _body("rs-folk08")
		var plea := Offers.of("rs-folk09", player.player_id).filter(func(o: Dictionary) -> bool: return str(o.get("what", {}).get("sick", "")) == "rs-folk08")
		_check(plea.size() == 1 and str(plea[0]["title"]).begins_with("Take ") and plea[0]["what"].get("hut") == hut, "the kin asks for the walk to the healer: %s" % [plea.map(func(o: Dictionary) -> String: return str(o["title"]))])
		if walked != null and not plea.is_empty():
			Offers.accept("rs-folk09", player.player_id, "Jeff", plea[0]["id"], 0)
			_main._ask_resident(walked, "Jeff", "Come, to the healer.", player)
			_check(walked.escort_of == player.player_id, "a word, and the sick one follows at heel")
			var hut_cell: Vector2i = World.holdings.place(hut).get("cell", Vector2i.ZERO)
			_put(walked, hut_cell)
			_put(player, _main._nearest_free(hut_cell + Vector2i(1, 0)))
			_sync()
			var record := Townsfolk.sickness_of(World.production, "rs-folk08")
			_check(int(record.get("treated", -1)) >= 0 and str(record.get("cured_by", "")) == _main._display_name(player), "on the hut's ground the healer sees to them, by the walker's name: %s" % [record])
			_check(walked.escort_of.is_empty(), "and the walk is over")
			_check(Townsfolk.card_of(World.production, "rs-folk09")["asks"].is_empty(), "the kin's plea is met")
		Townsfolk._set_sickness(World.production, "rs-folk08", {})
		World.production.set_away("rs-folk08", true)
		World.production.set_away("rs-folk09", true)
	Townsfolk._set_sickness(World.production, "rs-folk06", {})
	Townsfolk._set_sickness(World.production, "rs-folk07", {})
	World.production.set_away("rs-folk06", true)
	World.production.set_away("rs-folk07", true)
	if not hut.is_empty():
		World.production.set_away("medicine_man:" + hut, true)
	Townsfolk.use_rules({})
	_sync()


## The medicine man takes herbs on his way (decision 502, npc's side): the
## nearest within HERB_REACH of his body go to his hut's store.
func _test_herbs() -> void:
	print("\n== the medicine man takes herbs on his way and banks them at his hut, his own (decision 502, npc's side, amended) ==")
	var hut: String = _main._healers_hut_of(STORE)
	if Items.def("herbs").is_empty() or World.forage == null or hut.is_empty():
		_check(true, "(items' herbs, World.forage or the test hut is not here: skipped)")
		return
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	for id: String in ["rs-bram", "rs-snag", "rs-law"]:
		World.production.set_away(id, true)
	World.production.set_away("medicine_man:" + hut, false)
	DayNight.set_hour(12.0)
	_sync()
	var oren := _body("medicine_man:" + hut)
	_check(oren != null and oren.doing == Resident.Doing.WORK, "(the medicine man at his work, the hut)")
	if oren != null:
		var uid := World.items.mint("herbs", "grew", "the test", oren.zone, oren.tile)
		var laid := World.put_on_ground(uid, oren.tile + Vector2i(2, 0))
		_check(laid != World.NO_CELL and World.ground_at(laid).has("herbs"), "(herbs laid near him at %s)" % [laid])
		_main._herbs_gathered.clear()
		DayNight.set_hour(12.0)
		_main._gather_herbs()
		var town_had := World.stockpile.count(STORE, "herbs")
		var had := World.stockpile.count(hut, "herbs")
		_check(not World.ground_at(laid).has("herbs") and had >= 1 and not World.items.has(uid), "on the world tick he takes them into his own hut's store, unpaid (%d herbs)" % had)
		_check(World.stockpile.count(STORE, "herbs") == town_had, "the town's store neither holds nor paid for them")
		var second := World.items.mint("herbs", "grew", "the test", oren.zone, oren.tile)
		var again := World.put_on_ground(second, oren.tile + Vector2i(2, 0))
		_main._gather_herbs()
		_check(again != World.NO_CELL and World.ground_at(again).has("herbs") and World.stockpile.count(hut, "herbs") == had, "a day's gather once: the second pile waits for tomorrow")
		# Without a body: the next day, at the hut, once the hour has come.
		World.production.set_away("medicine_man:" + hut, true)
		_sync()
		World.production.set_away("medicine_man:" + hut, false)  # Back, but nobody near: no body until a sync.
		World.steps += DayNight.day_steps
		DayNight.set_hour(9.0)
		_main._gather_herbs()
		_check(_body("medicine_man:" + hut) == null and World.ground_at(again).has("herbs"), "before the gathering hour, with no body, the pile lies")
		DayNight.set_hour(15.0)
		_main._gather_herbs()
		_check(not World.ground_at(again).has("herbs") and World.stockpile.count(hut, "herbs") == had + 1, "after it, the hut's gather takes the pile with no body standing (%d herbs)" % World.stockpile.count(hut, "herbs"))
		var far := World.items.mint("herbs", "grew", "the test", oren.zone, oren.tile)
		var away := World.put_on_ground(far, oren.tile + Vector2i(_main.HERB_REACH + 3, 0))
		World.steps += DayNight.day_steps
		DayNight.set_hour(15.0)
		_main._gather_herbs()
		_check(away == World.NO_CELL or World.ground_at(away).has("herbs"), "herbs beyond his reach stay where they grow")
		_main._herbs_gathered.clear()
	World.production.set_away("medicine_man:" + hut, true)
	_sync()


func _test_resident_voices() -> void:
	print("\n== spoken to, a resident answers from one mind for them all, with facts only, yielding to companions (decision 336) ==")
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	DayNight.set_hour(12.0)
	World.towns.note_rescue(STORE, "rs-mara", "Mara", "cook")
	_sync()
	var mara := _body("rs-mara")
	var player := _player()
	_check(mara != null and mara.person == "Mara", "(Mara the cook stands in the town)")
	_put(player, _main._nearest_free(mara.tile + Vector2i(1, 0)))
	var mind := VoiceMind.new()
	_main._resident_mind = mind
	var spoken: Array[String] = []
	var heard := func(kind: String, data: Dictionary) -> void:
		if kind == "speech":
			spoken.append("%s: %s" % [data.get("speaker", ""), data.get("text", "")])
	Net.message_received.connect(heard)
	_main._chat_tick.clear()
	_main._player_said(player, "What are you making today?")
	World.step()
	_check(mind.asks.size() == 1 and spoken.has("Mara: The kitchen's warm, at least."), "beside her, a question: she answers from the resident mind (%s)" % [spoken])
	var prompt := str(mind.asks.back().get("system", "")) if not mind.asks.is_empty() else ""
	_check("You are Mara" in prompt and "as a cook" in prompt and "It is " in prompt and "The town is short of" in prompt
		and "shop" in prompt and "workshop" in prompt, "her prompt says who she is, the hour, her work, the town's wants and its shop: %s" % prompt.get_slice("What is true now:", 1).get_slice("Say what", 0).strip_edges())
	_check("Mara" in prompt.get_slice("Who you are:", 1).get_slice("What is true", 0), "and a card rolled for her, by her name")
	var pet := _companion()
	_check(_main._resident_addressed(player, "%s, what do you think?" % pet.name, pet) == null, "a line naming their own companion is hers, not Mara's")
	var was: CompanionMind = pet.mind
	pet.mind = BusyMind.new()
	_main._chat_tick.clear()
	_main._player_said(player, "Is the kitchen busy?")
	World.step()
	_check(mind.asks.size() == 1 and _main._resident_asks.size() == 1, "a companion's voice out: Mara's ask waits (residents yield)")
	pet.mind = was
	World.step()
	_check(mind.asks.size() == 2, "the companion done: Mara is asked")
	pet.mind = BusyMind.new()
	_main._chat_tick.clear()
	_main._player_said(player, "Mara, anything else?")
	for i in Main.RESIDENT_ASK_TICKS + 2:
		World.step()
	_check(mind.asks.size() == 2 and _main._resident_asks.is_empty(), "waited too long: dropped, nothing said")
	pet.mind = was
	World.towns.resident_taken(STORE, "rs-mara", "raid-11")
	World.towns.note_rescue(STORE, "rs-mara", "Mara", "cook")
	_check("carried off by raiders once" in str(mara.voice_ask("Player", "Hello", 98)["system"]), "taken before and brought home: her prompt says so")
	mara.doing = Resident.Doing.HIDE
	_check(_main._resident_addressed(player, "Mara?", null) == null, "hiding from raiders: she answers nothing")
	mara.card = "Wren is a legacy companion who rests in town between trips."
	_check(mara.card in str(mara.voice_ask("Player", "Hello", 99)["system"]), "a companion resting in town speaks from her own card")
	Net.message_received.disconnect(heard)
	_main._resident_mind = null
	World.despawn(mara)


func _test_means_in_voice() -> void:
	print("\n== how it last ate and traded, and how many the town feeds, are in its voice's facts (decision 336 amended, 353's facts) ==")
	var production := World.production
	production.add_worker("rs-means", "Tamsin", ["cook"], STORE)
	var body := Resident.new()
	body.worker_id = "rs-means"
	body.town = STORE
	var before := body.means_words()
	_check(before.filter(func(line: String) -> bool: return "You " in line).is_empty(), "before its first meal or trade: nothing of its own (%s)" % [before])
	production.note_meal("rs-means", "bought")
	production.note_trade("rs-means", "bought a stew", 4, "Mags")
	_check(body.means_words().has("You last bought a stew from Mags for 4 gold."), "a meal bought: from whom and for how much (%s)" % [body.means_words()])
	production.note_trade("rs-means", "bought bread from the store", 2, Economy.TREASURY)
	_check(body.means_words().has("You last bought bread from the store for 2 gold."), "from the store: not 'from the town' twice (%s)" % [body.means_words()])
	production.note_trade("rs-means", "sold a stew", 4, "Bram")
	_check(body.means_words().has("You last sold a stew to Bram for 4 gold."), "a sale: to whom (%s)" % [body.means_words()])
	production.note_trade("rs-means", "a bed at the inn", 2, Economy.TREASURY)
	_check(body.means_words().has("You last paid the town 2 gold for a bed at the inn."), "a fee to the town (%s)" % [body.means_words()])
	production.note_trade("rs-means", "work on their tools", 4, "Bram")
	_check(body.means_words().has("You last paid Bram 4 gold for work on your tools."), "a fee to a smith (%s)" % [body.means_words()])
	production.note_trade("rs-means", "work on their tools for Bram", 4, "Bram")
	_check(body.means_words().has("You were last paid 4 gold by Bram for work on their tools."), "a fee earned (%s)" % [body.means_words()])
	production.note_meal("rs-means", "dole")
	_check(body.means_words().has("At your last meal the town fed you for nothing: you could not pay.")
		and body.means_words().any(func(line: String) -> bool: return "of the town's folk ate from the town's dole" in line), "on the dole: it says so, and the town's count (%s)" % [body.means_words()])
	production.note_meal("rs-means", "hungry")
	_check(body.means_words().has("You went without at your last meal: there was nothing you could eat."), "hungry since a mealtime (%s)" % [body.means_words()])
	# A day as long as the clock has run, so hunger from step 1 is a day old.
	var day := DayNight.day_steps
	production._workers["rs-means"]["hungry_since"] = 1
	DayNight.day_steps = maxi(production.now() - 1, 1)
	_check(production.now() > 1 and body.means_words().has("You have had nothing to eat since yesterday or before."), "hungry a day: since yesterday (%s)" % [body.means_words()])
	DayNight.day_steps = day
	_check(not body.means_words().any(func(line: String) -> bool: return "owe" in line), "owing nothing: no debt said")
	production.set_loan("rs-means", 11.2)
	_check(body.means_words().has("You owe the town 12 gold.") and not body.means_words().any(func(line: String) -> bool: return "working off" in line),
		"a loan: what it owes, rounded up (%s)" % [body.means_words()])
	production.set_loan("rs-means", 29.5, true)
	_check(body.means_words().has("You owe the town 30 gold.") and body.means_words().has("You are working off your debt to the town, hauling for it, and cannot borrow more."),
		"working it off: it says so (%s)" % [body.means_words()])
	production.set_loan("rs-means", 0.0)
	_check(body.means_words()[0] in body.facts_now(), "and they are among what is true now")
	production.note_meal("rs-means", "bought")
	production.set_away("rs-means", true)
	body.free()


func _test_hearsay() -> void:
	print("\n== what townsfolk hear, they weigh by their intellect and repeat as hearsay; an official never does (decision 378) ==")
	var heard: Array = []
	var dull := Hearsay.hear(heard, "rs-x", 1, "The mine is cursed.", "beyond", "Talos", 1)
	_check(bool(dull.get("believed")) and dull["text"] == "The mine is cursed", "intellect 1: a claim beyond what they know is believed")
	_check(Hearsay.hear(heard, "rs-x", 1, "the mine is cursed", "beyond", "Talos", 2).is_empty(), "the same claim from the same one is not kept twice")
	_check(Hearsay.hear(heard, "rs-x", 1, "The king is alive.", "agrees", "Talos", 3).is_empty(), "one that agrees with what they know is lore already: not kept")
	_check(Hearsay.prompt_words(heard) == "You have heard, and believe it though you are not sure: Talos told you that the mine is cursed.",
		"believed, it is told as hearsay, naming who said it: %s" % Hearsay.prompt_words(heard))
	var sharp: Array = []
	_check(not bool(Hearsay.hear(sharp, "rs-y", 10, "The mine is cursed.", "beyond", "Talos", 1).get("believed")) and Hearsay.prompt_words(sharp).is_empty(),
		"intellect 10: not believed, and nothing told")
	_check(not bool(Hearsay.hear(sharp, "rs-y", 7, "The river runs uphill.", "against", "Talos", 2).get("believed")), "intellect 7 never believes what goes against what they know")
	_check(Hearsay.roll("rs-x", "The mine is cursed.") == Hearsay.roll("rs-x", "the mine is cursed"), "the roll is the same every time")
	Hearsay.overturn(heard, [dull["id"]])
	_check(Hearsay.prompt_words(heard).is_empty(), "shown false later: no longer believed, and not told")
	var full: Array = []
	for i in 9:
		Hearsay.hear(full, "rs-z", 1 if i > 0 else 10, "Claim number %d is so." % i, "beyond", "Talos", i)
	_check(full.size() == Hearsay.setting("max") and full.all(func(entry: Dictionary) -> bool: return entry["text"] != "Claim number 0 is so"),
		"over the cap: the oldest not believed goes")
	_check(bool(Hearsay.hear(sharp, "rs-y", 10, "The well is cursed.", "beyond", "Talos", 3, true, 10).get("believed", false))
		and Hearsay.p_believe("beyond", 10, true, 8) > 0.8 and Hearsay.p_believe("beyond", 10, true, 2) == Hearsay.p_believe("beyond", 10),
		"an omen: a superstitious role believes it though sharp, one who is not does not")
	_check(Hearsay.is_omen("The old well is haunted") and not Hearsay.is_omen("The mill is closed") and not Hearsay.is_omen("The well is haunted", false),
		"an omen by the claims ask's word, else by its words")
	_check(not Hearsay.worth_asking("Hello there.") and not Hearsay.worth_asking("What are you making today?") and Hearsay.worth_asking("The mine is cursed, Mara."),
		"only a line that may hold a claim is weighed")

	# In play: a player tells Mara (dull) and then Bram (sharp) the same.
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	DayNight.set_hour(12.0)
	_sync()
	var mara := _body("rs-mara")
	var player := _player()
	_check(mara != null, "(Mara stands in the town)")
	if mara == null:
		return
	_put(player, _main._nearest_free(mara.tile + Vector2i(1, 0)))
	World.production._workers["rs-mara"]["intellect"] = 1
	World.production.set_heard("rs-mara", [])
	var mind := ClaimsMind.new()
	mind.claims = {"facts": [{"text": "The mine is cursed", "fits": "beyond"}], "overturns": []}
	_main._resident_mind = mind
	_main._claims_at.clear()
	_main._chat_tick.clear()
	_main._player_said(player, "The mine is cursed, Mara.")
	for i in 3:
		World.step()
	var said_to := str(mara.voice_ask("Player", "What news?", 1)["system"])
	_check(_asks_of(mind, mara) == 1 and "Player told you that the mine is cursed" in said_to,
		"intellect 1, told it: she repeats it as hearsay (%s)" % said_to.get_slice("What is true now:", 1).get_slice("Say what", 0).strip_edges())
	_check("say what you have heard, as heard" in said_to.to_lower() or "what you have heard, say as heard" in said_to, "and her rule: never make up more")
	World.production._workers["rs-mara"]["intellect"] = 10
	World.production._workers["rs-mara"]["superstition"] = 2  # A curse is an omen: not one to take omens either.
	World.production.set_heard("rs-mara", [])
	_main._claims_at.clear()
	_main._chat_tick.clear()
	_main._player_said(player, "The mine is cursed, Mara.")
	for i in 3:
		World.step()
	_check(_asks_of(mind, mara) == 2 and "the mine is cursed" not in str(mara.voice_ask("Player", "What news?", 2)["system"]).to_lower(),
		"intellect 10, told the same: she does not")
	# A priest, told it and somehow holding it believed, never says it.
	var was_trade := mara.trade
	mara.trade = "priest"
	var record: Dictionary = World.production._workers["rs-mara"]
	var leanings := {}
	for key in ["creativity", "integrity", "type"]:
		leanings[key] = record.get(key)
	record["creativity"] = 2
	record["integrity"] = 8
	record["type"] = "steady"
	World.production.set_heard("rs-mara", [{"id": "h1", "text": "The mine is cursed", "from": "Player", "step": 1, "fits": "beyond", "believed": true}])
	var priest := str(mara.voice_ask("Player", "What news?", 3)["system"])
	_check(mara.binding() == "official" and "the mine is cursed" not in priest.to_lower() and Resident.BOUND["official"] in priest
		and Resident.BOUND["plain"] in priest and Resident.BOUND["honest"] in priest, "a priest (official) never repeats a non-fact, and is bound to lore's")
	# A cook who is a thief at heart (npc's hidden type): free, and as his own leanings say.
	mara.trade = was_trade
	record["type"] = "thief"
	record["creativity"] = 8
	record["integrity"] = 2
	var thief := str(mara.voice_ask("Player", "What news?", 4)["system"])
	_check(mara.binding() == "free" and Resident.BOUND["embellish"] in thief and Resident.BOUND["lie"] in thief and "the mine is cursed" in thief.to_lower()
		and "thief" not in mara.label.to_lower(), "a thief at heart (hidden) may embellish and lie, and repeats what he heard")
	for key: String in leanings:
		if leanings[key] == null:
			record.erase(key)
		else:
			record[key] = leanings[key]
	mara.trade = was_trade
	# Overheard: her companion's line beside Mara is weighed too.
	World.production.set_heard("rs-mara", [])
	_main._claims_at.clear()
	var pet := _companion()
	_put(pet, _main._nearest_free(mara.tile + Vector2i(0, 1)))
	_main._on_companion_said("They say the old well is haunted.", pet)
	_check(_main._claims_asks.any(func(each: Dictionary) -> bool: return each["worker"] == "rs-mara" and each["from"] == String(pet.name)),
		"a companion's line beside her: she weighs it too")
	_main._claims_asks.clear()
	World.production.set_heard("rs-mara", [])
	_main._resident_mind = null


## How many of [param mind]'s claims asks were [param body]'s (a companion
## near the player is asked too, decision 442).
func _asks_of(mind: ClaimsMind, body: Resident) -> int:
	return mind.claims_asks.filter(func(ask: Dictionary) -> bool: return str(ask.get("speaker", "")) == body.person).size()


class ClaimsMind:
	extends CompanionMind
	var claims := {}
	var claims_asks: Array[Dictionary] = []

	func facts(ask: Dictionary) -> Dictionary:
		claims_asks.append(ask)
		return claims.duplicate(true)


class VoiceMind:
	extends CompanionMind
	var asks: Array[Dictionary] = []

	func voice(ask: Dictionary) -> Dictionary:
		asks.append(ask)
		return {"say": "The kitchen's warm, at least."}


class BusyMind:
	extends CompanionMind

	func busy(what: String) -> bool:
		return what == "voice"


## A town far from everyone has no bodies, and is not in play: a raid on
## it takes its people off the record (decision 355). The room is small,
## so the distances are made small (Main.recall_tiles, retire_tiles).
func _test_companion_hearsay() -> void:
	print("\n== a companion weighs what she hears by her own intellect, says it as hearsay, and brings it to town and back (decision 442) ==")
	# Her leanings, rolled with her card.
	var rolled := CompanionCard.roll("lean-test")
	var leanings: Dictionary = rolled.get("leanings", {})
	_check(leanings.size() == 2 and leanings.values().all(func(v: Variant) -> bool: return int(v) >= 1 and int(v) <= 10)
		and leanings == CompanionCard.roll("lean-test")["leanings"] and rolled["fear"] == CompanionCard.roll("lean-test")["fear"],
		"her intellect and superstition are rolled with her card, the same every time, the rest as it was (%s)" % [leanings])
	_check(CompanionCard.leaning({"name": "Pip"}, "old", "intellect") == 4 and CompanionCard.leaning({"name": "Pip"}, "old", "superstition") == 2
		and CompanionCard.leaning({"name": "Pip", "leanings": {"intellect": 4, "superstition": 8}}, "old", "superstition") == 2
		and CompanionCard.leaning({"name": "Nix"}, "old", "intellect") == 8, "Pip, Wren and Nix have theirs fixed")
	_check(CompanionCard.leaning({"name": "Ysolt"}, "old", "intellect") == CompanionCard.leaning({"name": "Ysolt"}, "old", "intellect")
		and "Leanings" not in CompanionCard.facts(rolled, "Jeff"), "a card from before has them from her seed; her card is written without them")
	# Told a lie: kept as heard, weighed, never a fact or a belief.
	if World.zone.name != TOWN:
		_main.travel(Net.local_id, TOWN)
	var owner := _player()
	var pet := _companion()
	_check(owner != null and pet != null, "(a player and a companion)")
	if owner == null or pet == null:
		return
	var record: PlayerRecord = _main._records[Net.player_id]
	_put(owner, Vector2i(6, 8))
	_put(pet, Vector2i(7, 8))
	record.companion["traits"]["leanings"] = {"intellect": 1, "superstition": 5}
	record.companion["heard"] = []
	pet.heard = []
	var beliefs := pet.grown.beliefs.size()
	var facts := pet.grown.facts.size()
	var mind := ClaimsMind.new()
	mind.claims = {"facts": [{"text": "The mine is cursed", "fits": "beyond"}], "overturns": []}
	_main._resident_mind = mind
	_main._claims_at.clear()
	_main._chat_tick.clear()
	_main._player_said(owner, "The mine is cursed, %s." % pet.name)
	for i in 6:
		World.step()
	var asked := mind.claims_asks.filter(func(ask: Dictionary) -> bool: return str(ask.get("speaker", "")) == String(pet.name))
	_check(asked.size() == 1 and "who travels with %s" % pet.keeper_name() in str(asked[0]["system"]), "one claims ask on her, as one who travels with her player")
	_check(pet.heard.size() == 1 and bool(pet.heard[0]["believed"]) and record.companion.get("heard", []) == pet.heard,
		"intellect 1: she believes it, kept in her record (%s)" % [pet.heard])
	_check("%s told you that the mine is cursed" % pet.keeper_name() in pet.voice_prompt("test"), "her voice says it as hearsay, naming who told her")
	_check(pet.grown.beliefs.size() == beliefs and pet.grown.facts.size() == facts, "and it is neither a belief nor a fact on her card")
	record.companion["traits"]["leanings"] = {"intellect": 10, "superstition": 2}
	record.companion["heard"] = []
	pet.heard = []
	_main._claims_at.clear()
	_main._chat_tick.clear()
	_main._player_said(owner, "The mine is cursed, %s." % pet.name)
	for i in 6:
		World.step()
	_check(pet.heard.size() == 1 and not bool(pet.heard[0]["believed"]) and "the mine is cursed" not in pet.voice_prompt("test"),
		"intellect 10: kept but not believed, and not told")
	# Resting in town she brings it, and takes back what she heard there.
	record.companion["traits"]["leanings"] = {"intellect": 3, "superstition": 6}
	record.companion["heard"] = [{"id": "h1", "text": "The mine is cursed", "from": "Player", "step": 1, "fits": "beyond", "believed": true}]
	var ground := _town_cell(Vector2i(-1, -1))
	_put(pet, ground)
	_told_to_stay(pet)
	_main.travel(Net.local_id, ROAD)
	var who := "companion:%s" % _pet_name()
	var worker := World.production.worker(who)
	_check(not worker.is_empty() and worker.get("heard", []) == record.companion["heard"] and int(worker.get("intellect", 0)) == 3
		and int(worker.get("superstition", 0)) == 6, "staying in town, her worker record has what she heard and her leanings (%s)" % [worker.get("heard", [])])
	var there: Array = worker.get("heard", []).duplicate(true)
	Hearsay.hear(there, who, 3, "The miller hides gold.", "beyond", "Tam", 2, false, 6, "well")
	World.production.set_heard(who, there)
	_main.travel(Net.local_id, TOWN)
	pet = _companion()
	_check(record.companion.get("heard", []).size() == 2 and pet != null and pet.heard == record.companion["heard"]
		and str(pet.heard[1].get("where", "")) == "well", "back with her player, what she heard at the well comes with her (%s)" % [record.companion.get("heard", [])])
	record.companion["traits"].erase("leanings")
	record.companion["heard"] = []
	if pet != null:
		pet.heard = []
		_settle(pet)


func _test_houses() -> void:
	print("\n== inside a building she knows it; out of doorways but to hold one in a fight (decision 391) ==")
	if World.zone.name != TOWN:
		_main.travel(Net.local_id, TOWN)
	var owner := _player()
	var pet := _companion()
	_check(owner != null and pet != null, "(a player and a companion in the town)")
	if owner == null or pet == null:
		return
	for entity in World.get_entities():
		if entity is Monster:
			World.damage(entity, 999)
	_settle(pet)
	pet.errand = {}
	pet.hp = pet.max_hp
	var door: Door = null
	for each: Door in World.get_doors():
		if Terrain.edge_cells(each.key) == [Vector2i(13, 3), Vector2i(13, 4)]:
			door = each
	_check(door != null and Companion.door_cells().has(Vector2i(13, 3)) and Companion.door_cells().has(Vector2i(13, 4)),
		"(the shed's door, its cells either side: %s)" % [Companion.door_cells().keys()])
	if door == null:
		return
	door.open = true
	# Inside: the building by name, and whose home.
	_put(owner, Vector2i(14, 1))
	_put(pet, Vector2i(13, 1))
	_check(pet.inside_words() == "You are inside a shed" and pet.where_words().begins_with("You are inside a shed")
		and pet.where_words(false).begins_with("You are inside a shed"), "in the shed: she is told so, not outdoors (%s)" % pet.where_words())
	_sync()
	var homed := ""
	for body: GridEntity in World.townsfolk():
		if (body as Resident).places.get("home") == Rect2i(9, 5, 3, 3):
			homed = (body as Resident).person
	_put(pet, Vector2i(10, 6))
	_check(pet.inside_words().begins_with("You are inside a small hut") and (homed.is_empty() or ("%s's home" % homed) in pet.inside_words()),
		"in the hut: a small hut, and whose home it is when a resident's (%s; %s)" % [pet.inside_words(), homed])
	# A look round inside, offered there and done.
	_put(pet, Vector2i(13, 2))
	var look := pet.can_do().filter(func(each: Dictionary) -> bool: return each["verb"] == "look_inside")
	_check(look.size() == 1 and "look round inside the shed" in str(look[0]["words"]), "inside, she can look round it: %s" % [pet.can_do().map(func(e: Dictionary) -> String: return e["words"])])
	_check("look_inside" in Companion._errand_verbs("i will check this shed for loot.") and "look" not in Companion._errand_verbs("i will check this shed for loot."),
		"\"check this shed for loot\" promises that look, not a look off somewhere")
	var kit := World.put_on_ground(World.items.mint("bandaging_kit", "built"), Vector2i(14, 3))
	if not look.is_empty():
		pet._start_errand(look[0], pet._serial)
	_step_until(func() -> bool: return pet.errand.is_empty(), 60)
	var narrated := pet._exchange.filter(func(turn: Dictionary) -> bool: return "You looked round inside the shed" in str(turn["text"]))
	_check(pet.errand.is_empty() and not narrated.is_empty() and "bandaging kit on the floor" in str(narrated.back()["text"]).to_lower(),
		"the look done, what she found is told to her voice: %s" % [narrated.back()["text"] if not narrated.is_empty() else pet._exchange.slice(-3)])
	World.take_from_ground(kit, 0)
	# She follows her player in, and never stops in the doorway.
	_settle(pet)
	_put(owner, Vector2i(14, 2))
	owner.facing = Vector2i(0, -1)
	_put(pet, Vector2i(11, 4))
	_step_until(func() -> bool: return SHED.has_point(pet.tile) and not Companion.door_cells().has(pet.tile) and pet.current_intent == Companion.Intent.FOLLOW, 80)
	for i in 20:
		World.step()
	_check(SHED.has_point(pet.tile) and not Companion.door_cells().has(pet.tile), "her player went in: she followed, inside and off the door's cells (%s)" % pet.tile)
	# Asked to step aside in the doorway (standing as told): off it, and she stays off it.
	_told_to_stay(pet)
	_put(owner, Vector2i(13, 5))
	owner.facing = Vector2i(0, -1)
	_put(pet, Vector2i(13, 4))
	pet.hold_tile = pet.tile
	var way := pet.can_do().filter(func(each: Dictionary) -> bool: return each["verb"] == "make_way")
	_check(way.size() == 1 and pet.can_do()[0]["verb"] == "make_way", "in the doorway, stepping out of the way is offered first (%s)" % [way])
	_check("make_way" in Companion._errand_verbs("i will step aside.") and "make_way" in Companion._errand_verbs("sorry, let me get out of your way."),
		"\"step aside\" and \"get out of your way\" promise it")
	if not way.is_empty():
		pet._start_errand(way[0], pet._serial)
	for i in 40:
		World.step()
	_check(pet.tile != Vector2i(13, 4) and not Companion.door_cells().has(pet.tile) and pet.hold_tile == pet.tile,
		"asked, she stepped off the doorway and holds there, not back in it (%s)" % pet.tile)
	# A bump moves her out of the way, never into a doorway.
	_settle(pet)
	_put(pet, Vector2i(5, 9))
	_put(owner, Vector2i(4, 9))
	owner.facing = Vector2i(1, 0)
	pet.bumped(Vector2i(1, 0))
	for i in 12:
		World.step()
	_check(pet.tile.y != 9 and not Companion.door_cells().has(pet.tile), "bumped, she stepped aside, off her player's way (%s)" % pet.tile)
	# A fight: her player inside, an imp coming to the door: she holds it, and leaves it after.
	_settle(pet)
	_put(owner, Vector2i(14, 1))
	_put(pet, Vector2i(14, 2))
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "HouseImp%d" % World.tick, "tile": Vector2i(12, 5)}) as Monster
	imp.sight_range = 0  # It stays where it is: the hold is hers, not the fight's.
	var offered := pet.can_do().filter(func(each: Dictionary) -> bool: return each["verb"] == "hold_door")
	_check(offered.size() == 1 and offered[0]["cell"] == Vector2i(13, 3), "an imp near the door, her player inside: holding the door is offered (%s)" % [offered])
	_step_until(func() -> bool: return pet.tile == Vector2i(13, 3), 40)
	_check(pet.tile == Vector2i(13, 3), "guarding, she takes the door's inside cell herself (%s)" % pet.tile)
	World.damage(imp, 999)
	for i in 40:
		World.step()
	_check(not Companion.door_cells().has(pet.tile), "the imp down, she steps off the door (%s)" % pet.tile)
	if is_instance_valid(imp) and imp.spawned:
		World.despawn(imp)
	for body: GridEntity in World.townsfolk():
		(body as Resident)._hide_until = -1  # They saw the imp; the tests after are of quiet days.
	_put(owner, Vector2i(2, 2))
	for i in 3:
		World.step()
	# A friend and a threat in sight in one moment: the threat told last, as the danger (228 amended).
	var friends := pet.friends_seen()
	if friends.is_empty():
		# None in sight from here: she goes to stand by one of the town's people.
		for body: GridEntity in World.townsfolk():
			for offset: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				var at := body.tile + offset
				var beside := at + offset.sign()
				if friends.is_empty() and World.is_free(at) and World.is_free(beside) and World.has_line_of_sight(at, body.tile):
					_put(pet, at)
					_put(owner, beside)
					pet._seen_cells_tick = -1
					if pet.friends_seen().has(body):
						friends = [body]
	if friends.is_empty():
		_check(false, "a resident in her sight for the threat-leads case")
		return
	var spot := Vector2i(-1, -1)
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var at := pet.tile + Vector2i(dx, dy)
			var away := mini(World.distance(pet.tile, at), World.distance(owner.tile, at))
			if spot == Vector2i(-1, -1) and away > Companion.COMBAT_RANGE and World.distance(pet.tile, at) <= 6 \
					and World.is_free(at) and World.has_line_of_sight(pet.tile, at):
				spot = at
	var lurker := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "LurkImp%d" % World.tick, "tile": spot}) as Monster
	lurker.sight_range = 0
	pet._known_friends.erase(friends[0].get_instance_id())
	pet._known_hostiles.erase(lurker.get_instance_id())
	pet._was_in_fight = false
	World.step()
	var told: Array = pet._exchange.slice(-3).map(func(turn: Dictionary) -> String: return str(turn["text"]))
	_check(told.size() == 3 and "came into sight" in told[0] and "came into sight" in told[1] and "is the danger here" in told[2]
		and pet.refer(lurker, true).to_lower() in told[1].to_lower(), "the friend told first, the imp last, named the danger (%s)" % [told])
	World.despawn(lurker)
	for body: GridEntity in World.townsfolk():
		(body as Resident)._hide_until = -1
	for i in 3:
		World.step()


func _test_bodies_only_near() -> void:
	print("
== a town's residents have bodies only while someone is near; out of play while none (decision 355) ==")
	var recall: int = _main.recall_tiles
	var retire: int = _main.retire_tiles
	_main.recall_tiles = 4
	_main.retire_tiles = 6
	World.towns.note_rescue(STORE, "rs-near", "Nell", "cook")
	var player := _player()
	var pet := _companion()
	_put(player, Vector2i(26, 17))
	_put(pet, Vector2i(27, 17))
	_sync()
	_check(World.townsfolk().is_empty(), "everyone 20 and more cells off the store: no bodies (%s)" % [World.townsfolk().map(
		func(body: GridEntity) -> String: return "%s %s %s" % [(body as Resident).worker_id, body.tile, Resident.Doing.keys()[(body as Resident).doing]])])
	_check(not World.towns.in_play.call(STORE), "and the town is not in play: a raid takes its people off the record")
	_put(player, Vector2i(8, 3))
	_sync()
	_check(not World.townsfolk().is_empty() and World.towns.in_play.call(STORE), "the player 3 cells off: bodies, and in play (%d)" % World.townsfolk().size())
	_put(player, Vector2i(10, 3))
	_sync()
	_check(not World.townsfolk().is_empty() and World.towns.in_play.call(STORE), "5 off, between the two: kept")
	_put(player, Vector2i(26, 17))
	_sync()
	_check(World.townsfolk().is_empty() and not World.towns.in_play.call(STORE), "far again: gone, and out of play")
	_check(World.towns.residents(STORE).has("rs-near"), "still the town's: only the body went, not her")
	_main.recall_tiles = recall
	_main.retire_tiles = retire
	_put(player, Vector2i(2, 2))
	_sync()



## A level-placed captive (decision 518): the road level's camp holds a
## carpenter's daughter of the town from the start.
func _test_placed_captive() -> void:
	print("\n== a level-placed captive: a camp's holds, found or minted with kin, taken as a raid takes (decision 518) ==")
	var camp := ROAD + "/camp"
	_check(not _main._placed_captives.has(camp), "at boot the town had nobody to be kin to: the hold waited")
	_check(_main._place_captives(_main._world_map) == 1, "the next pass, the town peopled, places it")
	var held: Array = World.towns.captives(STORE).filter(func(each: Dictionary) -> bool: return str(each.get("held_by", "")) == camp)
	_check(held.size() == 1 and str(held[0].get("name", "")) == "Tilda" and str(held[0].get("by", "")) == "goblins", "the camp holds Tilda of the town: %s" % [held])
	if held.is_empty():
		return
	var who := str(held[0]["id"])
	var worker := World.production.worker(who)
	_check(bool(worker.get("away", false)) and str(worker.get("origin", "")) == "placed" and who not in World.towns.residents(STORE), "minted into the town with origin placed, away, off the roster")
	var card := Townsfolk.card_of(World.production, who)
	var kin: Dictionary = card.get("kin", {})
	_check(kin.has("rs-folk00") and str(kin["rs-folk00"]) == "parent and child" and str(card.get("traits", {}).get("pronoun", "")) == "she", "kin to the first carpenter by id, a daughter: %s" % [kin])
	var father := Townsfolk.card_of(World.production, "rs-folk00")
	var father_facts: Array = father.get("facts", []).map(func(f: Dictionary) -> String: return str(f["text"]))
	var raiders := ResidentCard.faction_name("goblins")
	_check("Tilda is Folk0's daughter." in father_facts and "Tilda, his daughter, was carried off by %s before you came; they hold her at their camp." % raiders in father_facts,
		"his card: the kinship and the loss, no raid and no date: %s" % [father_facts.slice(-2)])
	var her_facts: Array = card.get("facts", []).map(func(f: Dictionary) -> String: return str(f["text"]))
	_check("Tilda was carried off by %s; they hold her at their camp." % raiders in her_facts, "her own card: %s" % [her_facts.back()])
	World.production.set_away("rs-folk00", false)
	var plea := Offers.of("rs-folk00", Net.player_id)
	var rescue: Array = plea.filter(func(o: Dictionary) -> bool: return str(o.get("what", {}).get("captive", "")) == who)
	_check(rescue.size() == 1 and str(rescue[0].get("title", "")) == "Bring Tilda home" and str(rescue[0].get("what", {}).get("held_by", "")) == camp and str(rescue[0].get("words", "")).contains(raiders),
		"the kin's rescue commission at the counter, 331's, unchanged: %s" % [rescue.map(func(o: Dictionary) -> String: return str(o.get("words", "")))])
	World.production.set_away("rs-folk00", true)
	var before: int = World.towns.captives(STORE).size()
	_check(_main._place_captives(_main._world_map) == 0 and World.towns.captives(STORE).size() == before, "placed once: a second pass places nothing")
	_check(World.holdings.take(camp, Factions.NOBODY), "(the camp falls)")
	_check(who in World.towns.residents(STORE) and not bool(World.production.worker(who).get("away", false)), "its fall brings her home, a resident again")
	var home_facts: Array = Townsfolk.card_of(World.production, who).get("facts", []).map(func(f: Dictionary) -> String: return str(f["text"]))
	_check(home_facts.back() == "Tilda came home from %s." % raiders, "and her card says so: %s" % [home_facts.back()])
	_check(_main._place_captives(_main._world_map) == 0, "a fallen camp holds nobody: nothing placed again")
	var gone: Array[String] = [camp]
	_check(_main._place_captives(_main._world_map, gone) == 0 and not _main._placed_captives.has(camp), "a camp gone from the levels is forgotten")
	_check(World.towns.died(STORE, who, "the test's end"), "(Tilda out of the town again, so the later tests see the roster they expect)")


## Aldous's secrets (decision 546, npc's side, part 3): lore's crypt rows,
## told to a player he trusts and to nobody else; Main marks who was told.
func _test_crypt_secrets() -> void:
	print("\n== the crypt's secrets: Aldous knows the founding and the alms, tells one he trusts, and Main marks them told (decision 546, npc's side, part 3) ==")
	Lore.reload()
	var ids := func(knower: String) -> Array: return Lore.known_by(knower).map(func(f: Dictionary) -> String: return str(f["id"]))
	_check("crypt.founders" in ids.call("priest") and "crypt.alms_down" in ids.call("priest") and "crypt.pip_carries" in ids.call("priest") and not "crypt.draugr_bargains" in ids.call("priest"),
		"the priest knows the founding, the alms and Pip's errand, not the draugr's bargain: %s" % [ids.call("priest").filter(func(id: String) -> bool: return id.begins_with("crypt."))])
	_check("crypt.alms_down" in ids.call("acolyte") and "crypt.pip_carries" in ids.call("acolyte") and not "crypt.founders" in ids.call("acolyte") and "crypt.pip_carries" in ids.call("pip") and "crypt.draugr_bargains" in ids.call("draugr"),
		"the acolyte, Pip and the draugr know their rows")
	_check("crypt.keep_away" in ids.call("townsfolk") and not "crypt.founders" in ids.call("townsfolk") and Lore.known_by("priest").filter(func(f: Dictionary) -> bool: return str(f["id"]) == "crypt.founders")[0]["secret"] == true,
		"the town keeps away and knows no more; a secret is marked so")
	var priest := "priest:" + STORE
	if World.production.worker(priest).is_empty():
		World.production.add_worker(priest, "Aldous", ["priest"], STORE, "appointed")
	var told: Array = []
	Offers.ctx["secret_told"] = func(player_id: String, fact_id: String) -> void: told.append([player_id, fact_id])
	var voice := Resident.new()
	voice.worker_id = priest
	voice.person = "Aldous"
	voice.trade = "priest"
	voice.town = STORE
	voice.asked_by = "p-stranger"
	var founders := "The town's first folk moved the old dead down to make room for their own, the oldest as far down as they dared go."
	_check(not founders in voice.world_facts() and told.is_empty(), "a stranger is told no secret")
	var card := Townsfolk.card_of(World.production, priest)
	Standing.bump(card, "p-friend", Standing.setting("trusted"), "brought the sick home", World.production.now())
	World.production.set_card(priest, card)
	voice.asked_by = "p-friend"
	var facts := voice.world_facts()
	_check(founders in facts and told.any(func(t: Array) -> bool: return t[0] == "p-friend" and t[1] == "crypt.founders"), "one he trusts is told, and Main hears which: %s / %s" % [told, facts])
	# A secret the budget cuts is not reported told (546 amended; lore's old gods filled his budget).
	var days: Dictionary = Townsfolk.days()
	var had_chars: Variant = days.get("lore_chars")
	days["lore_chars"] = {voice.hidden_type(): 1}
	told.clear()
	var squeezed := voice.world_facts()
	_check(squeezed.is_empty() and told.is_empty(), "a budget too small for any secret: none said, none reported told (%s / %s)" % [squeezed, told])
	if had_chars == null:
		days.erase("lore_chars")
	else:
		days["lore_chars"] = had_chars
	voice.asked_by = ""
	_check(not founders in voice.world_facts(), "spoken to by nobody in particular: no secret")
	Offers.ctx.erase("secret_told")
	voice.free()
	_main._secret_told("p-friend", "crypt.founders")
	_main._secret_told("p-other", "star_fall.age")
	_check(bool(_main._crypt_told.get("p-friend", false)) and not _main._crypt_told.has("p-other"), "Main marks the crypt's secrets told, no other")
	_main._secret_told("p-other", "old_gods.war")
	_check(bool(_main._crypt_told.get("p-other", false)), "and the old gods' (lore's old_gods.*), the same secret's deeper why")
	_main._crypt_told.clear()


## The words said and one clause of how (336 amended; Jeff's play on

## v0.1.160): the model's stage direction round the words never reaches a
## bubble; it becomes a third-person aside, or nothing.
func _test_aloud() -> void:
	print("\n== the voice: the words said in the bubble, the model's narration turned to one third-person clause beside them, or dropped (336 amended) ==")
	var cases := [
		["You nod, your voice steady despite the rain. \"Jeff, I've been meaning to thank you for the food you brought last time. It was kind of you.\"", "Aldous",
			"Jeff, I've been meaning to thank you for the food you brought last time. It was kind of you.", "his voice steady despite the rain", "Aldous's line from the box: the quoted words, both sentences; the voice clause over a bare nod"],
		["You look up from your workbench, your voice low and careful. \"I owe the town 29 gold.\"", "Snagfin",
			"I owe the town 29 gold.", "looking up from his workbench, low and careful", "Snagfin's line from the box: a gesture with its place joins the voice within eight words"],
		["You look up from the long bench by the door, your voice low. \"Aye.\"", "Snagfin", "Aye.", "his voice low", "over eight words joined: the voice clause alone"],
		["You've got a better trade than me, at least. What's the town needing most?", "Pip", "You've got a better trade than me, at least. What's the town needing most?", "", "real speech beginning with You is kept whole, no aside"],
		["You look tired, friend. Sit a while.", "Bea", "You look tired, friend. Sit a while.", "", "\"You look tired\" is speech, not a look up from the bench"],
		["*nods* Aye, the well is low.", "Bea", "Aye, the well is low.", "nodding", "an asterisked action becomes the aside"],
		["(sighs) It is what it is. You shrug. We manage.", "Bea", "It is what it is. We manage.", "sighing", "a bracketed action first, a shrug mid-line out of the speech, the rest joined"],
		["You nod and say nothing more.", "Bea", "", "nodding", "narration alone leaves no words: not said"],
		["“Aye, the smith owes me.” You turn back to the fire.", "Bea", "Aye, the smith owes me.", "turning back to the fire", "curly quotes count; a gesture after the quote"],
		["Bea says: \"You turn to go. Stay, the night is cold.\"", "Bea", "Stay, the night is cold.", "", "the own-name lead cut first; a turn to go is movement, no aside"],
		["You smile. \"Come in.\" Aldous's voice is warm.", "Aldous", "Come in.", "his voice is warm", "the speaker's name turned to the pronoun, never in the aside"],
		["I know little of him. He came by the east road. Ask the lawspeaker.", "Bea", "I know little of him. He came by the east road.", "", "two sentences still, after the filter"],
	]
	for each: Array in cases:
		var got := Resident.spoken(str(each[0]), str(each[1]), "his")
		_check(str(got["say"]) == str(each[2]) and str(got["aside"]) == str(each[3]), "%s: \"%s\" + \"%s\"" % [each[4], got["say"], got["aside"]])


## Talk with no panel (decision 536): a kin's plea spoken back word for
## word when asked for work, standing, taken by a yes; the mind for the rest.
func _test_offer_words() -> void:
	print("\n== talk with no panel: asked for work, the plea is spoken as it is written and a yes takes it (decision 536) ==")
	var rules := Townsfolk.rules().duplicate(true)
	rules["sick"] = {"chance": 0.0, "winter": 1, "hungry": 1, "old": 1, "days": 5, "death_old": 0.0, "visit_hours": 2, "kinds": ["a cough"]}
	Townsfolk.use_rules(rules)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	for id: String in ["rs-bram", "rs-snag", "rs-law"]:
		World.production.set_away(id, true)
	var hut: String = _main._healers_hut_of(STORE)
	if not hut.is_empty():
		World.production.set_away("medicine_man:" + hut, true)  # Away: the plea is to walk the sick one to the hut.
	World.production.set_away("rs-folk11", false)
	var kin := Townsfolk.card_of(World.production, "rs-folk11")
	kin["kin"] = {"rs-folk10": "sister or brother"}
	kin["asks"] = []
	World.production.set_card("rs-folk11", kin)
	var sick := Townsfolk.card_of(World.production, "rs-folk10")
	sick["kin"] = {"rs-folk11": "sister or brother"}
	World.production.set_card("rs-folk10", sick)
	Townsfolk._set_sickness(World.production, "rs-folk10", {"since": Townsfolk.day_of(World.steps), "kind": "a cough", "treated": -1, "cured_by": ""})
	DayNight.set_hour(11.0)
	_sync()
	var body := _body("rs-folk11")
	var player := _player()
	var plea: Array = Offers.of("rs-folk11", Net.player_id).filter(func(o: Dictionary) -> bool: return str(o.get("kind", "")) == Offers.PLEA and not bool(o.get("open", false)))
	_check(body != null and player != null and not hut.is_empty() and plea.size() == 1, "(Folk11 stands in the town with a plea for Folk10: %s)" % [plea.map(func(o: Dictionary) -> String: return str(o.get("title", "")))])
	if body == null or player == null or hut.is_empty() or plea.is_empty():
		return
	_put(player, _main._nearest_free(body.tile + Vector2i(1, 0)))
	var mind := VoiceMind.new()
	_main._resident_mind = mind
	_main._chat_tick.clear()
	_main._player_said(player, "Any work for me?")
	World.step()
	var standing: Dictionary = _main._standing.get(Net.player_id, {})
	_check(mind.asks.is_empty() and str(standing.get("id", "")) == str(plea[0]["id"]) and str(standing.get("title", "")) == str(plea[0]["title"]),
		"asked for work: no mind asked, the plea spoken stands: %s" % [standing.get("title", "")])
	_main._chat_tick.clear()
	_main._player_said(player, "Is the kitchen busy?")
	World.step()
	_check(mind.asks.size() == 1 and _main._standing.has(Net.player_id), "a line of the player's own goes to the mind; the plea still stands")
	_main._chat_tick.clear()
	_main._player_said(player, "Yes, I'll take it.")
	World.step()
	var open: Array = Offers.of("rs-folk11", Net.player_id).filter(func(o: Dictionary) -> bool: return bool(o.get("open", false)) and str(o.get("id", "")) == str(plea[0]["id"]))
	_check(mind.asks.size() == 1 and open.size() == 1 and not _main._standing.has(Net.player_id), "a yes takes it through the accept path: the plea is theirs, open, and nothing stands")
	_main._chat_tick.clear()
	_main._player_said(player, "Yes")
	World.step()
	_check(mind.asks.size() == 2, "a yes with nothing standing is a line like any other: the mind's")
	_main._chat_tick.clear()
	_main._player_said(player, "What's the news?")
	World.step()
	_check(mind.asks.size() == 3 or _main._standing.has(Net.player_id), "news: a rumour spoken if they hold one, else the mind")
	_main._standing.clear()
	_main._resident_mind = null
	World.production.set_away("rs-folk11", true)
	Townsfolk._set_sickness(World.production, "rs-folk10", {})
	_sync()


## A monster that talks (decision 546, npc's side; the draugr, 548): its
## first words stand unasked, an amount said takes them, a bare yes does not.
func _test_monster_talk() -> void:
	print("\n== a monster that talks: the deal spoken unasked and standing, taken by an amount said, never by a bare yes (decision 546, npc's side) ==")
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	var player := _player()
	var talker := _main._spawn({"script": "res://tests/talker_stub.gd", "shape": "capsule", "name": "Draugr", "tile": _main._nearest_free(player.tile + Vector2i(2, 0))}) as Monster
	_check(talker != null and talker.talks and _main._talkers.has(talker.get_instance_id()), "(a talking monster spawned and hooked)")
	if talker == null:
		return
	var mind := VoiceMind.new()
	_main._resident_mind = mind
	_main._standing.clear()
	talker.offer_spoken.emit(Net.player_id, talker.offers_for(Net.player_id)[0])
	var standing: Dictionary = _main._standing.get(Net.player_id, {})
	_check(str(standing.get("worker", "")) == String(talker.get_path()) and str(standing.get("title", "")) == "Face the draugr", "he talks first: his deal stands, keyed by his path: %s" % [standing.get("title", "")])
	_main._chat_tick.clear()
	_main._player_said(player, "Yes.")
	World.step()
	_check(talker.got == [0] and _main._standing.has(Net.player_id) and mind.asks.is_empty(), "a bare yes reaches him with no gold: his own refusal, and the deal still stands (no resident mind): %s" % [talker.got])
	World.economy.add_gold(Net.player_id, 30, "the test")
	_main._chat_tick.clear()
	_main._player_said(player, "give 40")
	World.step()
	_check(talker.got == [0] and _main._standing.has(Net.player_id), "over the purse: refused by Main, he is not asked: %s" % [talker.got])
	_main._chat_tick.clear()
	_main._player_said(player, "Draugr, here is 16")
	World.step()
	_check(talker.got == [0, 16] and talker.pact and not _main._standing.has(Net.player_id), "an amount said reaches accept_offer with it; ok, nothing stands: %s" % [talker.got])
	_main._chat_tick.clear()
	_main._player_said(player, "Any work for me?")
	World.step()
	_check(not _main._standing.has(Net.player_id), "with a pact on he offers nothing: nothing stands")
	talker.pact = false
	_main._chat_tick.clear()
	_main._player_said(player, "Any work for me?")
	World.step()
	_check(_main._standing.has(Net.player_id), "asked, he speaks the deal again and it stands")
	talker.offer_withdrawn.emit(Net.player_id)
	_check(not _main._standing.has(Net.player_id), "withdrawn from his side: nothing stands")
	_main._resident_mind = null
	World.despawn(talker)


## Pip's alms run (decision 546, npc's side): seated as the priest's
## apprentice with the companion table's Pip on his card, down and back
## bodiless, lost once the secret is out, found at the niche.
func _test_alms_run() -> void:
	print("\n== Pip's alms run: the priest's apprentice carries the altar's gold down on the world tick, is lost once the secret is out, and found at the niche (decision 546, npc's side) ==")
	if World.economy == null or not World.economy.has_method("altar_gold"):
		_check(true, "(economy's 546 is not here: skipped)")
		return
	var rules := Townsfolk.rules().duplicate(true)
	rules["runner"] = {"name": "Pip", "trade": "acolyte", "hour": 6, "hours_each_way": 1, "lost_chance": 1.0, "barrow": TOWN, "niche": "niche", "found_reach": 2, "leanings": {"superstition": 2, "intellect": 4}}
	Townsfolk.use_rules(rules)
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	var player := _player()
	var priest := "priest:" + STORE
	if World.production.worker(priest).is_empty():
		World.production.add_worker(priest, "Aldous", ["priest"], STORE, "appointed")  # The test town is at its room: a worker, not a move-in.
	_check(not World.production.worker(priest).is_empty(), "(Aldous keeps the test town's temple)")
	# The town has a Pip of its own already, a carpenter at a bench (the box, 2026-10-20).
	var carp := "carp:" + STORE
	if World.production.worker(carp).is_empty():
		World.production.add_worker(carp, "Pip", ["carpenter"], STORE, "settled")
	World.production.add_workshop("bench:" + STORE, "carpenter", STORE)
	_check(World.production.assign("bench:" + STORE, carp), "(Pip the carpenter works a bench)")
	World.economy.add_gold(Net.player_id, 40, "the test")
	World.economy.temple_offering(STORE, Net.player_id, false)
	World.economy.temple_offering(STORE, Net.player_id, false)
	var altar: int = World.economy.altar_gold(STORE)
	_check(altar > 0, "(two offerings leave gold at the altar above the priest's day: %d)" % altar)
	_main._alms_runs.clear()
	_main._runs_day.clear()
	_main._crypt_told.clear()
	DayNight.set_hour(5.0)
	_main._alms_runs_tick()
	_check(_main._alms_runs.is_empty(), "before the hour, no run")
	DayNight.set_hour(6.5)
	_main._alms_runs_tick()
	var run: Dictionary = _main._alms_runs.get(STORE, {})
	var pip := str(run.get("who", ""))
	_check(not run.is_empty() and int(run["gold"]) == altar and World.economy.altar_gold(STORE) == 0 and bool(World.production.worker(pip).get("away", false)),
		"at the hour Pip takes the altar's gold and is away: %s with %d" % [pip, int(run.get("gold", 0))])
	_check(str(World.production.worker(pip).get("name", "")) == "Pip" and str(World.production.worker(pip).get("master", "")) == priest and str(World.production.worker(pip).get("origin", "")) == "settled",
		"seated as a settled resident, the priest's apprentice")
	var pips: Array = World.production.worker_ids(STORE).filter(func(id: String) -> bool: return str(World.production.worker(id).get("name", "")) == "Pip")
	_check(pip == carp and Array(World.production.worker(pip).get("trades", [])) == ["acolyte"] and pips.size() == 1 and str(World.production.workshop("bench:" + STORE).get("worker", "")).is_empty(),
		"the town's own Pip, the carpenter, is the acolyte in place: one Pip, trade acolyte, his bench left empty (%s)" % [pips])
	var card := Townsfolk.card_of(World.production, pip)
	var legacy: Dictionary = CompanionCard.legacy_look("Pip")
	_check(Townsfolk.leaning_of(World.production, pip, "superstition") == 2 and Townsfolk.leaning_of(World.production, pip, "intellect") == 4 and (legacy.is_empty() or legacy.keys().all(func(k: Variant) -> bool: return card.get("look", {}).get(k) == legacy[k])),
		"his card is the companion table's Pip: superstition 2, intellect 4, the legacy look")
	World.steps += 3 * (DayNight.day_steps / 24)
	_main._alms_runs_tick()
	_check(_main._alms_runs.is_empty() and World.economy.below_gold(STORE) == altar and not bool(World.production.worker(pip).get("away", false)), "two hours on he is home and the gold lies below: %d" % World.economy.below_gold(STORE))
	_main._alms_runs_tick()
	_check(_main._alms_runs.is_empty(), "one run a day")
	# The secret out: the next run goes wrong (chance 1).
	_main._crypt_told[Net.player_id] = true
	World.economy.temple_offering(STORE, Net.player_id, false)
	World.economy.temple_offering(STORE, Net.player_id, false)
	var second: int = World.economy.altar_gold(STORE)
	World.steps += DayNight.day_steps
	DayNight.set_hour(6.5)
	_main._alms_runs_tick()
	World.steps += DayNight.day_steps / 24 + 1
	_main._alms_runs_tick()
	run = _main._alms_runs.get(STORE, {})
	var aldous_facts: Array = Townsfolk.card_of(World.production, priest).get("facts", []).map(func(f: Dictionary) -> String: return str(f["text"]))
	_check(bool(run.get("lost", false)) and bool(World.production.worker(pip).get("away", false)) and World.economy.below_gold(STORE) == altar and "Pip has not been seen since morning." in aldous_facts,
		"at the altar the run goes wrong: Pip is lost below with the gold, and Aldous's card says he has not been seen: %s" % [aldous_facts.back()])
	World.steps += DayNight.day_steps
	_main._alms_runs_tick()
	_check(bool(_main._alms_runs.get(STORE, {}).get("lost", false)), "a day on, still lost: nobody has come")
	_put(player, _main._nearest_free(Vector2i(14, 9)))
	_main._alms_runs_tick()
	var pip_facts: Array = Townsfolk.card_of(World.production, pip).get("facts", []).map(func(f: Dictionary) -> String: return str(f["text"]))
	_check(_main._alms_runs.is_empty() and not bool(World.production.worker(pip).get("away", false)) and World.economy.below_gold(STORE) == altar + second and pip_facts.back().ends_with("saw the draugr bargain for gold, and lived."),
		"a player at the niche finds him: the gold goes down, he comes home with the lived fact: %s" % [pip_facts.back()])
	_main._crypt_told.clear()
	World.production.set_away(pip, true)
	World.production.set_away(priest, true)
	_put(player, Vector2i(2, 2))

func _sync() -> void:
	_main._sync_residents()
	World.step()


func _body(who: String) -> Resident:
	for body: GridEntity in World.townsfolk():
		if (body as Resident).worker_id == who:
			return body
	return null


func _step_until(condition: Callable, limit: int) -> void:
	for i in limit:
		if condition.call():
			return
		World.step()


# --- helpers ------------------------------------------------------------------

func _told_to_stay(pet: Companion) -> void:
	pet._serial += 1
	pet._set_stance(Companion.Stance.HOLD, pet._serial, "test")
	pet._instruction = "Player just said to you: \"Stay here.\""
	pet._instruction_tick = World.tick


func _settle(pet: Companion) -> void:
	pet.stance = Companion.Stance.GUARD
	pet._instruction = ""


func _put(entity: GridEntity, tile: Vector2i) -> void:
	if entity != null and entity.tile != tile:
		World._relocate(entity, tile)


## A free, walkable cell of the store's ground, not [param besides].
func _town_cell(besides: Vector2i) -> Vector2i:
	for y in 10:
		for x in 16:
			var at := Vector2i(x, y)
			if at != besides and World.is_free(at) and Stockpile.place_at(World.holdings, TOWN, at) == STORE:
				return at
	return Vector2i(-1, -1)


func _trade() -> String:
	return str(_main._records[Net.player_id].companion.get("traits", {}).get("trade", ""))


func _pet_name() -> String:
	return String(_main._records[Net.player_id].companion.get("name", ""))


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _companion() -> Companion:
	for entity in World.get_entities():
		if entity is Companion and entity.spawned:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _test_hails() -> void:
	print("\n== a resident with something to say hails a player come near, once a day, one a minute, the lowest ask (decision 554) ==")
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	DayNight.set_hour(12.0)
	World.towns.note_rescue(STORE, "rs-mara", "Mara", "cook")
	_sync()
	var mara := _body("rs-mara")
	var player := _player()
	var pid: String = player.player_id
	var now := World.production.now()
	var today := Townsfolk.day_of(now)
	# The lively trial's switch (554 amended): the user turn by townsfolk.json hail.lively, for the shared cues only; strict one edit away.
	var hail_rules: Dictionary = Townsfolk.rules().get("hail", {})
	var was_lively: Variant = hail_rules.get("lively")
	hail_rules["lively"] = true
	var news_turn := str(mara.hail_ask("Jeff", {"kind": "news", "text": "I heard today that a cart broke."}, 1).get("user", ""))
	var plea_turn := str(mara.hail_ask("Jeff", {"kind": "plea", "text": "I owe the town 3 gold; could you spare some of it?"}, 2).get("user", ""))
	_check(news_turn.contains("in your own colour") and news_turn.contains("no weather, no cause") and not plea_turn.contains("in your own colour") and plea_turn.contains("add no place, cause, name or detail"),
		"lively on: the news takes the trial's bounded turn, a plea keeps the strict one")
	hail_rules["lively"] = false
	news_turn = str(mara.hail_ask("Jeff", {"kind": "news", "text": "I heard today that a cart broke."}, 3).get("user", ""))
	_check(not news_turn.contains("in your own colour") and news_turn.contains("add no place, cause, name or detail"), "lively off: the strict sentence for all")
	if was_lively == null:
		hail_rules.erase("lively")
	else:
		hail_rules["lively"] = was_lively
	_check(mara != null and mara.person == "Mara", "(Mara the cook stands in the town)")
	# The cues, pure: the first that applies, none said twice.
	var card := Townsfolk.card_of(World.production, "rs-mara")
	card.erase("hails")
	World.production.set_card("rs-mara", card)
	var cue := Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, "")
	_check(cue.get("kind") == "greeting" and "Jeff is a stranger to you" in str(cue.get("text", "")), "nothing else to say: a greeting by standing, a stranger (%s)" % [cue])
	var sky := "It is noon in high summer; the sky is clear"
	cue = Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, sky)
	_check(cue.get("kind") == "sky" and cue.get("text") == sky + ".", "the sky before the greeting (%s)" % [cue])
	Townsfolk._remember(STORE, "A wagon was struck on the road to the market", "Mara", true, now)
	cue = Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, sky)
	_check(cue.get("kind") == "news" and cue.get("text") == "I heard today that a wagon was struck on the road to the market.", "what the town noted today before the sky (%s)" % [cue])
	var log: Array = Offers._call(Offers.ctx, "memory", [STORE])
	var entry: Dictionary = log.back()
	entry["tier"] = TownMemory.MEMORY
	entry["ruling"] = {"ruling": "accept", "because": "two saw it", "step": now}
	Offers._call(Offers.ctx, "set_memory", [STORE, log])
	Resident.hail_done(World.production, "rs-mara", pid, cue, today, "")
	cue = Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, "")
	_check(cue.get("kind") == "ruling" and cue.get("text") == "I heard the lawspeaker rule today that a wagon was struck on the road to the market, because two saw it.",
		"the news said once, the ruling of today with his because (%s)" % [cue])
	Resident.hail_done(World.production, "rs-mara", pid, cue, today, "")
	cue = Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, sky)
	_check(cue.get("kind") == "sky", "then the sky")
	Resident.hail_done(World.production, "rs-mara", pid, cue, today, sky)
	cue = Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, sky)
	_check(cue.get("kind") == "greeting", "the same sky again: the greeting")
	Resident.hail_done(World.production, "rs-mara", pid, cue, today, sky)
	_check(Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, sky).is_empty(), "everything said: nothing")
	_check(Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, "It is dusk; rain falls").get("kind") == "sky", "the sky turned: that")
	card = Townsfolk.card_of(World.production, "rs-mara")
	_check(Resident.hailed_today(card, pid, today) and not Resident.hailed_today(card, pid, today + 1) and card["hails"]["said"].size() == 4 and card["hails"]["sky"] == sky,
		"her card remembers the day, the four things said and the sky spoken of")
	_check(Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, "It is dusk; rain falls", Offers.ctx, ["It is dusk; rain falls."]).is_empty(),
		"but not one this player heard today from someone else")
	_check(Resident.hail_cue("rs-mara", STORE, pid, "Bo", World.production, now, "", Offers.ctx, ["Bo is a stranger to you; you greet them as the town does a newcomer."]).get("kind") == "greeting",
		"a greeting is each resident's own: another's does not silence it")
	var undone := Townsfolk.card_of(World.production, "rs-mara")
	var said_before: int = undone["hails"]["said"].size()
	Resident.hail_undone(World.production, "rs-mara", pid, str(undone["hails"]["said"].back()))
	undone = Townsfolk.card_of(World.production, "rs-mara")
	_check(not Resident.hailed_today(undone, pid, today) and undone["hails"]["said"].size() == said_before - 1, "a hail not said gives back the day's mark and its text")
	_check(Resident.hail_cue("rs-mara", STORE, pid, "Bo", World.production, now, "", Offers.ctx, [], false).is_empty(), "greetings capped for the day: nothing, when a greeting was all there was")
	Resident.hail_done(World.production, "rs-mara", pid, {"kind": "greeting", "text": "Jeff is a stranger to you; you greet them as the town does a newcomer."}, today, sky)
	Townsfolk._remember(STORE, "Odo saw the wagon come home", "rs-mara", true, now)
	_check(Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, "").is_empty(), "their own event line is not news to them")
	log = Offers._call(Offers.ctx, "memory", [STORE])
	_check(bool(log.back().get("event", false)) and log.back().get("text") == "Odo saw the wagon come home", "the town's event lines carry the mark")
	var talk := TownMemory.note(log, "goblins did it", "rs-folk01", "", now)
	Offers._call(Offers.ctx, "set_memory", [STORE, log])
	var card2 := Townsfolk.card_of(World.production, "rs-mara")
	card2.erase("hails")
	World.production.set_card("rs-mara", card2)
	cue = Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, "")
	_check(cue.get("kind") == "ruling", "talk noted from speech is no news, nor their own event line nor the ruled one: the ruling (%s)" % [cue])
	Townsfolk._remember(STORE, "Odo saw the wagon come home safe", "rs-folk02", true, now + 1)
	cue = Resident.hail_cue("rs-mara", STORE, pid, "Jeff", World.production, now, "")
	_check(cue.get("text") == "I heard today that Odo saw the wagon come home safe.", "the newest event line, Odo kept his capital (%s)" % [cue])
	# Main's hail, through the voice path.
	card.erase("hails")
	World.production.set_card("rs-mara", card)
	var mind := VoiceMind.new()
	_main._resident_mind = mind
	var spoken: Array[String] = []
	var heard := func(kind: String, data: Dictionary) -> void:
		if kind == "speech":
			spoken.append("%s: %s" % [data.get("speaker", ""), data.get("text", "")])
	Net.message_received.connect(heard)
	_main._hail_at.clear()
	_main._blow_at.clear()
	_main._hail_tried.clear()
	_main._mind_last_ticks = 0
	_main._resident_asks.clear()
	_put(player, _main._nearest_free(mara.tile + Vector2i(5, 0)))
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "out of talking reach: nothing")
	_put(player, _main._nearest_free(mara.tile + Vector2i(1, 0)))
	_main._hails_tick()
	var trigger := str(_main._resident_asks[0]["ask"].get("trigger", "")) if not _main._resident_asks.is_empty() else ""
	_check(_main._resident_asks.size() == 1 and trigger.begins_with("hail: news, Mara to "), "within reach: her hail is queued as an ask, the news first (%s)" % trigger)
	World.step()
	var user := str(mind.asks[0].get("user", "")) if not mind.asks.is_empty() else ""
	_check(mind.asks.size() == 1 and "comes within speaking distance of you" in user and "One thing is on your mind: I heard today that" in user and "not the words above" in user,
		"the mind is asked for one line on that one thing (%s)" % user)
	_check(spoken == ["Mara: The kitchen's warm, at least."], "and what it says goes out as speech, 336's path (%s)" % [spoken])
	_check(Resident.hailed_today(Townsfolk.card_of(World.production, "rs-mara"), pid, today), "her card remembers the hail")
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "not twice today")
	var again := func() -> void:
		var fresh := Townsfolk.card_of(World.production, "rs-mara")
		fresh["hails"]["to"].erase(pid)
		World.production.set_card("rs-mara", fresh)
		_main._hail_tried.clear()
	again.call()
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "a hail in their hearing within the minute (her answer counts too): nothing")
	_main._hail_at.clear()
	_main._guides[pid] = Guide.new({})
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "led by a companion: nothing")
	_main._guides.erase(pid)
	player.hurt_tick = World.tick
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "a blow taken just now: nothing")
	player.hurt_tick = -100000
	_main._blow_at[pid] = World.tick
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "a blow given just now: nothing")
	_main._blow_at.clear()
	_main._mind_last_ticks = 999
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "the mind slow over its last answer: nothing")
	_main._mind_last_ticks = 0
	_main._resident_asks.append({"body": 0, "ask": {"serial": 0, "trigger": "a plea", "speaker": "Someone"}, "at": World.tick, "player": "", "peer": -1})
	_main._hails_tick()
	_check(_main._resident_asks.size() == 1 and not Resident.hailed_today(Townsfolk.card_of(World.production, "rs-mara"), pid, today),
		"an ask waiting: no hail, and none counted")
	_main._resident_asks.clear()
	_main._hails_tick()
	trigger = str(_main._resident_asks[0]["ask"].get("trigger", "")) if not _main._resident_asks.is_empty() else ""
	_check(_main._resident_asks.size() == 1 and trigger.begins_with("hail: ruling"), "free again: the next thing she has to say, the ruling (%s)" % trigger)
	_main._resident_asks.clear()
	# The greeting cap (the coordinator, after the soak): three a player a day from the whole town.
	var capped := Townsfolk.card_of(World.production, "rs-mara")
	capped["hails"]["to"].erase(pid)
	capped["hails"]["said"].append("I heard the lawspeaker rule today that a wagon was struck on the road to the market, because two saw it.")
	World.production.set_card("rs-mara", capped)
	_main._hail_tried.clear()
	_main._hail_heard.clear()
	_main._hail_at.clear()
	_main._hail_greetings[pid] = {"day": today, "n": 3}
	_main._hails_tick()
	_check(_main._resident_asks.is_empty(), "three greeted this player today: a fourth resident with only a greeting says nothing")
	_main._hail_greetings[pid] = {"day": today - 1, "n": 3}
	_main._hail_tried.clear()
	_main._hail_at.clear()
	_main._hails_tick()
	trigger = str(_main._resident_asks[0]["ask"].get("trigger", "")) if not _main._resident_asks.is_empty() else ""
	_check(_main._resident_asks.size() == 1 and trigger.begins_with("hail: greeting") and _main._hail_greetings[pid] == {"day": today, "n": 1},
		"a new day: greeted, and counted (%s)" % trigger)
	_main._resident_asks.clear()
	_main._hail_greetings.clear()
	Net.message_received.disconnect(heard)
	_main._resident_mind = null
	_main._hail_at.clear()
	_main._hail_tried.clear()
	World.despawn(mara)


func _test_greet() -> void:
	print("\n== clicked, a townsperson stops, turns and says a word; what they have to tell you follows (decision 560, npc's side) ==")
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	DayNight.set_hour(12.0)
	World.towns.note_rescue(STORE, "rs-mara", "Mara", "cook")
	_sync()
	var mara := _body("rs-mara")
	var player := _player()
	var pid: String = player.player_id
	_check(mara != null and mara.person == "Mara", "(Mara the cook stands in the town)")
	var rules: Dictionary = Townsfolk.rules().get("greet", {})
	_check(int(rules.get("stop_seconds", 0)) == 8 and int(rules.get("again_seconds", 0)) == 10 and rules.get("trades", {}).has("cook"), "townsfolk.json greet: the stop, the again window, the cook's lines")
	var cook: Array = rules["trades"]["cook"]
	_check(Resident.greet_word("cook", "stranger", rules, 3) in cook and Resident.greet_word("cook", "stranger", rules, 4) in cook
		and Resident.greet_word("cook", "stranger", rules, 3) != Resident.greet_word("cook", "stranger", rules, 4), "a stranger gets one of the cook's lines, by the day")
	_check(Resident.greet_word("cook", "wronged", rules, 3) == "You again." and Resident.greet_word("cook", "trusted", rules, 3) == "Good to see you.", "one the town knows gets the standing's word")
	_check(Resident.greet_word("weaver", "stranger", rules, 1) in rules["trades"]["default"], "a trade not listed: the default's")
	_check(str(rules.get("care", "")).begins_with("You're in my care") and Resident.greet_word("medicine_man", "stranger", rules, 2) in rules["trades"]["medicine_man"]
		and not Resident.greet_word("medicine_man", "stranger", rules, 2).begins_with("You're in my care"), "the medicine man's own lines; the care word only for one in his care, by Main (584 amended, npc's side)")
	var mind := VoiceMind.new()
	_main._resident_mind = mind
	var spoken: Array[String] = []
	var heard := func(kind: String, data: Dictionary) -> void:
		if kind == "speech":
			spoken.append("%s: %s|%s" % [data.get("speaker", ""), data.get("text", ""), data.get("aside", "")])
	Net.message_received.connect(heard)
	var card := Townsfolk.card_of(World.production, "rs-mara")
	card.erase("hails")
	World.production.set_card("rs-mara", card)
	_main._greet_at.clear()
	_main._hail_at.clear()
	_main._hail_tried.clear()
	_main._hail_heard.clear()
	_main._hail_greetings.clear()
	_main._resident_asks.clear()
	_put(player, _main._nearest_free(mara.tile + Vector2i(5, 0)))
	_main._greeted(player, mara)
	_check(spoken.is_empty() and mara.addressing.is_empty(), "out of talking reach: nothing")
	_put(player, _main._nearest_free(mara.tile + Vector2i(1, 0)))
	var tick_before := World.tick
	World.command(player, "greet", {"resident": String(mara.get_path())})
	_check(spoken.size() == 1 and spoken[0].begins_with("Mara: ") and spoken[0].get_slice("|", 0).trim_prefix("Mara: ") in cook and spoken[0].ends_with("|"),
		"the greet command: her word at once, one of the cook's, no aside, as speech (%s)" % [spoken])
	_check(mara.addressing == String(player.get_path()) and mara._address_until == tick_before + 8 * World.TICK_RATE, "she addresses the player for the stop")
	var d := player.tile - mara.tile
	var toward := Vector2i(signi(d.x), signi(d.y)) if absi(d.x) == absi(d.y) else (Vector2i(signi(d.x), 0) if absi(d.x) > absi(d.y) else Vector2i(0, signi(d.y)))
	_check(mara.facing == toward, "turned to face them (%s toward %s)" % [mara.facing, d])
	_check(_main._resident_asks.size() == 1 and str(_main._resident_asks[0]["ask"].get("trigger", "")).begins_with("greet: "),
		"and what she has to say today follows as a hail, brought forward (%s)" % [_main._resident_asks[0]["ask"].get("trigger", "") if not _main._resident_asks.is_empty() else ""])
	World.step()
	_check(spoken.size() == 2 and spoken[1] == "Mara: The kitchen's warm, at least.|", "the mind's line goes out as speech after the word (%s)" % [spoken])
	_main._greeted(player, mara)
	_check(spoken.size() == 2, "a second click within the again window: nothing new said")
	_check(not mara.addressing.is_empty(), "still addressing them")
	for i in 8 * World.TICK_RATE + 2:
		World.step()
	_check(mara.addressing.is_empty(), "the stop over: she goes about her day")
	_main._greet_at.clear()
	_put(player, _main._nearest_free(mara.tile + Vector2i(1, 0)))
	_main._greeted(player, mara)
	_check(spoken.size() == 3 and not mara.addressing.is_empty(), "after the window: greeted again (%s)" % spoken[2])
	for i in 8 * World.TICK_RATE + 2:
		World.step()
	_main._greet_at.clear()
	_put(player, _main._nearest_free(mara.tile + Vector2i(1, 0)))
	mara.doing = Resident.Doing.BED
	_main._greeted(player, mara)
	_check(spoken.size() == 4 and spoken[3] == "Mara: Not now.|" and mara.addressing.is_empty(), "in bed: no stop, the refusal word (%s)" % spoken[3])
	mara.doing = Resident.Doing.SQUARE
	_main._greet_at.clear()
	_put(player, _main._nearest_free(mara.tile + Vector2i(1, 0)))
	_main._resident_asks.append({"body": mara.get_instance_id(), "ask": {"serial": 0, "trigger": "x", "speaker": "Mara"}, "at": World.tick, "player": "", "peer": -1})
	_main._greeted(player, mara)
	_check(spoken.size() == 5 and spoken[4] == "Mara: Not now.|", "an ask of hers waiting: the same")
	_main._resident_asks.clear()
	Net.message_received.disconnect(heard)
	_main._resident_mind = null
	_main._greet_at.clear()
	_main._hail_at.clear()
	World.despawn(mara)


func _test_visible_work() -> void:
	print("\n== seen at their work: the bed at night, a task walked to and shown, the woodcutter's trip, the carpenter's cells, the lamp (decision 566, npc's side) ==")
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	for i in 14:
		World.production.set_away("rs-folk%02d" % i, true)
	World.production.set_away("rs-bram", true)
	DayNight.set_hour(12.0)
	World.towns.note_rescue(STORE, "rs-mara", "Mara", "cook")
	_sync()
	var mara := _body("rs-mara")
	_check(mara != null and mara.person == "Mara", "(Mara the cook stands in the town)")
	var sleep: Dictionary = Townsfolk.days().get("sleep", {})
	_check(int(sleep.get("from", 0)) == 21 and int(sleep.get("to", 0)) == 6, "residents.json sleep: 21 to 6")
	_check(not Resident.asleep_now(), "noon: nobody sleeps")
	# The bed and the head.
	var home: Rect2i = mara.places.get("home", Rect2i())
	var square: Rect2i = mara.places.get("square", Rect2i())
	_check(home.size != Vector2i.ZERO, "(she has a home: %s)" % [home])
	var bed := Resident.bed_cell(home, square)
	_check(home.has_point(bed) and World.is_walkable(bed), "the bed is a walkable corner of her home (%s)" % [bed])
	var corners: Array[Vector2i] = [home.position, home.position + Vector2i(home.size.x - 1, 0), home.position + Vector2i(0, home.size.y - 1), home.position + home.size - Vector2i.ONE]
	var far_most := true
	for corner: Vector2i in corners:
		if World.is_walkable(corner) and (corner - square.get_center()).length_squared() > (bed - square.get_center()).length_squared():
			far_most = false
	_check(far_most, "the walkable corner farthest from the square")
	var head := Resident.head_of(home, bed)
	_check((home.size.x >= home.size.y and head.y == 0 and head.x != 0) or (home.size.x < home.size.y and head.x == 0 and head.y != 0), "the head along the room's long side (%s)" % [head])
	# Night: she goes to bed and lies down.
	DayNight.set_hour(23.0)
	_check(Resident.asleep_now(), "23:00: the sleep hours")
	for i in 400:
		World.step()
		if mara.activity == "sleep":
			break
	for i in 6:
		World.step()
	_check(mara.doing == Resident.Doing.HOME and mara.tile == bed and mara.activity == "sleep" and mara.facing == head, "at home at night she lies on the bed, head to the wall (%s at %s, %s)" % [mara.activity, mara.tile, mara.facing])
	var awake: Dictionary = _main._awake_map()
	var code := ""
	for building: Dictionary in _main._world_map.areas.get(World.zone.name, {}).get("buildings", []):
		if building.get("rect") is Rect2i and (building["rect"] as Rect2i).has_point(bed):
			code = str(building.get("code", ""))
	_check(code.is_empty() or (awake.has(code) and awake[code] == false), "the lamp: her house is asleep (%s: %s)" % [code, awake])
	DayNight.set_hour(8.0)
	for i in Resident.FAR_EVERY + 2:
		World.step()
	_check(mara.activity != "sleep", "morning: up")
	# The woodcutter's trip, end to end: a woodlot by the store, economy's trip stood in for, Main's tick sets her task.
	DayNight.set_hour(10.0)
	World.step()
	_check(mara.doing == Resident.Doing.WORK, "(10:00: at work)")
	var store: Dictionary = World.holdings.place(STORE)
	var lot := STORE.get_slice("/", 0) + "/soak_woodlot"
	var centre: Vector2i = _main._nearest_free(store.get("cell", Vector2i.ZERO) + Vector2i(0, 6))
	World.holdings._places[lot] = {"id": lot, "area": store["area"], "key": "soak_woodlot", "cell": centre, "name": "the test woodlot", "kind": "woodlot", "radius": 3, "worth": 1, "start": "town", "town": STORE}
	World.holdings._holder[lot] = "town"
	World.holdings._strength[lot] = 1
	World.holdings._since[lot] = World.steps
	World.production.retrain("rs-mara", "woodcutter")  # The worker's trade, which the body follows on the sync (566 amended, part 3).
	_sync()
	_check(mara.trade == "woodcutter", "retrained, her body follows the trade (%s)" % mara.trade)
	var site: Dictionary = World.production.site_of(STORE, "woodcutter")
	_check(not site.is_empty() and site.get("id") == lot, "(economy's site_of finds the woodlot)")
	var spot: Dictionary = _main._site_spot(site, STORE)
	_check(World.is_walkable(spot["cell"]) and absi(centre.x - spot["cell"].x) <= 3 and absi(centre.y - spot["cell"].y) <= 3
		and (spot["face"] == Resident.NO_CELL or not World.is_walkable(spot["face"])),
		"the woodlot's spot: a walkable cell within its radius with something that cannot be walked beside it (%s)" % [spot])
	var now := World.production.now()
	_main._trip_stub["rs-mara"] = {"site": lot, "from": now, "back_at": now + 40000}
	_put(_player(), _main._nearest_free(centre + Vector2i(2, 2)))
	var task: Dictionary = _main._task_for(mara)
	_check(task.get("kind") == "chop" and task.get("cell") == spot["cell"] and not bool(task.get("walking", true)), "outbound: the task is to chop at the spot (%s)" % [task])
	for i in 600:
		World.step()
		if mara.tile == spot["cell"]:
			break
	for i in Resident.FAR_EVERY + 2:
		World.step()
	var want_face: Vector2i = mara.facing if spot["face"] == Resident.NO_CELL else mara._toward(spot["face"])
	_check(mara.tile == spot["cell"] and mara.activity == "chop" and mara.facing == want_face,
		"she walks to the spot and chops there, facing the tree (%s at %s, %s; spot %s, goal %s, doing %s)" % [mara.activity, mara.tile, mara.facing, spot, mara._goal, mara.doing])
	_main._trip_stub["rs-mara"] = {"site": lot, "from": now - 40000, "back_at": now + 5}
	task = _main._task_for(mara)
	_check(task.get("kind") == "carry_log" and bool(task.get("walking", false)) and World.distance(task.get("cell", Vector2i.ZERO), store["cell"]) <= 2, "the return half: a log carried to the store (%s)" % [task])
	for i in Main.WORK_CHECK_TICKS + Resident.FAR_EVERY + 2:
		World.step()
	_check(mara.activity == "carry_log", "shown on the way home (%s at %s)" % [mara.activity, mara.tile])
	# The work props (566 amended): a chopping block in the woodlot and a woodpile by the store, stood as doorless solid buildings.
	var block: Vector2i = _main._nearest_free(centre + Vector2i(-1, 2))
	var pile: Vector2i = _main._nearest_free(store["cell"] + Vector2i(3, 0))
	_stand_prop(Main.CHOPPING_BLOCK, block)
	_stand_prop(Main.WOODPILE, pile)
	_main._site_spots.clear()
	_main._trip_stub["rs-mara"] = {"site": lot, "from": now, "back_at": now + 40000}
	spot = _main._site_spot(site, STORE)
	_check(spot["face"] == block and World.distance(spot["cell"], block) == 1 and World.is_walkable(spot["cell"]),
		"with a chopping block in the woodlot the spot is beside it, facing it (%s, block %s)" % [spot, block])
	var nearer := true
	for side: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if World.is_walkable(block + side) and (block + side - store["cell"]).length_squared() < (spot["cell"] - store["cell"]).length_squared():
			nearer = false
	_check(nearer, "the block's neighbour nearest the store")
	for i in 600:
		World.step()
		if mara.tile == spot["cell"]:
			break
	for i in Resident.FAR_EVERY + 2:
		World.step()
	_check(mara.tile == spot["cell"] and mara.activity == "chop" and mara.facing == mara._toward(block),
		"she chops facing the block (%s at %s, %s)" % [mara.activity, mara.tile, mara.facing])
	# The turn by the walk home (521 amended): at the block while back_at leaves time to walk home, carrying once it does not.
	var walk_home: int = _main._walk_home(mara, spot["cell"], store["cell"])
	now = World.production.now()  # The clock has run on since the trip began.
	_check(walk_home >= World.distance(spot["cell"], store["cell"]) * 3, "the walk home is the route at her pace at least (%d steps)" % walk_home)
	_main._trip_stub["rs-mara"] = {"site": lot, "from": now - 40000, "back_at": now + walk_home + 40}
	_check(_main._task_for(mara).get("kind") == "chop", "forty steps more than the walk home: still chopping")
	_main._trip_stub["rs-mara"] = {"site": lot, "from": now - 40000, "back_at": now + walk_home - 1}
	_check(_main._task_for(mara).get("kind") == "carry_log", "one step short of it: she sets off home with the log")
	_main._trip_stub["rs-mara"] = {"site": lot, "from": now - 40000, "back_at": now + 5}
	task = _main._task_for(mara)
	_check(task.get("kind") == "carry_log" and task.get("face") == pile and World.distance(task.get("cell", Vector2i.ZERO), pile) == 1 and World.is_walkable(task.get("cell", pile)),
		"with a woodpile by the store the log is carried to its side (%s, pile %s)" % [task, pile])
	for i in 600:
		World.step()
		if mara.tile == task["cell"]:
			break
	for i in Resident.FAR_EVERY + 2:
		World.step()
	_check(mara.tile == task["cell"] and mara.activity == "carry_log" and mara.facing == mara._toward(pile),
		"at the pile, facing it, the log still on her shoulder (%s at %s, %s)" % [mara.activity, mara.tile, mara.facing])
	_unstand_prop(block)
	_unstand_prop(pile)
	_main._site_spots.clear()
	_main._trip_stub["rs-mara"] = {}
	for i in Main.WORK_CHECK_TICKS + Resident.FAR_EVERY + 2:
		World.step()
	_check(_main._task_for(mara).is_empty() and mara.activity.is_empty(), "off the trip: nothing shown (%s)" % mara.activity)
	_main._trip_stub.erase("rs-mara")
	World.holdings._places.erase(lot)
	World.holdings._holder.erase(lot)
	World.holdings._strength.erase(lot)
	World.holdings._since.erase(lot)
	_main._site_spots.clear()
	World.production.retrain("rs-mara", "cook")
	_sync()
	# The carpenter's cells by progress.
	var rect := Rect2i(mara.tile + Vector2i(6, 6), Vector2i(4, 3))
	var slot_house := {"rect": rect, "facing": Vector2i(0, 1), "slot": "building.house"}
	var saw: Dictionary = _main._build_task(slot_house, 0.05)
	var hammer: Dictionary = _main._build_task(slot_house, 0.5)
	var front := Level.front_cell(rect, Vector2i(0, 1))
	_check(saw.get("kind") == "saw" and not rect.has_point(saw.get("cell", rect.position)) and World.distance(saw.get("cell", front), front) <= 1, "a slot building, no door record: the pad stage saws just outside the front cell (%s, front %s)" % [saw, front])
	_check(hammer.get("kind") == "hammer" and hammer.get("face") == rect.get_center(), "walls up: hammering, facing the building's middle (%s)" % [hammer])
	# A composed kind with a door (buildings' Level.site_cells, fd167d4b): the saw cell faces the sawbuck, the work cell is inside the door.
	var kind_house := {"rect": rect, "blocks": [rect], "facing": Vector2i(0, 1), "kind": "house", "seed": 2, "doors": [Vector3i(front.x, front.y - 1, Terrain.SOUTH)]}  # The edge between the cell inside the door and the front cell outside it.
	var cells: Dictionary = Level.site_cells(kind_house)
	saw = _main._build_task(kind_house, 0.05)
	hammer = _main._build_task(kind_house, 0.5)
	_check(saw.get("kind") == "saw" and saw.get("cell") == cells["saw"] and saw.get("face") == cells["sawbuck"] and not rect.has_point(cells["saw"]) and World.distance(cells["saw"], cells["sawbuck"]) == 1,
		"a kind with a door: sawing on buildings' saw cell facing the sawbuck (%s, cells %s)" % [saw, cells])
	_check(hammer.get("kind") == "hammer" and hammer.get("cell") == cells["work"] and rect.has_point(cells["work"]) and hammer.get("face") == rect.get_center(), "walls up: hammering on the work cell inside the door (%s)" % [hammer])
	_main._build_stub["rs-mara"] = {"use": "no_such_use", "progress": 0.5}
	_check(_main._task_for(mara).is_empty(), "a build with no map building here: nothing to stand at")
	_main._build_stub.erase("rs-mara")
	mara.task = {}
	World.despawn(mara)


## A work prop (566 amended) of [param slot] stood at [param cell] in the
## zone, as Level lays a doorless solid building: its record on the world
## map's buildings, its cell out of the floor.
func _stand_prop(slot: String, cell: Vector2i) -> void:
	var buildings: Array = _main._world_map.areas.get(World.zone.name, {}).get("buildings", [])
	buildings.append({"slot": slot, "cell": cell, "facing": Vector2i(0, 1), "rect": Rect2i(cell, Vector2i.ONE), "blocks": [], "use": "", "town": "", "code": ""})
	World._floor.erase(cell)


## The prop stood at [param cell] by _stand_prop taken away again.
func _unstand_prop(cell: Vector2i) -> void:
	var buildings: Array = _main._world_map.areas.get(World.zone.name, {}).get("buildings", [])
	for i in range(buildings.size() - 1, -1, -1):
		if buildings[i].get("rect") == Rect2i(cell, Vector2i.ONE) and str(buildings[i].get("code", "-")).is_empty():
			buildings.remove_at(i)
	World._floor[cell] = true


## A free cell of [param area] (not [param from]) a path from [param from]
## reaches, the farthest such; [param from] when none.
func _reachable_from(from: Vector2i, area: Rect2i) -> Vector2i:
	var best := from
	var best_d := 0
	for y in area.size.y:
		for x in area.size.x:
			var cell := area.position + Vector2i(x, y)
			if cell == from or not World.is_walkable(cell) or not World.is_free(cell):
				continue
			var d := World.distance(from, cell)
			if d > best_d and not World.find_path(from, cell, false).is_empty():
				best = cell
				best_d = d
	return best
