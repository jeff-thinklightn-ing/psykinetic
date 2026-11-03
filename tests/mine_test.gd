extends Node
## Ore seams (decision 769; Jeff: "a mixture of clearing mobs, and
## mining"): a seam stands in a recess; a pick's blows wear it a hp each and
## give a sack of ore at the miner's feet per max_hp blows; a sword or a bare
## hand rings off it; spent it is rubble that rings too, kept so through a
## save, and full again refill_days game days on. A small room, World stepped
## by hand, as combat_test.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const PLAYER := {"script": "res://sim/player.gd", "shape": "capsule"}

var _failures := 0
var _room: Node2D


func _ready() -> void:
	World.set_process(false)

	_test_level_marker()
	_test_recess()
	_test_rings_without_a_tool()
	_test_mined()
	_test_kept_and_refilled()
	_test_mine_look()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_level_marker() -> void:
	print("\n== a level's seam marker is a Seam, its props from level.json ==")
	var spec: Dictionary = Level._spec_for("seam", {})
	_check(spec.get("script") == Level.SEAM_SCRIPT and Level._spawns("seam") and "seam" in Level.MARKERS,
			"the \"seam\" marker spawns a res://sim/seam.gd (%s)" % spec.get("script"))
	var seam := EntityFactory.build({"script": Level.SEAM_SCRIPT, "props": {"full_sacks": 4, "max_hp": 5, "refill_days": 2.0}}) as Seam
	_check(seam != null and seam.sacks == 4 and seam.full_sacks == 4 and seam.max_hp == 5 and is_equal_approx(seam.refill_days, 2.0),
			"full_sacks 4 fills it with 4, max_hp 5 blows a sack, refill_days 2 (%s)" % [[seam.sacks, seam.max_hp, seam.refill_days] if seam else []])
	seam.free()
	seam = EntityFactory.build({"script": Level.SEAM_SCRIPT, "props": {"full_sacks": 4, "sacks": 1, "spent_at": -1}}) as Seam
	_check(seam.sacks == 1 and not seam.spent, "a save's sacks after its full_sacks: 1 left of 4")
	seam.free()


func _test_recess() -> void:
	print("\n== a seam stands in a recess: one side open of four ==")
	var e := _build(["#####", "##s##", "#.P.#", "#.s.#", "#####"])
	var seams: Array = e["s"]
	_check(World.in_recess(seams[0].tile), "walled on three sides at %s: a recess" % seams[0].tile)
	_check(not World.in_recess(seams[1].tile), "out in the room at %s: not one" % seams[1].tile)


func _test_rings_without_a_tool() -> void:
	print("\n== a sword, a bare hand: the blow rings off ==")
	var e := _build(["#####", "##s##", "#.P.#", "#####"])
	var player: GridEntity = e["P"][0]
	var seam: Seam = e["s"][0]
	_check(seam.hp == Seam.BLOWS and seam.sacks == Seam.SACKS and not seam.spent and not seam.pushable and not seam.is_breakable() and not seam.is_creature(),
			"whole: %d hp, %d sacks, not pushed, broken or fought as a body" % [seam.hp, seam.sacks])
	var rang := {"n": 0}
	var on_rang := func(_seam: Seam, _by: GridEntity) -> void: rang["n"] += 1
	World.seam_rang.connect(on_rang)
	_blow(player, seam)
	_check(seam.hp == Seam.BLOWS and rang["n"] == 1, "a bare hand: no wear, it rings (%d hp, rang %d)" % [seam.hp, rang["n"]])
	_give(player, "sword")
	_blow(player, seam)
	_check(seam.hp == Seam.BLOWS and rang["n"] == 2, "a sword: no wear, it rings (%d hp, rang %d)" % [seam.hp, rang["n"]])
	World.seam_rang.disconnect(on_rang)


func _test_mined() -> void:
	print("\n== a pick: a hp a blow, a sack at the miner's feet each BLOWS ==")
	var e := _build(["#####", "##s##", "#.P.#", "#####"])
	var player: GridEntity = e["P"][0]
	var seam: Seam = e["s"][0]
	_give(player, "pick")
	_check(Seam.bites("pick") and not Seam.bites("sword") and not Seam.bites(""), "the pick bites (a tool), the sword and no item not")
	_blow(player, seam)
	_check(seam.hp == Seam.BLOWS - 1 and World.ground_at(player.tile).is_empty(), "one blow: %d hp, nothing yet" % seam.hp)
	for i in Seam.BLOWS - 1:
		_blow(player, seam)
	var ground := World.ground_at(player.tile)
	_check(Array(ground) == [Seam.ORE], "the sack falls at the miner's feet %s (%s)" % [player.tile, ground])
	_check(seam.sacks == Seam.SACKS - 1 and seam.hp == Seam.BLOWS and not seam.spent, "whole again, a sack fewer (%d left, %d hp)" % [seam.sacks, seam.hp])
	for i in Seam.BLOWS * (Seam.SACKS - 1):
		_blow(player, seam)
	_check(seam.spent and seam.sacks == 0 and seam.spent_at == World.steps, "spent after %d sacks, spent_at the steps now" % Seam.SACKS)
	_check(seam.label == Seam.SPENT_LABEL, "named \"%s\" (%s)" % [Seam.SPENT_LABEL, seam.label])
	_check(World.ground_uids(player.tile).size() == Seam.SACKS, "%d sacks lie there (%d)" % [Seam.SACKS, World.ground_uids(player.tile).size()])
	var rang := {"n": 0}
	var on_rang := func(_seam: Seam, _by: GridEntity) -> void: rang["n"] += 1
	World.seam_rang.connect(on_rang)
	_blow(player, seam)
	World.seam_rang.disconnect(on_rang)
	_check(rang["n"] == 1 and World.ground_uids(player.tile).size() == Seam.SACKS, "rubble: the pick rings off it, nothing more")
	_check(seam.spawned and World.get_entity_at(seam.tile) == seam, "the rubble still holds its cell")


