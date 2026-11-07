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
	_test_ambience_weights()
	_test_music()
	_test_folders()
	_test_sfx_plays_slots()
	await _test_ui_sounds()
	_test_credits()
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
	_check(SoundKit.reach("sfx.bow_loose") == World.NOISE_BOW and SoundKit.noise_kind("sfx.bow_loose") == "bow",
			"a bow loosed: World.shoot's bow noise, %d cells" % SoundKit.reach("sfx.bow_loose"))
	var shot := int(Items.VERBS["ranged"]["cells"])
	for slot: String in ["sfx.arrow_hit_flesh", "sfx.arrow_hit_wood", "sfx.arrow_hit_stone", "sfx.arrow_land", "sfx.arrow_water"]:
		_check(SoundKit.reach(slot) > shot, "%s heard past a bow's reach (%d cells, the bow %d)" % [slot, SoundKit.reach(slot), shot])
	for slot: String in ["sfx.arrow_lob_rise", "sfx.arrow_lob_fall"]:
		_check(SoundKit.positional(slot) and SoundKit.noise(slot) == "" and SoundKit.takes(slot).size() == 3,
				"%s: placed, no noise for monsters (the loose is the bow's), three takes of its own" % slot)
	_check(SoundKit.positional("sfx.slab_grind") and SoundKit.reach("sfx.slab_grind") == SoundKit.reach("sfx.door_wood_open")
			and SoundKit.takes("sfx.slab_grind").size() == 3,
			"a stone slab drawn open: placed, heard as far as a door (%d cells), three takes" % SoundKit.reach("sfx.slab_grind"))
	_check(SoundKit.reach("sfx.arrow_lob_fall") >= 5, "a lob's falling whistle heard a few cells round where it lands (%d)" % SoundKit.reach("sfx.arrow_lob_fall"))
	_check(SoundKit.footstep("grass", 80.0) == "sfx.footstep_grass_medium" and SoundKit.footstep("water", 25.0) == "sfx.footstep_water_small"
			and SoundKit.footstep("mud", 120.0) == "sfx.footstep_stone_large", "a footstep by ground and body: grass medium, water small, unknown ground as stone")
	_check(SoundKit.footstep("grass", 60.0, "deer") == "sfx.footstep_hooves" and SoundKit.footstep("stone", 30.0, "wolf") == "sfx.footstep_claws"
			and SoundKit.footstep("dirt", 2.0, "rabbit") == "sfx.footstep_paws" and SoundKit.footstep("dirt", 80.0, "imp") == "sfx.footstep_dirt_medium",
			"an animal steps on its own feet: hooves, claws, paws; a goblin by the ground")
	_check(SoundKit.footstep("water", 60.0, "deer") == "sfx.footstep_water_medium" and SoundKit.footstep("water", 2.0, "rabbit") == "sfx.footstep_water_small"
			and SoundKit.footstep("water", 140.0, "boar") == "sfx.footstep_water_large",
			"an animal in water or a ford splashes by its size (505 amended (3)): a deer medium, a rabbit small, a heavy boar large")
	_check(SoundKit.positional("sfx.wade_drip") and SoundKit.noise("sfx.wade_drip") == "" and SoundKit.reach("sfx.wade_drip") <= Senses.NOISE_STEP
			and SoundKit.takes("sfx.wade_drip").size() >= 2,
			"a drip off a body out of the water: placed, no monster's noise, heard no further than a step (%d), takes of its own" % SoundKit.reach("sfx.wade_drip"))
	_check(SoundKit.cry("wolf", "call") == "sfx.wolf_howl" and SoundKit.cry("imp", "call") == "sfx.goblin_alert"
			and SoundKit.cry("stag", "rout") == "sfx.deer_rout" and SoundKit.cry("boar", "charge") == "sfx.boar_charge",
			"cries by kind: a wolf's call a howl, a goblin's its alert, a stag bolts as a deer, a boar charges")
	_check(SoundKit.cry("deer", "suspicious") == "sfx.deer_snort" and SoundKit.cry("stag", "suspicious") == "sfx.deer_snort"
			and SoundKit.cry("imp", "suspicious") == "", "a deer or stag snorts as its head comes up; a goblin says nothing")
	_check(SoundKit.struck("deer") == "sfx.deer_struck" and SoundKit.struck("stag") == "sfx.stag_struck"
			and SoundKit.struck("rabbit") == "sfx.rabbit_struck" and SoundKit.struck("boar") == ""
			and SoundKit.struck("wolf") == "" and SoundKit.struck("imp") == "",
			"game struck cries out (764): a doe, a stag its own, a rabbit; a boar, a wolf and a goblin not")
	_check(SoundKit.wave("wolves") == "sfx.wave_wolves" and SoundKit.wave("dead") == "sfx.wave_dead"
			and SoundKit.wave("raiders") == "sfx.wave_raiders" and SoundKit.wave("dragons") == "" and SoundKit.wave("") == "",
			"a night watch's wave announces itself by kind (771); an unknown kind comes unannounced")
	for slot: String in ["sfx.wave_wolves", "sfx.wave_dead", "sfx.wave_raiders"]:
		_check(SoundKit.positional(slot) and SoundKit.noise(slot) == "" and SoundKit.reach(slot) >= 80
				and SoundKit.takes(slot).size() >= 2,
				"%s: placed, heard %d cells (a wave 40 off behind a palisade, muffled, at half), not a monster's noise, takes of its own" % [slot, SoundKit.reach(slot)])
	for slot: String in ["sfx.deer_struck", "sfx.stag_struck", "sfx.rabbit_struck"]:
		_check(SoundKit.positional(slot) and SoundKit.noise(slot) == "" and SoundKit.reach(slot) > shot
				and SoundKit.takes(slot).size() >= 2,
				"%s: placed, heard past a bow's reach (%d cells), not a monster's noise, takes of its own" % [slot, SoundKit.reach(slot)])
	_check(SoundKit.cry("great_bear", "roar") == "sfx.great_bear_roar" and SoundKit.cry("great_bear", "swipe") == "sfx.great_bear_growl"
			and SoundKit.cry("great_bear", "slam") == "sfx.great_bear_growl" and SoundKit.cry("great_bear", "charge") == "sfx.great_bear_growl"
			and SoundKit.struck("great_bear") == "sfx.great_bear_struck" and SoundKit.death("great_bear") == "sfx.great_bear_death"
			and float(SoundKit.CREATURE_PITCH.get("great_bear", 1.0)) < 1.0,
			"the great bear (780): roars, growls with each tell (swipe, slam, charge), cries struck, dies its own; pitched deep")
	_check(SoundKit.reach("sfx.great_bear_roar") >= GreatBear.ROAR_REACH and SoundKit.reach("sfx.great_bear_growl") >= GreatBear.TELL_REACH
			and SoundKit.takes("sfx.great_bear_roar").size() >= 2 and SoundKit.takes("sfx.great_bear_growl").size() >= 2,
			"its roar heard as far as the sim's (%d >= %d cells), a growl as far as a tell (%d), takes of their own"
			% [SoundKit.reach("sfx.great_bear_roar"), GreatBear.ROAR_REACH, SoundKit.reach("sfx.great_bear_growl")])
	_check(SoundKit.positional("amb.campfire") and SoundKit.noise("amb.campfire") == "" and SoundKit.reach("amb.campfire") > SoundKit.reach("amb.torch_fire")
			and SoundKit.reach("amb.campfire") > Main.WARM_REACH and str(SoundKit.spec("amb.campfire").get("fallback", "")) == "amb.torch_fire"
			and SoundKit.takes("amb.campfire").size() >= 2,
			"a camp's fire (777): placed, heard further than a torch (%d > %d) and past its warmth, a torch's crackle without its own takes"
			% [SoundKit.reach("amb.campfire"), SoundKit.reach("amb.torch_fire")])
	_check(SoundKit.cry("boar_king", "call") == "sfx.boar_king_roar" and SoundKit.cry("boar_king", "roar") == "sfx.boar_king_roar"
			and SoundKit.cry("boar_king", "charge") == "sfx.boar_king_charge" and SoundKit.death("boar_king") == "sfx.boar_king_death"
			and SoundKit.footstep("dirt", 200.0, "boar_king") == "sfx.footstep_hooves_heavy" and SoundKit.CREATURE_PITCH["boar_king"] < 1.0,
			"the boar king (795): his own roar (his call and his coming out), charge, death and heavier hooves, pitched deep")
	_check(str(SoundKit.spec("sfx.boar_king_charge").get("fallback", "")) == "sfx.boar_charge"
			and str(SoundKit.spec("sfx.boar_king_death").get("fallback", "")) == "sfx.boar_death"
			and str(SoundKit.spec("sfx.footstep_hooves_heavy").get("fallback", "")) == "sfx.footstep_hooves"
			and SoundKit.reach("sfx.boar_king_charge") == Animal.NOISE_CHARGE and SoundKit.takes("sfx.boar_king_roar").size() >= 2
			and SoundKit.takes("sfx.boar_king_charge").size() >= 2, "his charge, death and steps a boar's where he has none of his own; takes for his roar and charge")
	# 814, sound's side: the hill cat snarls when seen, roars as it lands its
	# leap, hisses struck, dies its own way (else a wolf's), on paws.
	_check(SoundKit.cry("hill_cat", "call") == "sfx.hill_cat_snarl" and SoundKit.cry("hill_cat", "pounce") == "sfx.hill_cat_pounce"
			and SoundKit.struck("hill_cat") == "sfx.hill_cat_struck" and SoundKit.death("hill_cat") == "sfx.hill_cat_death"
			and SoundKit.footstep("dirt", 200.0, "hill_cat") == "sfx.footstep_paws"
			and str(SoundKit.spec("sfx.hill_cat_death").get("fallback", "")) == "sfx.wolf_death"
			and ["snarl", "pounce", "struck", "death"].all(func(cry: String) -> bool: return SoundKit.takes("sfx.hill_cat_" + cry).size() >= 3),
			"the hill cat: its snarl, pounce, hurt and death its own, three takes each, its death a wolf's without; on paws")
	# 790 amended (4), sound's side: Skeech (a sneak) hisses as his ambush's
	# windup starts, sharp and short, heard behind you, never by monsters.
	_check(SoundKit.cry("sneak", "ambush") == "sfx.goblin_ambush" and SoundKit.positional("sfx.goblin_ambush")
			and SoundKit.noise("sfx.goblin_ambush") == "" and SoundKit.bus("sfx.goblin_ambush") == "voice"
			and SoundKit.takes("sfx.goblin_ambush").size() >= 3 and SoundKit.cry("wolf", "ambush") == "",
			"a sneak's ambush hisses (sfx.goblin_ambush, three takes, positional, unheard by monsters); a kind with no ambush slot, nothing")
	_check(SoundKit.idle("boar").has("sfx.boar_grunt") and SoundKit.idle("boar").has("sfx.boar_root") and SoundKit.idle("boar_king") == SoundKit.idle("boar")
			and SoundKit.idle("deer").is_empty() and SoundKit.takes("sfx.boar_grunt").size() >= 2 and SoundKit.takes("sfx.boar_root").size() >= 2
			and SoundKit.positional("sfx.boar_grunt") and SoundKit.noise("sfx.boar_grunt") == "",
			"a boar at peace grunts and roots (795), the king as a boar; a deer has none; no sim noise")
	_check(SoundKit.link_url("https://freesound.org/people/jnr hacksaw/sounds/11126/") == "https://freesound.org/people/jnr%20hacksaw/sounds/11126/"
			and SoundKit.third_party_block().find("jnr hacksaw/") == -1 and SoundKit.third_party_block().find("jnr%20hacksaw/") >= 0,
			"a maker's name with a space: the credit's link percent-encoded, the name as shown kept (795, release's ask)")
	_check(SoundKit.reach("sfx.boar_charge") == Animal.NOISE_CHARGE and SoundKit.reach("sfx.wolf_howl") == Senses.NOISE_CALL,
			"a charge carries Animal.NOISE_CHARGE, a howl the call's")
	_check(SoundKit.death("rabbit") == "sfx.rabbit_death" and SoundKit.death("stag") == "sfx.deer_death" and SoundKit.death("brute") == "sfx.goblin_death",
			"a death by kind: an animal's own, a goblin's")
	_check(SoundKit.hit("") == "sfx.hit_fist_flesh" and SoundKit.hit("hammer") == "sfx.hit_blunt_flesh" and SoundKit.hit("sword") == "sfx.hit_blade_flesh"
			and SoundKit.hit("dagger") == "sfx.hit_blade_flesh", "a blow by weapon: fists, a blunt hammer, a blade")
	_check(SoundKit.hit("sword", "plate") == "sfx.hit_blade_armor" and SoundKit.hit("hammer", "mail") == "sfx.hit_blunt_armor"
			and SoundKit.hit("", "plate") == "sfx.hit_blunt_armor" and SoundKit.hit("sword", "leather") == "sfx.hit_blade_flesh"
			and SoundKit.hit("sword", "robes") == "sfx.hit_blade_flesh", "on worn plate or mail: a blade's or a knock's on metal; leather and robes as flesh")
	_check(SoundKit.voice(null, "death", &"female") == "voice.foe_death_female" and SoundKit.voice(null, "death", &"male") == "voice.foe_death_male"
			and SoundKit.voice(null, "effort_hurt", &"male") == "voice.effort_hurt_male" and SoundKit.voice(null, "death") == "",
			"a person-drawn monster's voice by its look's body, its death a foe's grunt; none without one")
	# Jeff, the crypt: a robber's death scream "too exaggerated": a short grunt,
	# quieter than a player's cry, several to pick from.
	var grunts := true
	for body: String in ["male", "female"]:
		var slot := "voice.foe_death_" + body
		grunts = grunts and SoundKit.takes(slot).size() >= 5 and SoundKit.volume_db(slot) < SoundKit.volume_db("voice.death_" + body)
		for take: Dictionary in SoundKit.takes(slot):
			grunts = grunts and str(take.get("from", "")) == "freesound"
	_check(grunts, "a foe's death grunt: five takes or more for each body, all Freesound, quieter than a player's death cry")
	_check(SoundKit.takes("sfx.hit_blade_flesh").size() == 3 and SoundKit.takes("sfx.hit_blade_flesh").all(
			func(take: Dictionary) -> bool: return str(take.get("from", "")) == "freesound"),
			"the sword's hit: three freesound impacts with an onset (the slash swish gone)")
	_check(SoundKit.block("shield") == "sfx.block_shield" and SoundKit.block("sword") == "sfx.block_weapon" and SoundKit.block("") == "sfx.block_weapon",
			"a guard: a shield's knock, else a parry")
	_check(SoundKit.positional("sfx.parry_clash") and SoundKit.takes("sfx.parry_clash").size() == 3
			and str(SoundKit.spec("sfx.parry_clash").get("fallback", "")) == "sfx.block_weapon"
			and SoundKit.positional("sfx.parry_scrape") and SoundKit.takes("sfx.parry_scrape").size() == 3
			and not SoundKit.spec("sfx.parry_scrape").has("fallback"),
			"blade meeting blade (732): a placed clash, three takes, the parry's as fallback; a scrape under it, silent untaken")
	_check(SoundKit.takes("sfx.block_weapon").size() == 1
			and str(SoundKit.takes("sfx.block_weapon")[0].get("original", "")).begins_with("freesound 733887"),
			"the parry's take: one, the same recording, re-cut under full scale (732)")
	var draugr := Draugr.new()
	var other := Monster.new()
	_check(SoundKit.speech(draugr, Draugr.REFUSED) == "voice.draugr_laugh" and SoundKit.speech(draugr, Draugr.WON) == ""
			and SoundKit.speech(other, Draugr.REFUSED) == "" and SoundKit.speech(null, Draugr.REFUSED) == "",
			"the draugr laughs on his refusal line alone; anyone else's speech is silent (735)")
	draugr.free()
	other.free()
	_check(SoundKit.positional("voice.draugr_laugh") and SoundKit.takes("voice.draugr_laugh").size() == 3
			and not SoundKit.spec("voice.draugr_laugh").has("fallback"),
			"his laugh: placed at him, three takes, silent untaken (735)")
	_check(SoundKit.swing("giant_axe") == "sfx.swing_heavy" and SoundKit.swing("sword") == "sfx.swing" and SoundKit.swing("") == "sfx.swing"
			and SoundKit.swing("bow") == "sfx.swing", "a two-handed weapon swings heavy; a bow is no club")
	# 662: a blade drawn and sheathed, any other piece taken up and stowed; every slot real.
	_check(SoundKit.stow_slot("sword", true) == "sfx.blade_draw" and SoundKit.stow_slot("dagger", false) == "sfx.blade_sheathe"
			and SoundKit.stow_slot("knife", true) == "sfx.blade_draw", "a sword, dagger or knife: the blade's draw and sheathe")
	_check(SoundKit.stow_slot("shield", false) == "sfx.gear_stow" and SoundKit.stow_slot("spear", true) == "sfx.gear_draw"
			and SoundKit.stow_slot("battle_axe", false) == "sfx.gear_stow", "a shield, spear or axe: gear's stow and draw")
	var stowed := true
	for id: String in ["sword", "shield"]:
		for drawing: bool in [true, false]:
			stowed = stowed and SoundKit.has(SoundKit.stow_slot(id, drawing)) and bool(SoundKit.spec(SoundKit.stow_slot(id, drawing)).get("positional", true))
	_check(stowed, "the four rest slots are in the manifest, positional")
	# 676 1b: worn armour's clank, by World.armour_noise's kind and radius.
	_check(SoundKit.armour_slot("plate") == "sfx.armour_plate" and SoundKit.armour_slot("mail") == "sfx.armour_mail" and SoundKit.armour_slot("none") == ""
			and SoundKit.has("sfx.armour_plate") and SoundKit.has("sfx.armour_mail") and SoundKit.positional("sfx.armour_plate"),
			"plate clanks, mail jingles, the rest nothing; both slots positional")
	_check(SoundKit.armour_db("plate", 5) == 0.0 and is_equal_approx(SoundKit.armour_db("plate", 10), 6.0) and is_equal_approx(SoundKit.armour_db("mail", 1), -6.0)
			and SoundKit.armour_db("plate", 19) == SoundKit.ARMOUR_DB_RANGE.y and SoundKit.armour_db("mail", 0) == SoundKit.ARMOUR_DB_RANGE.x,
			"as loud as its slot at a walk's radius, 6 dB a doubling, within %s" % SoundKit.ARMOUR_DB_RANGE)
	_check(SoundKit.step_pace(0.0) == 1.0 and SoundKit.step_pace(SoundKit.ARMOUR_STANDING) == 1.0
			and is_equal_approx(SoundKit.step_pace(World.CLANK_WALK_TICKS / World.TICK_RATE), 1.0) and is_equal_approx(SoundKit.step_pace(World.CLANK_WALK_TICKS / World.TICK_RATE / 2.0), 2.0)
			and SoundKit.step_pace(0.01) == 2.0,
			"pace from the time between steps: a walk 1, twice as quick 2 (capped), a first step or one from standing a walk")
	var plate_walk: Dictionary = World.armour_noise("plate_armour", 1.0)
	var plate_run: Dictionary = World.armour_noise("plate_armour", SoundKit.step_pace(World.CLANK_WALK_TICKS / World.TICK_RATE / 2.0))
	_check(plate_walk["kind"] == "plate" and SoundKit.armour_db("plate", int(plate_walk["radius"])) == 0.0
			and SoundKit.armour_db("plate", int(plate_run["radius"])) > 5.0 and World.armour_noise("leather_armour", 2.0)["kind"] == "none",
			"physics' radii: plate at a walk as its slot (%s), louder at a run (%s); leather none" % [plate_walk, plate_run])
	var light := ""
	var heavy := ""
	for id: String in Items.ids():
		if Items.weight_of(id) >= World.THUD_HEAVY_KG and heavy == "":
			heavy = id
		elif Items.weight_of(id) < World.THUD_HEAVY_KG and light == "":
			light = id
	_check(SoundKit.handled(light, "drop") == "sfx.item_drop_light" and SoundKit.handled(heavy, "drop") == "sfx.item_drop_heavy"
			and SoundKit.handled(light, "pickup") == "sfx.item_pickup_light" and SoundKit.handled(heavy, "land") == "sfx.thrown_land_heavy",
			"a thing handled: light or heavy at the sim's thud split (%s, %s)" % [light, heavy])
	var chest := Chest.new()
	_check(SoundKit.closing(chest) == "sfx.chest_close" and SoundKit.closing(null) == "", "a chest's lid shuts; nothing else")
	chest.free()
	var someone := Player.new()
	var her := Companion.new()
	var imp := Monster.new()
	_check(SoundKit.voice(someone, "effort_swing") == "voice.effort_swing_male" and SoundKit.voice(her, "death") == "voice.death_female"
			and SoundKit.voice(imp, "effort_hurt") == "", "voices by body: a player's (male by default), a companion's (female by default), a monster none")
	someone.body = &"female"
	her.body = &"male"
	_check(SoundKit.voice(someone, "effort_hurt") == "voice.effort_hurt_female" and SoundKit.voice(her, "effort_lift") == "voice.effort_lift_male",
			"a player with the female body, a companion like Pip with the male one")
	for one: Node in [someone, her, imp]:
		one.free()
	for slot: String in ["sfx.hit_blade_flesh", "sfx.hit_blunt_flesh", "sfx.hit_fist_flesh", "sfx.block_shield", "sfx.block_weapon", "sfx.swing_heavy",
			"voice.effort_swing_male", "voice.death_female"]:
		_check(SoundKit.has(slot), "%s is a slot" % slot)
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
	# As if these had no takes yet, whatever the library holds now.
	_without_takes(["sfx.footstep_sand_medium", "sfx.knockdown", "sfx.bodyfall", "sfx.block_shield", "sfx.door_wood_break"])
	_check(SoundKit.played_from("sfx.footstep_sand_medium", false) == "sfx.footstep", "sand underfoot sounds as the footstep meanwhile")
	_check(SoundKit.played_from("sfx.footstep_grass_small", false) == "sfx.footstep_grass_medium", "a small body on grass, as a medium one meanwhile")
	_check(SoundKit.played_from("sfx.door_wood_break") == "sfx.break_wood", "a door broken sounds as wood breaking meanwhile")
	_check(SoundKit.played_from("sfx.knockdown") == "sfx.knockback_body_soft", "a knockdown, through the bodyfall, as the soft thud")
	_check(SoundKit.filled_by("sfx.hit_flesh") == "fill" and SoundKit.files("sfx.hit_flesh").size() == 5, "hit_flesh: Kenney's five")
	_check(SoundKit.played_from("sfx.block_shield") == "" and SoundKit.files("sfx.block_shield").is_empty(), "a block: nothing yet, the placeholder")
	SoundKit.reload()


