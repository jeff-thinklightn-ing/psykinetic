extends Node
## A repair is worked at the building, and the Ledger says it is in hand (566 amended (9); the coordinator's ruling,
## 11-15, after ui-design's look at a damaged kitchen: the carpenter stood at the temple the whole repair, the
## Ledger and the walls showed nothing of it). Main._build_of matched a repair's recipe, "repair:kitchen", against a
## building's use and found none, so the carpenter had no task. On the laid world, Umbrage's kitchen damaged:
## its repair ordered and taken up; the carpenter hammers on a cell beside it, outside it, never in its door, facing
## its wall; at 0.4 the "town" message the views are told (Net.broadcast, handled here as a joined client handles
## it) carries the progress, the Ledger reads "Damaged: the kitchen, being mended." and the composer stands it in
## scaffold. With no free cell beside a building she works from her bench. A building in disrepair: the Ledger's own
## group, its mend never read as a new build, in scaffold; a ruin its group. A pasture in disrepair still brings its
## shepherd (the trade first, the walls after).

const TOWN := "wilds/store"
const MINUTE := 37

var _main: Node
var _failed := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17998)
	Net.companions = false
	Net.map_name = "wilds"
	Net.lawspeaker = "off"
	Net.state_path = ports.scratch_path("repair_site_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	DayNight.set_hour(10.0)
	print("== a repair worked at the building; the Ledger says it is in hand (566 amended (9)) ==")
	World.stockpile.deposit(TOWN, "wood", 60, "test")
	_check(World.towns.damage(TOWN, "kitchen"), "(Umbrage's kitchen damaged)")
	var kitchen := _map_building("kitchen")
	_check(not kitchen.is_empty(), "(the kitchen on the map: %s)" % [kitchen.get("rect", "none")])
	var job := 0
	var told_at := {}  # building kind -> the last step the views were told it (566 amended (11)).
	World.towns.building_changed.connect(func(town: String, kind: String) -> void:
		if town == TOWN:
			told_at[kind] = World.steps)
	for s in 6000:
		World.step()
		job = int(World.towns.building(TOWN, "kitchen").get("job", 0))
		if job != 0 and str(World.production.job(job).get("state", "")) == "working":
			break
	_check(job != 0 and str(World.production.job(job).get("recipe", "")) == Towns.REPAIR + "kitchen", "its repair ordered and taken up (job %d)" % job)
	_test_told_same_tick(job, told_at)
	var carpenter := _carpenter()
	_check(carpenter != null, "(the carpenter's body in the wilds)")
	if carpenter == null or kitchen.is_empty():
		_end()
		return
	DayNight.set_hour(8.0)  # Her work hours (residents.json carpenter: 7 to 12 at work, on her own clock).
	var build: Dictionary = _main._build_of(carpenter)
	_check(bool(build.get("repair", false)) and str((build.get("building", {}) as Dictionary).get("use", "")) == "kitchen",
		"her build is the kitchen's repair (was {}: the recipe matched against its use) (%s)" % [build.get("building", {}).get("use", "none")])
	var task: Dictionary = _main._repair_task(carpenter, kitchen)
	var rect: Rect2i = kitchen["rect"]
	var at: Vector2i = task.get("cell", World.NO_CELL)
	_check(str(task.get("kind", "")) == "hammer" and not rect.has_point(at) and _beside(rect, at) and not Main.door_cells(kitchen).has(at)
		and not World.is_link_cell(at) and rect.has_point(task.get("face", World.NO_CELL)),
		"her task: hammering at %s, beside the kitchen %s, outside it, not in its door, facing its wall %s" % [at, rect, task.get("face")])
	# Walked there, she works there; the progress to 0.4.
	var stood := 0
	var progress := -1.0
	for s in 6000:
		World.step()
		progress = World.towns.build_progress(TOWN, "kitchen")
		if _beside(rect, carpenter.tile) and not rect.has_point(carpenter.tile):
			stood += 1
		if progress >= 0.4:
			break
	_check(progress >= 0.4 and stood > 0 and _beside(rect, carpenter.tile),
		"at %.2f she is at the kitchen, beside it (%s), for %d of the ticks; never at the temple" % [progress, carpenter.tile, stood])
	var told: Dictionary = (_main.town_states.get(TOWN, {}) as Dictionary).get("kitchen", {})
	# Told as it starts and at each stage it crosses, on the town's turn (Towns._stages): the views' figure trails.
	_check(float(told.get("progress", -1.0)) >= 0.0 and str(told.get("state", "")) == Towns.DAMAGED,
		"the views were told its progress with the \"town\" message (%s)" % [told])
	var words := TownSheet.buildings_words(_main.town_states.get(TOWN, {}))
	_check(words.contains("Damaged: the kitchen, being mended."), "the Ledger: \"%s\"" % words)
	_check(BuildingComposer.scaffolded(told) and BuildingComposer.stage(told) == BuildingComposer.STANDING, "the composer: standing, in scaffold")
	# No free cell beside a building: her bench, as before.
	var shut := _shut_cell()
	_check(shut != World.NO_CELL and _main._repair_task(carpenter, {"rect": Rect2i(shut, Vector2i.ONE), "facing": Vector2i(0, 1)}).is_empty(),
		"no free cell beside a building (%s): no repair task, her bench" % shut)
	# The Ledger's groups for disrepair and ruins (voice's words, 11-15).
	var houses := {"forge": {"state": Towns.STANDING}, "pasture": {"state": Towns.DISREPAIR}, "inn": {"state": Towns.RUIN}, "well": {"state": Towns.PLANNED}}
	_check(TownSheet.buildings_words(houses) == "Standing: the forge. In disrepair: the pasture. In ruins: the inn. Planned: the well.",
		"disrepair and ruins named: \"%s\"" % TownSheet.buildings_words(houses))
	houses["pasture"]["progress"] = 0.4
	_check(TownSheet.buildings_words(houses).contains("In disrepair: the pasture, being mended.") and not TownSheet.buildings_words(houses).contains("Building:")
		and BuildingComposer.scaffolded(houses["pasture"]), "a disrepair's mend: \"being mended\", never a build, in scaffold (\"%s\")" % TownSheet.buildings_words(houses))
	# A pasture in disrepair still brings its shepherd.
	var record: Dictionary = World.towns._town(TOWN)
	var had: Variant = record["buildings"].get("pasture")
	record["buildings"]["pasture"] = {"kind": "pasture", "level": 1, "state": Towns.DISREPAIR, "since": 0, "job": 0}
	record.erase("shepherd_wanted")
	World.towns._shepherd_comes(TOWN)
	var since := int(record.get("shepherd_wanted", -1))
	_check(since >= 0, "a pasture in disrepair with no shepherd: one wanted (since %d)" % since)
	# flock.growth_days on: a one-minute day for the call (a back-dated mark under 0 reads as none), then the day back.
	var minutes := float(DayNight.day_steps) / 600.0
	DayNight.set_day_minutes(1.0)
	record["shepherd_wanted"] = 0
	World.towns._shepherd_comes(TOWN)
	DayNight.set_day_minutes(minutes)
	var sought := World.towns.sought(TOWN).any(func(entry: Dictionary) -> bool: return str(entry["trade"]) == "shepherd")
	_check(World.towns.has_resident(TOWN, "shepherd") or sought, "and after flock.growth_days one comes (or is sought, Towns._arrive), the pasture still in disrepair (resident %s, sought %s)" % [World.towns.has_resident(TOWN, "shepherd"), sought])
	record["buildings"]["pasture"]["state"] = Towns.RUIN
	record["buildings"]["pasture"]["level"] = 0
	_check(not World.towns._kept_for_trade(TOWN, "pasture"), "a ruin: none wanted")
	if had == null:
		record["buildings"].erase("pasture")
	else:
		record["buildings"]["pasture"] = had
	_end()


## 566 amended (11): the step its repair is taken up the views are told it (Towns.tell_stages after
## production.tick), not the towns' next turn; the second call only tells (the town's records, its jobs and
## its stage the same, bar _stages' own note of the stage told, which the towns' next turn writes the same)
## and, nothing crossed since, sends nothing.
func _test_told_same_tick(job: int, told_at: Dictionary) -> void:
	var started := int(World.production.job(job).get("last", -1))
	_check(int(told_at.get("kitchen", -1)) == World.steps and World.towns.build_progress(TOWN, "kitchen") >= 0.0,
		"told the step it was taken up (step %d, told %d, its job's start %d), not 30 s on" % [World.steps, int(told_at.get("kitchen", -1)), started])
	var towns_before := World.towns.to_dict()
	var work_before: Dictionary = World.production.to_dict()
	var stage_before := World.towns.stage(TOWN)
	told_at.clear()
	World.towns.tell_stages()
	_check(told_at.is_empty() and World.towns.to_dict() == towns_before and World.production.to_dict() == work_before
		and World.towns.stage(TOWN) == stage_before, "again, nothing crossed since: nothing sent, nothing changed (told %s)" % [told_at])
	var house: Dictionary = World.towns._town(TOWN)["buildings"]["kitchen"]
	var noted := int(house.get("stage", -1))
	house.erase("stage")  # As before the call: the towns' last turn had not seen her at work.
	var unnoted := World.towns.to_dict()
	World.towns.tell_stages()
	var after := World.towns.to_dict()
	after[TOWN]["buildings"]["kitchen"].erase("stage")
	_check(after == unnoted and int(house.get("stage", -1)) == noted and told_at.has("kitchen") and World.production.to_dict() == work_before,
		"its only write is its note of the stage told (%d, as the towns' turn writes it); jobs and records the same" % noted)


func _end() -> void:
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	Net.state_path = ""
	get_tree().quit(0 if _failed == 0 else 1)


func _map_building(use: String) -> Dictionary:
	for building: Dictionary in _main._world_map.areas.get("wilds", {}).get("buildings", []):
		if str(building.get("town", "")) == "store" and str(building.get("use", "")) == use and building.get("rect") is Rect2i:
			return building
	return {}


func _carpenter() -> Resident:
	for entity in World.get_entities():
		if entity is Resident and entity.spawned and (entity as Resident).trade == "carpenter" and (entity as Resident).town == TOWN:
			return entity
	return null


## Whether [param cell] is in the ring about [param rect] (outside it, touching it).
func _beside(rect: Rect2i, cell: Vector2i) -> bool:
	return not rect.has_point(cell) and rect.grow(1).has_point(cell)


## A cell of the wilds with no free cell about it (a wall's or a thicket's middle).
func _shut_cell() -> Vector2i:
	for y in range(5, 300):
		for x in range(5, 300):
			var at := Vector2i(x, y)
			var open := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if (dx != 0 or dy != 0) and World.is_free(at + Vector2i(dx, dy)):
						open = true
			if not open:
				return at
	return World.NO_CELL


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failed += 1
