extends Node
## The sound slots (SoundKit, art/audio/slots.json): the manifest is whole,
## every positional slot is heard as far as its sim noise carries (or says
## monsters do not hear it), every slot plays its takes, its fill, its
## fallback's or a placeholder, and Sfx plays slots with a different take
## each repeat. Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL
## per assertion and quits with exit code 1 if any assertion failed, 0
## otherwise.

const GROUPS := ["sfx", "amb", "voice", "ui", "music"]

var _failures := 0


func _ready() -> void:
	_test_manifest()
	_test_sources()
	_test_noises_are_the_sims()
	_test_fallbacks()
	_test_placeholder()
	_test_takes()
	_test_folders()
	_test_sfx_plays_slots()
	_test_status_current()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_manifest() -> void:
	print("\n== the manifest: every slot has a group, category, type, bus and use; a positional one how far it is heard ==")
	var slots := SoundKit.slots()
	_check(slots.size() >= 80, "slots.json has slots (%d)" % slots.size())
	for slot: String in slots:
		var entry: Dictionary = slots[slot]
		var problems: Array[String] = []
		if slot.get_slice(".", 0) not in GROUPS or slot.get_slice(".", 1) == "":
			problems.append("a name is <%s>.<name>" % "|".join(GROUPS))
		if str(entry.get("category", "")) == "":
			problems.append("no category")
		if str(entry.get("type", "")) not in SoundKit.TYPES:
			problems.append("type %s, not one of %s" % [entry.get("type"), SoundKit.TYPES])
		if str(entry.get("bus", "")) not in SoundKit.BUSES:
			problems.append("bus %s, not one of %s" % [entry.get("bus"), SoundKit.BUSES])
		if str(entry.get("uses", "")) == "":
			problems.append("no uses")
		if SoundKit.positional(slot):
			if not entry.has("noise"):
				problems.append("positional, but no noise (a sim kind, or null with a range)")
			elif entry["noise"] == null and int(entry.get("range", 0)) <= 0:
				problems.append("not heard by monsters, but no range")
			elif entry["noise"] != null and not SoundKit.NOISES.has(str(entry["noise"])):
				problems.append("noise %s is no sim noise kind (%s)" % [entry["noise"], SoundKit.NOISES.keys()])
		elif entry.has("noise") or entry.has("range"):
			problems.append("flat (positional false), but has a noise or range")
		if entry.get("type") == "bed" and SoundKit.positional(slot):
			problems.append("a bed is flat (positional false)")
		if entry.get("bus") == "ui" and SoundKit.positional(slot):
			problems.append("a ui sound is flat (positional false)")
		_check(problems.is_empty(), "%s %s" % [slot, problems if not problems.is_empty() else ""])


func _test_sources() -> void:
	print("\n== every fill names a source, every source its licence, every fill file is there ==")
	var sources: Dictionary = SoundKit.manifest().get("sources", {})
	for name: String in sources:
		var source: Dictionary = sources[name]
		_check(str(source.get("license", "")) != "" and FileAccess.file_exists("res://" + str(source.get("license_file", ""))) and str(source.get("url", "")) != "",
				"%s: a licence, its text in the repo, a url" % name)
	for slot: String in SoundKit.slots():
		var fill: Dictionary = SoundKit.spec(slot).get("fill", {})
		if fill.is_empty():
			continue
		var missing: Array[String] = []
		for path in SoundKit.fill_files(slot):
			if not ResourceLoader.exists(path):
				missing.append(path)
		_check(sources.has(str(fill.get("from", ""))) and not (fill.get("files", []) as Array).is_empty() and missing.is_empty(),
				"%s: from %s, %d files %s" % [slot, fill.get("from"), (fill.get("files", []) as Array).size(), missing if not missing.is_empty() else "all there"])