func _test_takes() -> void:
	print("
== a third-party take: listed is filled (the status says so everywhere), played once it is there ==")
	var listed := SoundKit.takes("sfx.block_shield").duplicate(true)
	_without_takes(["sfx.block_shield"])
	var sonniss := SoundKit.source("sonniss-gdc-2024")
	_check(sonniss.get("store") == "external" and str(sonniss.get("path")) == "res://art/audio/external/",
			"a Sonniss source is stored external, synced into art/audio/external/")
	# A take listed but not synced (as on a machine without the sound library).
	SoundKit.all_takes()["sfx.block_shield"] = [{"file": "sfx.block_shield.9.ogg", "from": "sonniss-gdc-2024", "sha256": "0"}]
	SoundKit.forget_files()
	_check(SoundKit.take_files("sfx.block_shield") == ["res://art/audio/external/sfx.block_shield/sfx.block_shield.9.ogg"], "it is looked for in art/audio/external/<slot>/")
	_check(SoundKit.filled_by("sfx.block_shield") == "fill" and SoundKit.played_from("sfx.block_shield", false) == "sfx.block_shield",
			"listed: filled, by the lists alone")
	_check(SoundKit.played_from("sfx.block_shield") == "" and SoundKit.files("sfx.block_shield").is_empty(), "not synced: the placeholder meanwhile")
	_check("sonniss-gdc-2024" in SoundKit._sources_of("sfx.block_shield") and "sfx.block_shield" in SoundKit.third_party_block(),
			"THIRD_PARTY's block names it under its source")
	# A Freesound take: its own licence, maker and page, credited.
	var freesound := SoundKit.source("freesound")
	_check(freesound.get("store") == "external" and FileAccess.file_exists("res://" + str(freesound.get("license_file"))),
			"Freesound is a source stored external, its licences written down")
	SoundKit.all_takes()["sfx.block_shield"] = [{"file": "sfx.block_shield.ogg", "from": "freesound", "sha256": "0",
			"original": "freesound 1: Shield [hit]", "by": "someone", "url": "https://freesound.org/s/1/", "license": "CC BY 4.0"}]
	_check("- `sfx.block_shield` (sfx.block_shield.ogg): cut from [freesound 1: Shield (hit)](https://freesound.org/s/1/) by someone, CC BY 4.0" \
			in SoundKit.third_party_block(), "THIRD_PARTY credits a take with a maker: its page, maker and licence")
	# Synced: a take that is there (a Kenney file, through its path from the slot's folder).
	SoundKit.all_takes()["sfx.block_shield"] = [{"file": "../sfx/hit_1.ogg", "from": "kenney-impact", "sha256": "0"}]
	SoundKit.source("kenney-impact")["path"] = "res://art/audio/"
	SoundKit.forget_files()
	_check(SoundKit.files("sfx.block_shield").size() == 1, "there: played (%s)" % [SoundKit.files("sfx.block_shield")])
	_check(SoundKit._played_from.get("sfx.block_shield") == "sfx.block_shield", "what a slot plays from is resolved once, kept (perf: Music weighs by it)")
	SoundKit.reload()
	_check(SoundKit._played_from.is_empty(), "reload forgets it")
	_check(SoundKit.takes("sfx.block_shield") == listed and SoundKit.source("kenney-impact")["path"] == "res://art/audio/sfx/", "reload reads the files again")


func _test_ambience_weights() -> void:
	print("
== ambience: each bed's weight by zone, roof, the clock and the weather ==")
	var clear := {"kind": "clear", "rain": 0.0, "wind": 0.0}
	var noon := Ambience.weights("outdoors", true, 1.0, 12.0, clear, 0.0)
	_check(is_equal_approx(noon["amb.forest_day"], 1.0) and noon["amb.forest_night"] == 0.0 and noon["amb.dungeon"] == 0.0
			and noon["amb.forest_dawn"] == 0.0, "outdoors at noon, clear: the forest by day alone (%s)" % [noon])
	var night := Ambience.weights("outdoors", true, DayNight.NIGHT, 0.0, clear, 0.0)
	_check(is_equal_approx(night["amb.forest_night"], 1.0) and night["amb.forest_day"] == 0.0, "at midnight: the night bed (owls)")
	var dawn := Ambience.weights("outdoors", true, 0.6, Ambience.DAWN_HOUR, clear, 0.0)
	_check(is_equal_approx(dawn["amb.forest_dawn"], 1.0) and dawn["amb.forest_day"] == 0.0, "at dawn: the dawn chorus")
	var rain := Ambience.weights("outdoors", true, 1.0, 12.0, {"kind": "rain", "rain": 1.0, "wind": 0.3}, 0.0)
	_check(is_equal_approx(rain["amb.rain"], 1.0) and is_equal_approx(rain["amb.forest_day"], 1.0 - Ambience.RAIN_HUSH)
			and is_equal_approx(rain["amb.field_wind"], 0.3), "rain: the rain bed, the birds hushed, the wind as it blows")
	var storm := Ambience.weights("outdoors", true, 0.5, 15.0, {"kind": "storm", "rain": 1.0, "wind": 1.0}, 0.0)
	_check(storm["amb.storm"] > 0.5 and storm["amb.rain"] < 0.5, "a storm: the storm bed over the rain (%.2f, %.2f)" % [storm["amb.storm"], storm["amb.rain"]])
	var roofed := Ambience.weights("outdoors", false, 1.0, 12.0, clear, 0.0)
	_check(is_equal_approx(roofed["amb.forest_day"], Ambience.ROOFED), "under a roof: outdoor beds quieter")
	var town := Ambience.weights("outdoors", true, 1.0, 12.0, clear, 1.0)
	_check(is_equal_approx(town["amb.town_day"], 1.0) and town["amb.town_night"] == 0.0, "by a town's buildings by day: its day bed")
	var dungeon := Ambience.weights("dungeon", true, 1.0, 12.0, {"kind": "storm", "rain": 1.0, "wind": 1.0}, 0.0)
	_check(dungeon["amb.dungeon"] == 1.0 and dungeon["amb.rain"] == 0.0 and dungeon["amb.forest_day"] == 0.0, "under stone: the dungeon bed, no weather")
	_check(dungeon["amb.mine_tunnel"] == 0.0 and dungeon["amb.mine_chamber"] == 0.0, "no mine: no mine bed")
	var tunnel := Ambience.weights("dungeon", false, 1.0, 12.0, clear, 0.0, 0.0, 0.0, 0.0)
	_check(tunnel["amb.mine_tunnel"] == 1.0 and tunnel["amb.mine_chamber"] == 0.0 and tunnel["amb.dungeon"] == 0.0,
			"in a mine's tunnel (769 amended (4)): its own near-silent bed, never the crypt's cave bed (%s)" % [tunnel])
	var chamber := Ambience.weights("cave", false, 1.0, 12.0, clear, 0.0, 0.0, 0.0, 1.0)
	_check(chamber["amb.mine_chamber"] == 1.0 and chamber["amb.mine_tunnel"] == 0.0 and chamber["amb.dungeon"] == 0.0,
			"in a mine's chamber: the chamber's bed")
	var corridor: Dictionary = {}
	var room: Dictionary = {}
	for x in range(-10, 11):
		for y in range(0, 2):
			corridor[Vector2i(x, y)] = true
		for y in range(-5, 6):
			room[Vector2i(x, y)] = true
	_check(Ambience.openness(corridor, Vector2i(0, 0)) == 0.0 and Ambience.openness(room, Vector2i(0, 0)) == 1.0,
			"a two-wide corridor reads as a tunnel (%.2f), an open room as a chamber (%.2f)"
			% [Ambience.openness(corridor, Vector2i(0, 0)), Ambience.openness(room, Vector2i(0, 0))])
	var floor_cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	var parts := Ambience.mine_parts({"floor": floor_cells, "decor": [
			{"cell": Vector2i(1, 1), "out": Vector2i(0, -1), "kind": "mine_lamp", "variant": 1},
			{"cell": Vector2i(1, 1), "out": Vector2i(1, 0), "kind": "mine_arch", "variant": 1, "width": 3},
			{"cell": Vector2i(2, 1), "out": Vector2i(1, 0), "kind": "mine_track", "variant": 1},
			{"cell": Vector2i(3, 1), "out": Vector2i(0, 0), "kind": "barrel", "variant": 1}]})
	_check(not parts.is_empty() and parts["lamps"] == [Vector2i(1, 1)] and parts["timbers"] == [Vector2i(2, 1)] and parts["floor"].size() == 3,
			"a mine's parts from its decor: the lamp, the arch's middle, its floor (%s)" % [parts])
	_check(Ambience.mine_parts({"floor": floor_cells, "decor": [{"cell": Vector2i(1, 1), "out": Vector2i(0, 0), "kind": "barrel", "variant": 1}]}).is_empty(),
			"no mine piece: no mine")
	for slot: String in ["amb.mine_drip", "amb.timber_creak", "amb.lamp_hiss", "sfx.pick_strike", "sfx.ore_sack", "sfx.minecart_roll", "sfx.minecart_stop"]:
		_check(SoundKit.positional(slot) and SoundKit.noise(slot) == "" and not SoundKit.takes(slot).is_empty(), "%s: placed, no sim noise, takes of its own" % slot)
	_check(not SoundKit.positional("amb.mine_tunnel") and not SoundKit.positional("amb.mine_chamber")
			and not SoundKit.takes("amb.mine_tunnel").is_empty() and not SoundKit.takes("amb.mine_chamber").is_empty(), "the mine's beds: everywhere, with takes")
	_check(SoundKit.reach("sfx.pick_strike") >= Ambience.DRIP_FAR and SoundKit.reach("amb.mine_drip") >= Ambience.DRIP_FAR
			and SoundKit.reach("amb.timber_creak") >= Ambience.TIMBER_NEAR, "a drop heard from as far as it falls, a creak from its nearest timber")
	# A beast's cave (795 amended): its own bed, never the crypt's or a mine's.
	var lair := Ambience.weights("cave", false, 1.0, 12.0, clear, 0.0, 0.0, 0.0, -1.0, "cave_lair")
	_check(lair["amb.lair_cave"] == 1.0 and lair["amb.dungeon"] == 0.0 and lair["amb.mine_tunnel"] == 0.0 and lair["amb.mine_chamber"] == 0.0,
			"in a cave_lair: the lair's bed alone (%s)" % [lair])
	_check(Ambience.weights("cave", false, 1.0, 12.0, clear, 0.0)["amb.lair_cave"] == 0.0
			and Ambience.weights("outdoors", true, 1.0, 12.0, clear, 0.0, 0.0, 0.0, -1.0, "thicket")["amb.forest_day"] > 0.0,
			"no ambience key: no lair bed; a thicket under the sky: the forest's beds as outside")
	var said: Array[String] = []
	_check(Level.ambience_from({"ambience": "cave_lair"}, said) == "cave_lair" and Level.ambience_from({}, said) == "" and said.is_empty()
			and Level.ambience_from({"ambience": "cavern"}, said) == "" and said.size() == 1,
			"level.json's ambience: cave_lair read, none \"\", an unknown one \"\" and said (%s)" % [said])
	_check(not SoundKit.positional("amb.lair_cave") and not SoundKit.takes("amb.lair_cave").is_empty()
			and SoundKit.positional("amb.skylight_air") and SoundKit.noise("amb.skylight_air") == "" and SoundKit.takes("amb.skylight_air").size() >= 2
			and SoundKit.reach("amb.skylight_air") <= 6, "the lair's bed everywhere; the skylight's air placed, near (%d), takes of its own" % SoundKit.reach("amb.skylight_air"))
	# 795 amended (2): the camps' murmur, by 793's "mix", while a holder lives
	# by the fire.
	var camps: Array = [{"at": Vector2i(10, 10), "mix": "bandit"}, {"at": Vector2i(30, 10), "mix": "trader"},
		{"at": Vector2i(50, 10), "mix": "mixed"}]
	var far := Vector2i(50 + Ambience.CAMP_HELD_CELLS + 1, 10)
	var held := Ambience.held_camps(camps, {"bandits": [Vector2i(13, 12), far] as Array[Vector2i], "traders": [] as Array[Vector2i]})
	_check(held["amb.camp_bandit"] == [Vector2i(10, 10)] and held["amb.camp_trader"].is_empty(),
			"a bandit within CAMP_HELD_CELLS: its camp's talk; one past it: the mixed camp silent; no trader, no traders' talk (%s)" % [held])
	held = Ambience.held_camps(camps, {"bandits": [Vector2i(50, 13), Vector2i(30, 10)] as Array[Vector2i], "traders": [Vector2i(30, 11)] as Array[Vector2i]})
	_check(held["amb.camp_bandit"] == [Vector2i(50, 10)] and held["amb.camp_trader"] == [Vector2i(30, 10)],
			"a mixed camp held by bandits, its trader away: their talk alone; a trader at his fire: his; a bandit at a trader camp: none of theirs (%s)" % [held])
	held = Ambience.held_camps(camps, {"bandits": [] as Array[Vector2i], "traders": [Vector2i(51, 10)] as Array[Vector2i]})
	_check(held["amb.camp_bandit"].is_empty() and held["amb.camp_trader"] == [Vector2i(50, 10)],
			"a mixed camp cleared of bandits, its trader back at the fire: only his talk (%s)" % [held])
	held = Ambience.held_camps(camps, {})
	_check(held["amb.camp_bandit"].is_empty() and held["amb.camp_trader"].is_empty(), "every camp emptied: no murmur")
	var forest_camps := Level.camps_of(Level.load_level("forest").get("places", {}))
	var mixes := {}
	for camp: Dictionary in forest_camps:
		mixes[camp["mix"]] = true
	_check(forest_camps.size() >= 3 and mixes.has("bandit") and mixes.has("trader") and mixes.has("mixed")
			and "captive" not in Ambience.CAMP_HOLDERS,
			"the forest's camps read with their mix (%d: %s); a captive holds nothing" % [forest_camps.size(), mixes.keys()])
	_check(SoundKit.positional("amb.camp_bandit") and SoundKit.noise("amb.camp_bandit") == "" and SoundKit.takes("amb.camp_bandit").size() >= 3
			and SoundKit.positional("amb.camp_trader") and SoundKit.noise("amb.camp_trader") == "" and SoundKit.takes("amb.camp_trader").size() >= 3
			and SoundKit.volume_db("amb.camp_bandit") < SoundKit.volume_db("amb.campfire"),
			"the murmurs placed, unheard by monsters, under the fire, three takes each")
	# 795 amended (3): a beast's cave's way out breathes wind; the wolves growl.
	var bear_cave := Level.load_level("bear_cave")
	var cave_mouths: Array = bear_cave.get("terrain", {}).get("lair_mouths", [])
	var no_lair: Array = Level.lair_mouths_of("", [{"tile": Vector2i(3, 3)}] as Array[Dictionary])
	var wolf_mouths: Array = Level.load_level("wolf_cave").get("terrain", {}).get("lair_mouths", [])
	_check(cave_mouths == [Vector2i(4, 26)] and wolf_mouths == [Vector2i(6, 24)] and no_lair.is_empty()
			and Level.load_level("forest").get("terrain", {}).get("lair_mouths", []).is_empty(),
			"the bear's and the wolves' caves' mouths their links' cells (%s, %s); no mouths but a cave_lair's" % [cave_mouths, wolf_mouths])
	_check(SoundKit.positional("amb.cave_mouth_wind") and SoundKit.noise("amb.cave_mouth_wind") == ""
			and SoundKit.reach("amb.cave_mouth_wind") <= 10 and SoundKit.takes("amb.cave_mouth_wind").size() >= 3,
			"the mouth's wind placed, unheard by monsters, within 10, three takes")
	_check(SoundKit.idle("wolf").has("sfx.wolf_growl") and SoundKit.positional("sfx.wolf_growl") and SoundKit.noise("sfx.wolf_growl") == ""
			and SoundKit.bus("sfx.wolf_growl") == "voice" and SoundKit.reach("sfx.wolf_growl") <= 8
			and int(SoundKit.IDLE_APART_MS.get("sfx.wolf_growl", 0)) >= 4000 and SoundKit.takes("sfx.wolf_growl").size() >= 3,
			"a wolf at peace growls, near, unheard by monsters, never two within IDLE_APART_MS, three takes or more")
	_check(noon["amb.forest_deep_day"] == 0.0 and noon["amb.rain_canopy"] == 0.0 and noon["amb.drips"] == 0.0,
			"no canopy: no deep forest, no crowns, no drips")
	var deep := Ambience.weights("outdoors", true, 1.0, 12.0, clear, 0.0, 1.0)
	_check(is_equal_approx(deep["amb.forest_deep_day"], 1.0) and is_equal_approx(deep["amb.forest_day"], 1.0 - Ambience.DEEP)
			and deep["amb.forest_deep_night"] == 0.0, "under a full roof at noon: the deep forest by day over the open's (%s)" % [deep])
	var deep_night := Ambience.weights("outdoors", true, DayNight.NIGHT, 0.0, clear, 0.0, 0.5)
	_check(is_equal_approx(deep_night["amb.forest_deep_night"], 0.5) and is_equal_approx(deep_night["amb.forest_night"], 1.0 - Ambience.DEEP * 0.5),
			"half under the roof at midnight: the deep night bed half in")
	var crowns := Ambience.weights("outdoors", true, 1.0, 12.0, {"kind": "rain", "rain": 1.0, "wind": 0.0}, 0.0, 1.0, 1.0)
	_check(is_equal_approx(crowns["amb.rain_canopy"], 1.0) and is_equal_approx(crowns["amb.rain"], 1.0 - Ambience.CANOPY_RAIN)
			and is_equal_approx(crowns["amb.drips"], 1.0), "rain under the roof: on the crowns, little through, dripping")
	var after := Ambience.weights("outdoors", true, 1.0, 12.0, clear, 0.0, 0.8, 0.4)
	_check(after["amb.rain_canopy"] == 0.0 and is_equal_approx(after["amb.drips"], 0.4), "after the rain: the drips as Weather.drip_at has them")
	var roofed_deep := Ambience.weights("outdoors", false, 1.0, 12.0, clear, 0.0, 1.0, 1.0)
	_check(is_equal_approx(roofed_deep["amb.drips"], Ambience.ROOFED) and is_equal_approx(roofed_deep["amb.forest_deep_day"], Ambience.ROOFED),
			"under a roof in the forest: its beds quieter too")
	# Night's voices (Jeff: "no birds at night, maybe owls bats").
	var by_day := Ambience.calls("outdoors", 1.0, clear, 1.0, 1.0)
	_check(by_day["amb.owl"] == 0.0 and by_day["amb.bat"] == 0.0, "by day: no owls, no bats")
	var open_night := Ambience.calls("outdoors", DayNight.NIGHT, clear, 0.0, 0.0)
	var roofed_night := Ambience.calls("outdoors", DayNight.NIGHT, clear, 1.0, 0.0)
	_check(is_equal_approx(roofed_night["amb.owl"], 1.0 / Ambience.OWL_SECONDS) and is_equal_approx(open_night["amb.owl"] * 4.0, roofed_night["amb.owl"]),
			"at night an owl now and then, more under the roof (every %.0f s, %.0f s in the open)" % [1.0 / roofed_night["amb.owl"], 1.0 / open_night["amb.owl"]])
	var edge_night := Ambience.calls("outdoors", DayNight.NIGHT, clear, 0.5, 0.0)
	_check(is_equal_approx(edge_night["amb.bat"], 1.0 / Ambience.BAT_SECONDS) and roofed_night["amb.bat"] == 0.0 and open_night["amb.bat"] == 0.0,
			"bats by the canopy's edge, not deep under it nor out in the open")
	_check(is_equal_approx(Ambience.calls("outdoors", DayNight.NIGHT, clear, 0.0, 1.0)["amb.bat"], 1.0 / Ambience.BAT_SECONDS), "bats by a tower")
	var wet_night := Ambience.calls("outdoors", DayNight.NIGHT, {"kind": "rain", "rain": 1.0, "wind": 0.0}, 1.0, 0.0)
	_check(wet_night["amb.owl"] < roofed_night["amb.owl"] * 0.5, "rain hushes them")
	var under := Ambience.calls("dungeon", DayNight.NIGHT, clear, 1.0, 1.0)
	_check(under["amb.owl"] == 0.0 and under["amb.bat"] == 0.0, "none under stone")
	for slot: String in ["amb.owl", "amb.bat"]:
		_check(SoundKit.has(slot) and SoundKit.positional(slot) and SoundKit.reach(slot) > 0, "%s is a call from somewhere" % slot)
	# A stream heard from the nearest point of its course (decision 505).
	var course: Array[Vector2i] = [Vector2i(0, 0), Vector2i(4, 0), Vector2i(5, 1), Vector2i(5, 6)]
	var beside := Ambience.nearest_on(course, Vector2(2, 3))
	_check(beside.at == 0 and is_equal_approx(beside.t, 0.5) and is_equal_approx(beside.distance, 3.0), "a stream: beside its middle, the point across from you (%s)" % beside)
	var by_bend := Ambience.nearest_on(course, Vector2(8, 4))
	_check(by_bend.at == 2 and is_equal_approx(by_bend.t, 0.6) and is_equal_approx(by_bend.distance, 3.0), "a stream round a bend: along its last reach (%s)" % by_bend)
	var past := Ambience.nearest_on(course, Vector2(5, 10))
	_check(past.at == 2 and is_equal_approx(past.t, 1.0) and is_equal_approx(past.distance, 4.0), "past its end: its end (%s)" % past)
	_check(Ambience.nearest_on([Vector2i(3, 3)], Vector2(3, 7)).distance == 4.0 and Ambience.nearest_on([], Vector2.ZERO).is_empty(), "one cell; none")
	_check(SoundKit.positional("amb.stream") and SoundKit.reach("amb.stream") >= 12, "a stream heard from %d cells" % SoundKit.reach("amb.stream"))
	# A stream's fall (decision 557): louder the further it drops.
	_check(is_equal_approx(Ambience.fall_db(Client3D.FALL_LEAST), Ambience.FALL_DB.x) and is_equal_approx(Ambience.fall_db(3.0), Ambience.FALL_DB.y)
			and Ambience.fall_db(0.46) > Ambience.FALL_DB.x and Ambience.fall_db(0.46) < Ambience.FALL_DB.y,
			"a fall: %.1f dB at the least, %.1f at the hills' 0.46 m, %.1f at 3 m" % [Ambience.fall_db(Client3D.FALL_LEAST), Ambience.fall_db(0.46), Ambience.fall_db(3.0)])
	_check(SoundKit.positional("amb.falls") and SoundKit.reach("amb.falls") > 0, "a fall heard from %d cells" % SoundKit.reach("amb.falls"))
	for bed: String in Ambience.BEDS:
		_check(SoundKit.has(bed) and not SoundKit.positional(bed), "%s is a flat slot" % bed)


func _test_placeholder() -> void:
	print("\n== the placeholder: a short blip by bus, silence for a bed ==")
	var blip := SoundKit.placeholder("sfx")
	_check(blip != null and blip.data.size() > 1000 and blip.get_length() < 0.2, "sfx: a blip (%s s)" % (blip.get_length() if blip != null else -1.0))
	_check(SoundKit.placeholder("sfx") == blip, "made once")
	_check(SoundKit.placeholder("voice") != null and SoundKit.placeholder("ui") != null, "voice and ui have one")
	_check(SoundKit.placeholder("ambience") == null and SoundKit.placeholder("music") == null, "ambience and music: silence")


func _test_music() -> void:
	print("
== music: layers by zone, time and tension, phrases, stingers (decision 377) ==")
	for slot: String in SoundKit.slots():
		if slot.begins_with("music."):
			_check(not SoundKit.positional(slot) and str(SoundKit.spec(slot).get("bus")) == "music", "%s: flat, on Music" % slot)
	for zone: String in Music.ZONES:
		_check(SoundKit.has("music.%s_base" % zone) and (zone in Music.NO_MELODY or SoundKit.has("music.melody_" + zone)),
				"%s has a base, and a melody unless it goes without" % zone)
	# Jeff's ringing at every indoor map: the town's melody was a bell wash; no take now, and a bed with none is silent.
	_check(SoundKit.takes("music.melody_town").is_empty() and SoundKit.placeholder(SoundKit.bus("music.melody_town")) == null,
			"the town's melody: no take, silent (its bells rang over every indoor map)")
	# 728: the discovery stinger's chime was the squeal at every map start; retired, rejected for good, and never for the zone a session starts in.
	_check(SoundKit.takes("music.sting_discovery").is_empty() and SoundKit.files("music.sting_discovery").is_empty()
			and SoundKit.placeholder(SoundKit.bus("music.sting_discovery")) == null, "the discovery stinger: no take, silent (no blip on Music)")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SoundKit.MANIFEST))
	var rejected_listed := []
	for rejected: Dictionary in manifest.get("rejected", []):
		for slot: String in SoundKit.slots():
			for take: Dictionary in SoundKit.takes(slot):
				if str(take.get("original", "")).get_file().begins_with(str(rejected.file)):
					rejected_listed.append(slot)
	_check(manifest.get("rejected", []).size() >= 1 and rejected_listed.is_empty(), "no slot plays a rejected recording %s" % [rejected_listed])
	var visited_was := Music._visited.duplicate()
	Music._visited.clear()
	_check(not Music.discovers("practice") and not Music.discovers("practice") and Music.discovers("barrow") and not Music.discovers("barrow")
			and not Music.discovers(""), "a discovery: a zone first entered, never the one a session starts in")
	Music._visited = visited_was
	_check(Music.silent_level("practice") and Music.silent_level("test_room") and not Music.silent_level("barrow")
			and not Music.silent_level("wilds") and not Music.silent_level("") and Music.level_music("practice") == "",
			"the practice hall and the test room play no music; the barrow, the wilds and an unnamed level do")
	var temple := Music.weights("temple", 0.0, 0.0, true)
	_check(temple["music.temple_base"] == 1.0 and temple.keys().all(func(k: String) -> bool: return k == "music.temple_base" or temple[k] == 0.0),
			"in a temple, by night too: its ground alone")
	var buildings := [{"slot": "building.temple", "rect": Rect2i(10, 10, 4, 4)}, {"slot": "building.house", "rect": Rect2i(0, 0, 2, 2)}]
	_check(Music.temple_nearness(buildings, Vector2i(12, 12)) == 1.0 and is_equal_approx(Music.temple_nearness(buildings, Vector2i(10, 5)), 0.6)
			and Music.temple_nearness(buildings, Vector2i(1, 1)) == 0.0, "a temple near: full inside, fading out from its walls, none by a house")
	_check(Music.zone_of("outdoors", 1.0, 0.6) == "temple" and Music.zone_of("indoors", 0.0, 1.0) == "temple"
			and Music.zone_of("dungeon", 0.0, 1.0) == "dungeon", "a temple near is its zone, but not under stone")
	for kind: String in Music.STINGS:
		_check(SoundKit.has("music.sting_" + kind), "a %s stinger" % kind)
	_check(Music.zone_of("dungeon", 0.0) == "dungeon" and Music.zone_of("cave", 1.0) == "dungeon" and Music.zone_of("indoors", 0.0) == "town"
			and Music.zone_of("outdoors", 0.7) == "town" and Music.zone_of("outdoors", 0.2) == "wilds", "zones: under stone, a town or house, the wilds")
	var calm_day := Music.weights("wilds", 1.0, 0.0, true)
	_check(calm_day["music.wilds_base"] == 1.0 and calm_day["music.wilds_night"] == 0.0 and calm_day["music.melody_wilds"] > 0.0
			and calm_day["music.tension_low"] == 0.0 and calm_day["music.town_base"] == 0.0, "a calm day in the wilds: its base and melody")
	var night := Music.weights("town", 0.0, 0.0, true)
	_check(night["music.town_night"] == 1.0 and night["music.town_base"] == 0.0, "a town by night: its night layer")
	var rest := Music.weights("wilds", 1.0, 0.0, false)
	_check(rest.values().all(func(w: float) -> bool: return w == 0.0), "between phrases: silence")
	var wary := Music.weights("dungeon", 1.0, 0.4, false)
	_check(wary["music.tension_low"] == 1.0 and wary["music.tension_high"] == 0.0 and wary["music.dungeon_base"] > 0.0
			and wary["music.melody_dungeon"] == 0.0, "something wary near: the low tension layer and the ground, even between phrases")
	var fight := Music.weights("wilds", 1.0, 1.0, true)
	_check(fight["music.tension_high"] == 1.0 and fight["music.tension_low"] == 0.0 and fight["music.melody_wilds"] == 0.0
			and fight["music.wilds_base"] == 0.5, "a fight: the high layer, the ground down, the melody out")
	_check(Music.weights("wilds", 1.0, 0.5, true)["music.melody_wilds"] == 0.0 and Music.weights("wilds", 1.0, 0.3, true)["music.melody_wilds"] > 0.0,
			"the melody leaves by half tension")
	# 729: a 50 ms output buffer, so a loaded machine doesn't starve the mix (a starved WASAPI buffer replays its last chunk: a ring).
	_check(int(ProjectSettings.get_setting("audio/driver/output_latency", 15)) == 50, "the audio output buffer is 50 ms (729)")
	# 668: a level's own music, named in its level.json, in place of the zone's ground and melody.
	_check(Music.level_music("barrow") == "music.barrow" and Music.level_music("barrow_deep") == "" and Music.level_music("") == "",
			"the barrow's first level names its own music; the levels below none")
	_check(str(SoundKit.files("music.barrow")[0]).ends_with("music.barrow/music.barrow.ogg") and SoundKit.filled_by("music.barrow") == "own",
			"music.barrow plays Jeff's own take")
	# 668 amended: a named room's own music, the town of Umbrage's in the wilds.
	_check(Music.room_music("wilds", Vector2i(200, 200)) == "music.umbrage" and Music.room_music("wilds", Vector2i(70, 202)) == ""
			and Music.room_music("barrow", Vector2i(10, 10)) == "" and Music.room_music("", Vector2i.ZERO) == "",
			"the wilds' Umbrage room names the town's music; outside it, and a level without rooms, none")
	_check(str(SoundKit.files("music.umbrage")[0]).ends_with("music.umbrage/music.umbrage.ogg") and SoundKit.filled_by("music.umbrage") == "own",
			"music.umbrage plays Jeff's own take")
	_check(Music.own_fade("music.umbrage", true) == 2.0 * Music.LEVEL_FADE and Music.own_fade("music.umbrage", false) == Music.LEVEL_FADE
			and Music.own_fade("music.barrow", true) == Music.LEVEL_FADE and SoundKit.volume_db("music.umbrage") < SoundKit.volume_db("music.barrow"),
			"Umbrage's music comes in over twice the level fade, softer than the barrow's; out as fast; the barrow's as before (Jeff)")
	var own := Music.weights("dungeon", 1.0, 0.0, false, "music.barrow")
	_check(own["music.barrow"] == 1.0 and own["music.dungeon_base"] == 0.0 and own["music.melody_dungeon"] == 0.0,
			"a level's own music, even between phrases, the dungeon's ground and melody out")
	var own_fight := Music.weights("dungeon", 1.0, 1.0, true, "music.barrow")
	_check(own_fight["music.barrow"] == 0.5 and own_fight["music.tension_high"] == 1.0, "a fight over it: the high layer rises, the level's music down by half")
	_check(Music.tension_from([]) == 0.0 and Music.tension_from([[Monster.Alert.SUSPICIOUS, true]]) == Music.TENSION_SUSPICIOUS
			and Music.tension_from([[Monster.Alert.SUSPICIOUS, true], [Monster.Alert.FIGHTING, true]]) == 1.0
			and Music.tension_from([[Monster.Alert.HUNTING, false], [Monster.Alert.FLEEING, true]]) == 0.0,
			"tension: the most alarming hostile near; a harmless one or a fleeing one none")
	var deer := Animal.new()
	deer.spawn_spec = {"kind": "deer"}
	deer.alert = Monster.Alert.FIGHTING
	var wolf := Animal.new()
	wolf.spawn_spec = {"kind": "wolf"}
	wolf.alert = Monster.Alert.SUSPICIOUS
	var goblin := Monster.new()
	_check(not Music.hostile(deer) and not Music.hostile(wolf) and Music.hostile(goblin), "a deer is never a threat, a wolf only hunting, a goblin always")
	wolf.alert = Monster.Alert.HUNTING
	_check(Music.hostile(wolf), "a hunting wolf is")
	for one: Node in [deer, wolf, goblin]:
		one.free()
	var at := [0.0, 0.0]
	for i in 4:
		at = Music.step_tension(at[0], at[1], 1.0, 0.25)
	_check(is_equal_approx(at[0], 1.0 / Music.TENSION_RISE) or at[0] > 0.6, "tension rises quickly (%.2f after 1 s)" % at[0])
	for i in 8:
		at = Music.step_tension(at[0], at[1], 1.0, 0.25)
	_check(at[0] == 1.0, "and reaches full")
	at = Music.step_tension(at[0], at[1], 0.0, Music.TENSION_HOLD - 0.5)
	_check(at[0] == 1.0, "held a while once the threat is gone")
	at = Music.step_tension(at[0], at[1], 0.0, 1.0)
	at = Music.step_tension(at[0], at[1], 0.0, 1.0)
	_check(at[0] < 1.0 and at[0] > 0.8, "then falls slowly (%.2f)" % at[0])
	at = Music.step_tension(at[0], at[1], 0.0, Music.TENSION_FALL)
	_check(at[0] == 0.0, "to nothing")
	_check(Music.may_sting("danger", 100.0, -INF, {}) and not Music.may_sting("death", 110.0, 100.0, {"danger": 100.0})
			and Music.may_sting("death", 121.0, 100.0, {"danger": 100.0}) and not Music.may_sting("danger", 150.0, 100.0, {"danger": 100.0}),
			"stingers: none within 20 s of another, the same not within 2 min")
	_without_takes(["music.wilds_night"])
	var folded := Music.by_take({"music.wilds_night": 0.6, "music.wilds_base": 0.3})
	_check(SoundKit.files("music.wilds_base").is_empty() or (folded.size() == 1 and is_equal_approx(float(folded["music.wilds_base"]), 0.9)),
			"a night layer with no take of its own folds into its base's recording (%s)" % folded)
	SoundKit.reload()
	var was := Net.music_volume
	Net.music_volume = 0.0
	var music := Music.new()
	add_child(music)
	_check(Music.muted() and not music.sting("death"), "the Music slider at 0: nothing plays")
	Net.music_volume = was
	music.free()


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
	_without_takes(["sfx.block_shield", "amb.town_night"])
	sfx.play("sfx.block_shield", Vector3.ZERO)
	_check(sfx.played.back().slice(0, 2) == ["sfx.block_shield", ""], "a slot with no takes plays the blip (%s)" % [sfx.played.back()])
	var before := sfx.played.size()
	sfx.play("amb.town_night", Vector3.ZERO)
	_check(sfx.played.size() == before, "a bed with no takes: silence")
	var player := sfx.get_child(sfx.get_child_count() - 1) as AudioStreamPlayer3D
	_check(player != null and player.bus == Sfx.BUS, "on the SFX bus")
	sfx.free()
	SoundKit.reload()


## Forgets [param slots]' takes until SoundKit.reload(), as on a slot not filled yet.
func _without_takes(slots: Array) -> void:
	for slot: String in slots:
		SoundKit.all_takes().erase(slot)
	SoundKit.forget_files()


func _test_credits() -> void:
	print("
== the Credits section's sounds (decision 406): each source in play by name, each maker once ==")
	var given := SoundKit.credits()
	_check(str(given.get("summary", "")) == "Sounds: Freesound, Kenney, Sonniss", "summary: %s" % given.get("summary"))
	var entries: Array = given.get("entries", [])
	var urls := {}
	var problems: Array[String] = []
	for entry: Dictionary in entries:
		for key: String in ["title", "by", "license", "url"]:
			if str(entry.get(key, "")) == "":
				problems.append("%s has no %s" % [entry, key])
		if str(entry.get("title", "")).get_extension().to_lower() in ["wav", "mp3", "ogg", "flac"]:
			problems.append("%s keeps its file's extension" % entry.get("title"))
		if urls.has(entry.get("url")):
			problems.append("%s twice" % entry.get("url"))
		urls[entry.get("url")] = true
	_check(not entries.is_empty() and problems.is_empty(), "%d entries, each with a title, maker, licence and page, once%s" % [
		entries.size(), "" if problems.is_empty() else ": " + "; ".join(problems.slice(0, 3))])
	var missing: Array[String] = []
	for slot: String in SoundKit.all_takes():
		for take: Dictionary in SoundKit.takes(slot):
			if str(take.get("license", "")).begins_with("CC BY") and not urls.has(str(take.get("url", ""))):
				missing.append(slot)
	_check(missing.is_empty(), "every CC BY take's maker is credited (missing: %s)" % [missing])


func _test_ui_sounds() -> void:
	print("
== UI sounds: buttons click and tick as they come, sliders click when let go, watched panels open and shut ==")
	var sfx := Sfx.new()
	add_child(sfx)
	var ui := UiSounds.new()
	ui.sfx_of = func() -> Sfx: return sfx
	add_child(ui)
	ui._quiet_until = 0
	var button := Button.new()
	add_child(button)
	button.pressed.emit()
	button.mouse_entered.emit()
	button.mouse_entered.emit()
	_check(ui.played == ["ui.click", "ui.hover"], "a button made after it: pressed clicks, hovered ticks, not twice at once (%s)" % [ui.played])
	var slider := HSlider.new()
	add_child(slider)
	slider.drag_ended.emit(true)
	_check(ui.played.back() == "ui.click", "a slider let go clicks")
	var panel := PanelContainer.new()
	add_child(panel)
	ui.watch(panel)
	panel.visible = false
	panel.visible = true
	_check(ui.played.slice(-2) == ["ui.panel_close", "ui.panel_open"], "a watched panel shuts and opens (%s)" % [ui.played.slice(-2)])
	_check(sfx.played.size() == ui.played.size() and sfx.played.all(func(entry: Array) -> bool: return entry[2] == "UI"),
			"each played on the UI bus")
	ui._quiet_until = Time.get_ticks_msec() + 10000
	var before := ui.played.size()
	button.pressed.emit()
	_check(ui.played.size() == before, "nothing while the menus are being built")
	# 804, sound's side: ui's reward cues, each on the UI bus, everywhere,
	# under ui.notify (heard a dozen times running), three takes of its own.
	var rewards: Array[String] = []
	for kind: String in ["gain", "step", "want", "coin", "catch", "found", "need"]:
		var slot := "ui.reward_" + kind
		if SoundKit.bus(slot) != "ui" or SoundKit.positional(slot) or SoundKit.volume_db(slot) >= SoundKit.volume_db("ui.notify") \
				or SoundKit.takes(slot).size() < 3:
			rewards.append(slot)
	_check(rewards.is_empty(), "each reward cue on the UI bus, not placed, under ui.notify, three takes (%s)" % [rewards])
	# 805 amended (4): items' fishing cues, placed at the float, heard near,
	# never by monsters, two takes or more.
	var fishing: Array[String] = []
	for kind: String in ["cast", "plop", "bite", "landed"]:
		var slot := "sfx.fish_" + kind
		if SoundKit.bus(slot) != "sfx" or not SoundKit.positional(slot) or SoundKit.noise(slot) != "" \
				or SoundKit.reach(slot) > 12 or SoundKit.takes(slot).size() < 2:
			fishing.append(slot)
	_check(fishing.is_empty(), "each fishing cue placed on the sfx bus, no noise, heard within 12, two takes (%s)" % [fishing])
	# 813 amended: the family tomb's wall heard like a door, falling
	# back to the slab's grind; its plates a close click no monster hears.
	_check(SoundKit.positional("sfx.wall_sink") and SoundKit.noise("sfx.wall_sink") == "door"
			and str(SoundKit.spec("sfx.wall_sink").get("fallback", "")) == "sfx.slab_grind" and SoundKit.takes("sfx.wall_sink").size() >= 3
			and SoundKit.positional("sfx.plate_click") and SoundKit.noise("sfx.plate_click") == ""
			and SoundKit.reach("sfx.plate_click") <= 6 and SoundKit.takes("sfx.plate_click").size() >= 3,
			"the tomb's wall sinks like a door, else the slab; its plates click close, unheard by monsters")
	for node: Node in [button, slider, panel, ui, sfx]:
		node.queue_free()
	await get_tree().process_frame


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
