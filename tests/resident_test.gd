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

	_test_stays_when_told()
	_test_stays_when_left()
	_test_goes_when_not_told()
	_test_legacy_rests_in_town()
	_test_taken_by_raiders()
	_test_bodies_in_town()
	_test_resident_voices()
	_test_means_in_voice()
	_test_hearsay()
	_test_bodies_only_near()  # Last: its resident would answer the voice tests.

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


## rs_town: a room of stone (30 x 20 rows of the layout) in a wall, the start
## at (2, 2), the store (a stockpile the town holds) at (5, 3), radius 2, a
## hut at (9, 5) (no walls of its own: its inside, (9, 5) to (11, 7), is a
## home). rs_road: a bare room.
func _register_levels() -> void:
	for level_name: String in [TOWN, ROAD]:
		var rows: Array[String] = []
		for y in 20:
			rows.append("#".repeat(30) if y == 0 or y == 19 else "#" + ".".repeat(28) + "#")
		var spec := {"name": level_name, "centre": [7, 4], "starts": [[2, 2]], "entities": []}
		if level_name == TOWN:
			spec["places"] = {"store": {"at": [5, 3], "kind": "stockpile", "radius": 2, "holder": "town", "name": "the stockpile"}}
			# A home for residents' bodies (decision 333): a hut linked to nothing.
			spec["buildings"] = [{"slot": "building.hut", "at": [9, 5]}]
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
	_check(bram != null and bram.label == "Bram [smith]" and bram.town == STORE and bram.trade == "smith",
		"a body for him, named \"Name [profession]\" over his head (%s)" % [bram.label if bram != null else "none"])
	_check(Resident.label_of("Odo", "medicine_man") == "Odo [medicine man]" and Resident.label_of("Wren", "") == "Wren",
		"a trade id's underscores spaced in the label, a bare name for no trade")
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
	_step_until(func() -> bool: return bram.doing == Resident.Doing.SQUARE and square.has_point(bram.tile), 150)
	_check(bram.doing == Resident.Doing.SQUARE and square.has_point(bram.tile), "evening, between work and home: the square (at %s)" % bram.tile)
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
	_check(mind.claims_asks.size() == 1 and "Player told you that the mine is cursed" in said_to,
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
	_check(mind.claims_asks.size() == 2 and "the mine is cursed" not in str(mara.voice_ask("Player", "What news?", 2)["system"]).to_lower(),
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
	_check(World.townsfolk().is_empty(), "everyone 20 and more cells off the store: no bodies (%d)" % World.townsfolk().size())
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