func _test_noises_are_the_sims() -> void:
	print("\n== a slot's noise carries as far as the sim's: what players hear is what monsters hear ==")
	_check(SoundKit.NOISES["step"] == Senses.NOISE_STEP and SoundKit.NOISES["fight"] == Senses.NOISE_FIGHT
			and SoundKit.NOISES["door"] == Senses.NOISE_DOOR and SoundKit.NOISES["door_broken"] == Senses.NOISE_DOOR_BROKEN,
			"step, fight, door and door_broken are Senses' radii")
	_check(SoundKit.reach("sfx.footstep") == Senses.NOISE_STEP, "a footstep: %d cells" % SoundKit.reach("sfx.footstep"))
	_check(SoundKit.reach("sfx.door_wood_open") == Senses.NOISE_DOOR, "a door: %d cells" % SoundKit.reach("sfx.door_wood_open"))
	_check(SoundKit.reach("sfx.item_drop_light") == Senses.NOISE_THUD_LIGHT and SoundKit.reach("sfx.item_drop_heavy") == Senses.NOISE_THUD_HEAVY
			and SoundKit.noise_kind("sfx.item_drop_heavy") == "thud", "a dropped item: World.noise's thud, light 2 or heavy 4")
	_check(SoundKit.reach("sfx.door_wood_rattle") == Senses.NOISE_RATTLE and SoundKit.reach("sfx.chest_open") == Senses.NOISE_RUMMAGE
			and SoundKit.reach("sfx.break_wood") == Senses.NOISE_BREAK and SoundKit.reach("sfx.door_wood_lock") == Senses.NOISE_LATCH,
			"rattle, rummage, break and latch: Senses' radii")
	_check(SoundKit.noise("sfx.goblin_chatter") == "" and SoundKit.reach("sfx.goblin_chatter") > 0,
			"chatter: not heard by monsters, heard by players %d cells" % SoundKit.reach("sfx.goblin_chatter"))
	_check(SoundKit.reach("ui.click") == 0 and SoundKit.reach("amb.forest_day") == 0, "ui and beds: flat, no reach")
	_check(SoundKit.footstep("grass", 80.0) == "sfx.footstep_grass_medium" and SoundKit.footstep("water", 25.0) == "sfx.footstep_water_small"
			and SoundKit.footstep("mud", 120.0) == "sfx.footstep_stone_large", "a footstep by ground and body: grass medium, water small, unknown ground as stone")
	for ground: String in SoundKit.STEP_GROUNDS:
		for mass: float in [20.0, 80.0, 150.0]:
			_check(SoundKit.has(SoundKit.footstep(ground, mass)), "%s is a slot" % SoundKit.footstep(ground, mass))


func _test_fallbacks() -> void:
	print("\n== a slot with no takes plays its fallback's, else the placeholder; fallbacks end ==")
	for slot: String in SoundKit.slots():
		var seen: Array[String] = []
		var at := slot
		while at != "" and at not in seen:
			seen.append(at)
			at = str(SoundKit.spec(at).get("fallback", ""))
			if at != "" and not SoundKit.has(at):
				break
		_check(at == "", "%s: its fallbacks are slots and end (%s)" % [slot, " -> ".join(seen)])
	_check(SoundKit.played_from("sfx.footstep_grass_medium") == "sfx.footstep", "grass underfoot sounds as the footstep meanwhile")
	_check(SoundKit.played_from("sfx.door_wood_break") == "sfx.break_wood", "a door broken sounds as wood breaking meanwhile")
	_check(SoundKit.played_from("sfx.knockdown") == "sfx.knockback_body_soft", "a knockdown, through the bodyfall, as the soft thud")
	_check(SoundKit.filled_by("sfx.hit_flesh") == "fill" and SoundKit.files("sfx.hit_flesh").size() == 5, "hit_flesh: Kenney's five")
	_check(SoundKit.played_from("sfx.block_shield") == "" and SoundKit.files("sfx.block_shield").is_empty(), "a block: nothing yet, the placeholder")