func _test_kept_and_refilled() -> void:
	print("\n== spent through a save, full again refill_days on ==")
	var e := _build(["#####", "##s##", "#.P.#", "#####"])
	var player: GridEntity = e["P"][0]
	var seam: Seam = e["s"][0]
	_give(player, "pick")
	World.steps = 1000
	for i in Seam.BLOWS * Seam.SACKS:
		_blow(player, seam)
	var entries: Array[GridEntity] = [seam]
	var entry: Dictionary = Snapshot._entries(entries)[0]
	var back := EntityFactory.build({"script": entry["script"], "props": JSON.to_native(entry["props"])}) as Seam
	_check(back.spent and back.sacks == 0 and back.spent_at == 1000, "the saved entry builds it spent at 1000 (%s)" % entry["props"])
	back.free()
	var day := DayNight.day_steps
	World.steps = 1000 + roundi(Seam.REFILL_DAYS * day) - 1
	_check(World.refill_seams() == 0 and seam.spent, "a step short of %s game days: still rubble" % Seam.REFILL_DAYS)
	World.steps += 1
	_check(World.refill_seams() == 1 and not seam.spent and seam.sacks == Seam.SACKS and seam.hp == Seam.BLOWS and seam.spent_at == -1,
			"then full: %d sacks, %d hp" % [seam.sacks, seam.hp])
	_check(seam.label == Seam.LABEL, "named \"%s\" again (%s)" % [Seam.LABEL, seam.label])
	_check(int(seam.spawn_spec["props"]["sacks"]) == Seam.SACKS and int(seam.spawn_spec["props"]["spent_at"]) == -1, "and kept so for the next save")
	World.steps = 0


func _test_mine_look() -> void:
	print("
== mine_look (769's look test) parses, its seams in recesses, its decor all placed ==")
	var level := Level.load_level("mine_look")
	_check(level.get("warnings", ["no level"]).is_empty(), "no warnings (%s)" % [level.get("warnings")])
	World.reset()
	World.load_terrain(level["terrain"])
	var seams := 0
	var recessed := 0
	for spec: Dictionary in level["entities"]:
		if spec.get("script") == Level.SEAM_SCRIPT:
			seams += 1
			recessed += 1 if World.in_recess(spec["tile"]) else 0
	_check(seams >= 6 and recessed == seams, "%d seams, %d in a recess" % [seams, recessed])
	var kinds := {}
	for piece: Dictionary in level["terrain"].get("decor", []):
		kinds[piece["kind"]] = int(kinds.get(piece["kind"], 0)) + 1
	_check(kinds.has("mine_arch") and kinds.has("mine_beam") and kinds.has("mine_track") and kinds.has("mine_lamp"), "arches, beams, track and lamps placed (%s)" % [kinds])
	var widths := {}
	for piece: Dictionary in level["terrain"].get("decor", []):
		if piece["kind"] == "mine_arch":
			widths[int(piece["width"])] = true
			_check(Client3D.decor_slot(piece) == "mine.arch_%d" % piece["width"], "an arch at %s is mine.arch_%d" % [piece["cell"], piece["width"]])
	_check(Client3D.decor_slot({"kind": "mine_track", "variant": 3}) == "mine.track_end" and Client3D.decor_slot({"kind": "mine_beam", "width": 8}) == "mine.beam_8"
			and Client3D.decor_slot({"kind": "moss_strip", "variant": 2}) == "prop.moss_strip", "the slot table: track end, beam, and prop.<kind> as before")
	_check(Level.template_config("mine_look").get("mass") == "rock", "\"mass\": \"rock\" (terrain's rock mass)")


## A room of [param rows]: "#" wall, "." floor, "P" a player, "s" a seam.
func _build(rows: Array[String]) -> Dictionary:
	World.reset()
	World.load_combat_rules(FileAccess.get_file_as_string(World.COMBAT_RULES))
	if _room != null:
		_room.free()
	_room = Node2D.new()
	add_child(_room)
	var cell_rows: Array[String] = []
	var spawns: Array[Array] = []
	for y in rows.size():
		var cells := ""
		for x in rows[y].length():
			var symbol := rows[y][x]
			cells += symbol if symbol in ["#", "."] else "."
			if symbol not in ["#", "."]:
				spawns.append([symbol, Vector2i(x, y)])
		cell_rows.append(cells)
	World.load_terrain(Terrain.parse(Terrain.expand(cell_rows)))
	var out := {"P": [], "s": []}
	for spawn in spawns:
		var spec: Dictionary = PLAYER.duplicate(true) if spawn[0] == "P" else Level._spec_for("seam", {})
		spec["name"] = "%s%d" % ["Player" if spawn[0] == "P" else "Seam", out[spawn[0]].size() + 1]
		spec["tile"] = spawn[1]
		var entity := EntityFactory.build(spec)
		_room.add_child(entity)
		World.spawn(entity, spawn[1])
		out[spawn[0]].append(entity)
	return out


func _give(entity: GridEntity, id: String) -> void:
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		if not entity.slots[slot].is_empty():
			World.items.end(World.take_item(entity, entity, slot), "gone")
	World.put_item(entity, entity, Player.RIGHT_HAND, World.items.mint(id, "built"))


## A blow struck now and resolved.
func _blow(attacker: GridEntity, target: GridEntity) -> void:
	attacker.next_attack_tick = 0
	attacker.next_move_tick = 0
	attacker.stamina = attacker.max_stamina
	World.try_attack(attacker, target)
	World._resolve_hits()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