func _test_takes() -> void:
	print("
== a third-party take: listed is filled (the status says so everywhere), played once it is there ==")
	_check(SoundKit.takes("sfx.block_shield").is_empty(), "takes.json lists no take of a block yet")
	var sonniss := SoundKit.source("sonniss-gdc-2024")
	_check(sonniss.get("store") == "external" and str(sonniss.get("path")) == "res://art/audio/external/",
			"a Sonniss source is stored external, synced into art/audio/external/")
	# A take listed but not synced (as on a machine without the sound library).
	SoundKit.all_takes()["sfx.block_shield"] = [{"file": "sfx.block_shield.ogg", "from": "sonniss-gdc-2024", "sha256": "0"}]
	SoundKit._files.clear()
	_check(SoundKit.take_files("sfx.block_shield") == ["res://art/audio/external/sfx.block_shield/sfx.block_shield.ogg"], "it is looked for in art/audio/external/<slot>/")
	_check(SoundKit.filled_by("sfx.block_shield") == "fill" and SoundKit.played_from("sfx.block_shield", false) == "sfx.block_shield",
			"listed: filled, by the lists alone")
	_check(SoundKit.played_from("sfx.block_shield") == "" and SoundKit.files("sfx.block_shield").is_empty(), "not synced: the placeholder meanwhile")
	_check("sonniss-gdc-2024" in SoundKit._sources_of("sfx.block_shield") and "sfx.block_shield" in SoundKit.third_party_block(),
			"THIRD_PARTY's block names it under its source")
	# Synced: a take that is there (a Kenney file, through its path from the slot's folder).
	SoundKit.all_takes()["sfx.block_shield"] = [{"file": "../sfx/hit_1.ogg", "from": "kenney-impact", "sha256": "0"}]
	SoundKit.source("kenney-impact")["path"] = "res://art/audio/"
	SoundKit._files.clear()
	_check(SoundKit.files("sfx.block_shield").size() == 1, "there: played (%s)" % [SoundKit.files("sfx.block_shield")])
	SoundKit.reload()
	_check(SoundKit.takes("sfx.block_shield").is_empty() and SoundKit.source("kenney-impact")["path"] == "res://art/audio/sfx/", "reload reads the files again")


func _test_placeholder() -> void:
	print("\n== the placeholder: a short blip by bus, silence for a bed ==")
	var blip := SoundKit.placeholder("sfx")
	_check(blip != null and blip.data.size() > 1000 and blip.get_length() < 0.2, "sfx: a blip (%s s)" % (blip.get_length() if blip != null else -1.0))
	_check(SoundKit.placeholder("sfx") == blip, "made once")
	_check(SoundKit.placeholder("voice") != null and SoundKit.placeholder("ui") != null, "voice and ui have one")
	_check(SoundKit.placeholder("ambience") == null and SoundKit.placeholder("music") == null, "ambience and music: silence")


func _test_folders() -> void:
	print("\n== the slot folders hold only slots' takes ==")
	var problems := SoundKit.check_folders()
	_check(problems.is_empty(), "art/audio/<category>/<slot>/ %s" % [problems if not problems.is_empty() else "clean"])


func _test_sfx_plays_slots() -> void:
	print("\n== Sfx plays a slot: a different take each repeat, the blip for one with none, nothing for no slot ==")
	var sfx := Sfx.new()
	add_child(sfx)
	for i in 12:
		sfx.play("sfx.hit_flesh", Vector3.ZERO)
	var repeats := 0
	for i in range(1, sfx.played.size()):
		if sfx.played[i][1] == sfx.played[i - 1][1]:
			repeats += 1
	_check(sfx.played.size() == 12 and repeats == 0, "twelve hits, no take twice running (%d repeats)" % repeats)
	sfx.play("sfx.block_shield", Vector3.ZERO)
	_check(sfx.played.back().slice(0, 2) == ["sfx.block_shield", ""], "a slot with no takes plays the blip (%s)" % [sfx.played.back()])
	var before := sfx.played.size()
	sfx.play("amb.forest_day", Vector3.ZERO)
	_check(sfx.played.size() == before, "a bed with no takes: silence")
	var player := sfx.get_child(sfx.get_child_count() - 1) as AudioStreamPlayer3D
	_check(player != null and player.bus == Sfx.BUS, "on the SFX bus")
	sfx.free()


func _test_status_current() -> void:
	print("\n== docs/sound_status.md and THIRD_PARTY.md say what each slot plays from now ==")
	var status := FileAccess.get_file_as_string("res://docs/sound_status.md")
	_check(status == SoundKit.status_markdown(), "docs/sound_status.md is current (run tools/sound_status.tscn if not)")
	var third := FileAccess.get_file_as_string("res://THIRD_PARTY.md")
	_check(SoundKit.third_party_block() in third, "THIRD_PARTY.md's sound slot block is current (run tools/sound_status.tscn if not)")


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1
