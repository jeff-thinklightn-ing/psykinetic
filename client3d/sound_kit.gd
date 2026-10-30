class_name SoundKit
extends RefCounted
## The game's sounds, by slot: everything the game plays is a named slot in
## art/audio/slots.json (its bus, how far it carries and whether monsters
## hear it, where it is played and where its takes came from), and
## SoundKit.streams(slot) is how Sfx gets one. A slot is played from, in
## order:
##
## - its own takes: art/audio/<category>/<slot>/<slot>.ogg (more takes
##   <slot>.2.ogg, <slot>.3.ogg ...; .wav too), its "source" saying whose;
## - else its third-party takes, listed in art/audio/takes.json (written by
##   tools/sound_take.ps1): each a file cut from a source the manifest
##   names, with its original and its sha256. A source stored "external"
##   (the Sonniss bundles, whose licence forbids sharing the files) keeps
##   its takes outside the repo, in the sound library's takes/ folder,
##   copied into art/audio/external/ (git ignores it) by
##   tools/sound_sync.ps1; until they are copied there, the slot plays as
##   if it had none;
## - else its fill: files of a third-party source the manifest names (today
##   Kenney's two CC0 packs, in art/audio/sfx/);
## - else its fallback, another slot (a footstep on grass sounds as the
##   generic footstep until it has takes of its own);
## - else a placeholder: a short blip, its pitch by bus, so a gap is heard
##   and not mistaken for a sound (a bed: silence).
##
## A positional slot names the sim's noise kind it goes with ("noise", as
## World.noise makes it): what players hear and what monsters hear come
## from the one radius (NOISES). A slot whose noise is null is not heard by
## monsters; its "range" is how far players hear it.

const MANIFEST := "res://art/audio/slots.json"
const TAKES := "res://art/audio/takes.json"
const ROOT := "res://art/audio/"
const TYPES := ["oneshot", "loop", "bed"]
const BUSES := ["sfx", "ambience", "voice", "ui", "music"]
const EXTENSIONS := ["ogg", "wav"]
## The sim's noises a slot may name, cells heard (Chebyshev; half with no
## clear line): Senses' own radii, so a sound carries as far for players as
## for monsters. A footstep's is the body's (Senses.step_radius) where the
## body is known.
const NOISES := {
	"step": Senses.NOISE_STEP, "speech": Senses.NOISE_SPEECH, "shout": Senses.NOISE_SHOUT,
	"whisper": Senses.NOISE_WHISPER, "fight": Senses.NOISE_FIGHT, "door": Senses.NOISE_DOOR,
	"door_struck": Senses.NOISE_DOOR_STRUCK, "door_broken": Senses.NOISE_DOOR_BROKEN,
	"door_rattle": Senses.NOISE_RATTLE, "latch": Senses.NOISE_LATCH, "rummage": Senses.NOISE_RUMMAGE,
	"break": Senses.NOISE_BREAK, "thud_light": Senses.NOISE_THUD_LIGHT, "thud_heavy": Senses.NOISE_THUD_HEAVY,
	"call": Senses.NOISE_CALL, "rout": Senses.NOISE_ROUT, "charge": Animal.NOISE_CHARGE,
	"bow": preload("res://sim/world.gd").NOISE_BOW,
}
## A slot's noise that is one radius of a sim kind: the kind World.noise
## makes for it.
const NOISE_KINDS := {"thud_light": "thud", "thud_heavy": "thud"}
## The placeholder blip: its pitch by bus (Hz), how long (s) and how loud.
const PLACEHOLDER_PITCH := {"sfx": 660.0, "voice": 440.0, "ui": 990.0}
const PLACEHOLDER_SECONDS := 0.09
const PLACEHOLDER_DB := -14.0

static var _manifest: Dictionary = {}
static var _takes: Dictionary = {}
static var _takes_read := false
## Slot -> the files it plays (res:// paths), resolved once.
static var _files: Dictionary[String, Array] = {}
## Slot -> played_from(slot) on disk, resolved once: Music weighs its
## layers by it four times a second (perf: uncached, ResourceLoader.exists
## over every take name cost 2-4 ms a weigh).
static var _played_from: Dictionary[String, String] = {}
static var _placeholders: Dictionary[String, AudioStreamWAV] = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		# The server's export leaves art/audio out, and the Credits still ask (decision 406).
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else {}
		_manifest = parsed if parsed is Dictionary and not parsed.is_empty() else {"slots": {}}
	return _manifest


## Slot -> its third-party takes ({file, from, original, sha256, ...} each),
## from TAKES.
static func all_takes() -> Dictionary:
	if not _takes_read:
		_takes_read = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TAKES)) if FileAccess.file_exists(TAKES) else {}
		_takes = parsed.get("takes", {}) if parsed is Dictionary else {}
	return _takes


static func slots() -> Dictionary:
	return manifest().get("slots", {})


static func has(slot: String) -> bool:
	return slots().has(slot)


static func spec(slot: String) -> Dictionary:
	return slots().get(slot, {})


static func bus(slot: String) -> String:
	return str(spec(slot).get("bus", "sfx"))


static func volume_db(slot: String) -> float:
	return float(spec(slot).get("volume_db", 0.0))


static func positional(slot: String) -> bool:
	return bool(spec(slot).get("positional", true))


## The noise [param slot] names (a key of NOISES), or "" when monsters do
## not hear it.
static func noise(slot: String) -> String:
	var kind: Variant = spec(slot).get("noise")
	return str(kind) if kind != null else ""


## The sim noise kind [param slot] goes with (World.noise's), or "".
static func noise_kind(slot: String) -> String:
	return str(NOISE_KINDS.get(noise(slot), noise(slot)))


## How far [param slot] is heard, in cells: its noise's radius, else its
## range; 0 for one that is not positional.
static func reach(slot: String) -> int:
	if not positional(slot):
		return 0
	var kind := noise(slot)
	return int(NOISES.get(kind, 0)) if kind != "" else int(spec(slot).get("range", 0))


## Where [param slot]'s own takes go.
static func folder(slot: String) -> String:
	return ROOT + str(spec(slot).get("category", "")) + "/" + slot + "/"


## [param slot]'s own takes on disk: <slot>.ogg, <slot>.2.ogg ... while
## each next one is there.
static func own_files(slot: String) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, 100):
		var found := ""
		for extension: String in EXTENSIONS:
			var path := folder(slot) + (slot if i == 1 else "%s.%d" % [slot, i]) + "." + extension
			if ResourceLoader.exists(path):
				found = path
				break
		if found == "":
			break
		out.append(found)
	return out


## [param slot]'s fill files (res:// paths), whether or not they are there.
static func fill_files(slot: String) -> Array[String]:
	var out: Array[String] = []
	var fill: Dictionary = spec(slot).get("fill", {})
	var source: Dictionary = manifest().get("sources", {}).get(str(fill.get("from", "")), {})
	for file: String in fill.get("files", []):
		out.append(str(source.get("path", ROOT)) + file)
	return out


## [param slot]'s third-party takes, as TAKES lists them.
static func takes(slot: String) -> Array:
	return all_takes().get(slot, [])


## The source the manifest names [param key].
static func source(key: String) -> Dictionary:
	return manifest().get("sources", {}).get(key, {})


## Where [param take] of [param slot] is (a res:// path), there or not.
static func take_path(slot: String, take: Dictionary) -> String:
	return str(source(str(take.get("from", ""))).get("path", ROOT)) + slot + "/" + str(take.get("file", ""))


## [param slot]'s third-party take files (res:// paths), whether or not
## they are there (an external one is there once synced).
static func take_files(slot: String) -> Array[String]:
	var out: Array[String] = []
	for take: Dictionary in takes(slot):
		out.append(take_path(slot, take))
	return out


## What [param slot] is filled from, by the manifest and the takes list
## (the same on every machine, synced or not): "own", "fill" (a third
## party's: takes or a fill) or "placeholder" (its fallback's sound or the
## blip).
static func filled_by(slot: String) -> String:
	if not own_files(slot).is_empty():
		return "own"
	if not takes(slot).is_empty():
		return "fill"
	return "fill" if not _existing(fill_files(slot)).is_empty() else "placeholder"


## The slot whose takes [param slot] plays: itself, or the first along its
## fallbacks that has some; "" for none (the placeholder). On disk (the
## default) a slot whose takes are listed but not synced has none; by the
## lists alone (on_disk false: the status) it has them.
static func played_from(slot: String, on_disk := true) -> String:
	if on_disk and _played_from.has(slot):
		return _played_from[slot]
	var found := _resolve_played_from(slot, on_disk)
	if on_disk:
		_played_from[slot] = found
	return found


static func _resolve_played_from(slot: String, on_disk: bool) -> String:
	var seen: Array[String] = []
	var at := slot
	while has(at) and at not in seen:
		var filled := not _playing(at).is_empty() if on_disk else filled_by(at) != "placeholder"
		if filled:
			return at
		seen.append(at)
		at = str(spec(at).get("fallback", ""))
	return ""


## The files [param slot] plays (res:// paths); empty for the placeholder.
static func files(slot: String) -> Array:
	if not _files.has(slot):
		var from := played_from(slot)
		_files[slot] = _playing(from) if from != "" else []
	return _files[slot]


## [param slot]'s own takes there, else its third-party takes there, else
## its fill there.
static func _playing(slot: String) -> Array[String]:
	var found := own_files(slot)
	if found.is_empty():
		found = _existing(take_files(slot))
	if found.is_empty():
		found = _existing(fill_files(slot))
	return found


## Grounds a footstep has its own slots for (others sound as stone).
const STEP_GROUNDS := ["grass", "dirt", "stone", "sand", "water"]
## A body's size for its footsteps, by mass (kg): small under the first,
## large from the second (a sneak is small, a player or a brute medium).
const STEP_MASS := [50.0, 100.0]


## An animal's feet (enemy-ai's kinds), for its footsteps.
const FEET := {"deer": "hooves", "stag": "hooves", "boar": "hooves", "rabbit": "paws", "wolf": "claws"}


## The footstep slot for a body of [param mass] on [param ground] (a floor
## kind, or "water"); an animal of [param creature] kind (FEET) steps on its
## own feet, whatever the ground.
static func footstep(ground: String, mass: float, creature := "") -> String:
	if FEET.has(creature):
		return "sfx.footstep_%s" % FEET[creature]
	var size := "small" if mass < STEP_MASS[0] else "medium" if mass < STEP_MASS[1] else "large"
	return "sfx.footstep_%s_%s" % [ground if ground in STEP_GROUNDS else "stone", size]


## The monster kinds that are goblins (and one of no kind), whose cries
## are the goblin's slots, pitched by size: an imp high, a brute low.
const GOBLINS := ["", "imp", "brute", "sneak"]
const CREATURE_PITCH := {"imp": 1.15, "brute": 0.8, "sneak": 1.05}
## The slot a blow lands with, by the weapon [param id] it was struck with
## (World.wielded): bare hands a fist's, a blunt weapon (Items' blunt) a
## blunt one's, any other weapon a blade's; on flesh, or on metal where the
## one struck wears [param armour] (its armour's look, Items.armour_of) of
## ARMOUR_STRUCK, where bare hands knock as a blunt weapon does.
static func hit(id: String, armour := "") -> String:
	var bare := id == "" or Items.verb_of(id).is_empty()
	if armour in ARMOUR_STRUCK:
		return "sfx.hit_blunt_armor" if bare or bool(Items.def(id).get("blunt", false)) else "sfx.hit_blade_armor"
	if bare:
		return "sfx.hit_fist_flesh"
	return "sfx.hit_blunt_flesh" if bool(Items.def(id).get("blunt", false)) else "sfx.hit_blade_flesh"


## The armour looks a blow is heard on as metal (hit); leather and robes
## are heard as flesh.
const ARMOUR_STRUCK: Array[String] = ["plate", "mail"]


## The look of the armour [param entity] wears (its worn, a player's or
## companion's; Items.armour_of), "" for none or anyone else.
static func armour_look(entity: Object) -> String:
	var worn: Variant = entity.get("worn") if entity != null else null
	return str(Items.armour_of(worn).get("look", "")) if worn is String else ""


## The slot a blow taken on a guard makes: a shield's (Items tag shield)
## knock, else a weapon's parry.
static func block(guard_id: String) -> String:
	return "sfx.block_shield" if guard_id != "" and Items.has_tag(guard_id, "shield") else "sfx.block_weapon"


## A swing's slot: a two-handed weapon's heavier whoosh.
static func swing(id: String) -> String:
	return "sfx.swing_heavy" if id != "" and int(Items.def(id).get("hands", 1)) >= 2 and not Items.verb_of(id).is_empty() 			and str(Items.verb_of(id).get("kind", "")) != "ranged" else "sfx.swing"


## Items whose rest is a scabbard: their drawing and sheathing are a blade's.
const BLADES: Array[String] = ["knife", "dagger", "sword"]


## The slot for item [param id] going to its rest or, [param drawing], taken up
## from it (662, pc-character's rest poses): a blade's draw or sheathe, else
## gear's (a shield, spear, axe ...) draw or stow.
static func stow_slot(id: String, drawing: bool) -> String:
	if id in BLADES:
		return "sfx.blade_draw" if drawing else "sfx.blade_sheathe"
	return "sfx.gear_draw" if drawing else "sfx.gear_stow"


## Worn armour's slot by its noise kind (676 1b, World.armour_noise): plate's
## clank, mail's jingle; "" for none (leather, robes, nothing worn).
const ARMOUR_SLOTS: Dictionary[String, String] = {"plate": "sfx.armour_plate", "mail": "sfx.armour_mail"}
## Each kind's radius at a walk with physics' first knobs (plate 20 kg x 0.25,
## mail 10 kg x 0.2): its slot's own loudness. A step carrying twice as far
## is ARMOUR_DB_PER_DOUBLING louder, within ARMOUR_DB_RANGE.
const ARMOUR_WALK_RADIUS: Dictionary[String, float] = {"plate": 5.0, "mail": 2.0}
const ARMOUR_DB_PER_DOUBLING := 6.0
const ARMOUR_DB_RANGE := Vector2(-12.0, 6.0)
## A step this long after the last (s) or more starts from standing: heard
## at a walk.
const ARMOUR_STANDING := 1.0


static func armour_slot(kind: String) -> String:
	return ARMOUR_SLOTS.get(kind, "")


## dB over [param kind]'s slot for a step whose clank carries [param radius]
## cells (World.armour_noise): 0 at its walk's radius, louder as it carries
## further (a run, a heavier piece, physics' clank knobs turned up).
static func armour_db(kind: String, radius: int) -> float:
	var walk: float = ARMOUR_WALK_RADIUS.get(kind, 0.0)
	if walk <= 0.0 or radius <= 0:
		return ARMOUR_DB_RANGE.x
	return clampf(ARMOUR_DB_PER_DOUBLING * log(radius / walk) / log(2.0), ARMOUR_DB_RANGE.x, ARMOUR_DB_RANGE.y)


## A step's pace as the server reckons it (World.armour_noise: a walk 1, to
## 2) from [param seconds] since the body's last step as the client saw it;
## a first step, or one after standing, a walk.
static func step_pace(seconds: float) -> float:
	if seconds <= 0.0 or seconds >= ARMOUR_STANDING:
		return 1.0
	return clampf(World.CLANK_WALK_TICKS / (seconds * World.TICK_RATE), 0.0, 2.0)


## A person's voice slot for [param what] (effort_swing, effort_hurt,
## effort_lift, death), by its body (Player.body, Companion.body: male or
## female; decision 388), or [param body] for a monster drawn as a person
## (its look's, Client3D.person_words: a grave robber); "" for anyone else.
static func voice(entity: Object, what: String, body := &"") -> String:
	if entity is Player or entity is Companion:
		return "voice.%s_%s" % [what, "female" if entity.get("body") == &"female" else "male"]
	if body in [&"male", &"female"]:
		return "voice.%s_%s" % [what, body]
	return ""


## The slot a line of speech (the "speech" message) sounds as it is shown, ""
## for none: the draugr laughs as he turns on a refusal (735; Jeff: he "laughs
## as he attacks you"). The line is his own constant, so the server and this
## build agree; an older server's reworded line just goes unlaughed.
static func speech(entity: Object, text: String) -> String:
	return "voice.draugr_laugh" if entity is Draugr and text == Draugr.REFUSED else ""


## A cry (Monster.cried) -> the part of its slot's name after the creature;
## a creature's own name for one first (a wolf's call is its howl).
const CRIES := {"call": "alert", "rout": "rout"}
const OWN_CRIES := {"wolf": {"call": "howl"}, "deer": {"suspicious": "snort"}}
## A kind that sounds as another (a stag as a deer).
const SOUNDS_AS := {"stag": "deer"}


## The name a [param creature] (a monster's kind) goes by in slot names:
## "goblin" for the goblins, else its own or SOUNDS_AS's.
static func creature_slot_name(creature: String) -> String:
	return "goblin" if creature in GOBLINS else str(SOUNDS_AS.get(creature, creature))


## The slot for a [param creature] (a monster's kind) crying
## [param cry_kind] (Monster.cried's kind): "" when there is none.
static func cry(creature: String, cry_kind: String) -> String:
	var own: Dictionary = OWN_CRIES.get(creature_slot_name(creature), {})
	var slot := "sfx.%s_%s" % [creature_slot_name(creature), own.get(cry_kind, CRIES.get(cry_kind, cry_kind))]
	return slot if has(slot) else ""


## The slot for a [param creature] (a monster's kind) dying: its own, else
## the goblin's.
static func death(creature: String) -> String:
	var slot := "sfx.%s_death" % creature_slot_name(creature)
	return slot if has(slot) else "sfx.goblin_death"


## The slot for [param entity], a breakable thing, broken: a crate's or
## cart's smash, else wood breaking.
static func breaking(entity: GridEntity) -> String:
	return "sfx.crate_break" if str(entity.spawn_spec.get("art", "")) in ["prop.crate", "prop.cart"] else "sfx.break_wood"


## The slot for opening [param entity]'s slots: a chest's lid, a crate's or
## cart's (Cargo), else a pack's leather.
static func opening(entity: GridEntity) -> String:
	if entity is Chest:
		return "sfx.chest_open"
	return "sfx.crate_open" if entity is Cargo else "sfx.pack_open"


## The slot [param entity]'s row shuts with as the pack panel lets it go:
## a chest's lid, "" for anything else.
static func closing(entity: GridEntity) -> String:
	return "sfx.chest_close" if entity is Chest else ""


## A thing of [param id] put down, picked up, or thrown and landing
## ([param what]: "drop", "pickup", "land"): light under World.THUD_HEAVY_KG,
## heavy from it (the sim's thud noises split there too).
static func handled(id: String, what: String) -> String:
	var weight := "heavy" if Items.weight_of(id) >= World.THUD_HEAVY_KG else "light"
	match what:
		"pickup":
			return "sfx.item_pickup_" + weight
		"land":
			return "sfx.thrown_land_" + weight
	return "sfx.item_drop_" + weight


## The sounds' credits for the game's Credits (decision 406):
## {summary: "Sounds: <each source a slot plays from now, by name>",
##  entries: [{title, by, license, url}] each sound a take was cut from that
##  has a maker (Freesound's: CC BY asks it, CC0 has it too), once however
##  many takes it gave}.
static func credits() -> Dictionary:
	var sources: Dictionary = manifest().get("sources", {})
	var all := slots().keys()
	all.sort()
	var used: Array[String] = []
	for name: String in sources:
		for slot: String in all:
			if filled_by(slot) != "placeholder" and name in _sources_of(slot):
				# "Impact Sounds 1.0, Kenney" -> Kenney; "Freesound" as it is.
				var full := str(sources[name].get("name", name))
				var short := full.get_slice(", ", 1) if ", " in full else full
				if short not in used:
					used.append(short)
				break
	used.sort()
	var seen := {}
	var entries: Array[Dictionary] = []
	for slot: String in all:
		for take: Dictionary in takes(slot):
			var url := str(take.get("url", ""))
			if str(take.get("by", "")) == "" or seen.has(url):
				continue
			seen[url] = true
			var original := str(take.get("original", ""))
			var title := original.get_slice(": ", 1) if ": " in original else original
			title = title.get_slice(" (from ", 0)
			# Freesound titles are often file names: "Sword Impact.wav" -> "Sword Impact".
			if title.get_extension().to_lower() in ["wav", "mp3", "ogg", "flac", "aif", "aiff"]:
				title = title.get_basename()
			entries.append({"title": title, "by": str(take["by"]),
				"license": str(take.get("license", source(str(take.get("from", ""))).get("license", "?"))), "url": url})
	return {"summary": "Sounds: " + ", ".join(used), "entries": entries}


## Forget what was resolved (after takes land, for tools and tests).
static func reload() -> void:
	_manifest = {}
	_takes = {}
	_takes_read = false
	forget_files()


## Forget which files each slot plays (after its takes' lists change).
static func forget_files() -> void:
	_files.clear()
	_played_from.clear()


## The blip a slot with no takes plays on [param bus_name] (null for a bed's
## buses: silence).
static func placeholder(bus_name: String) -> AudioStreamWAV:
	if not PLACEHOLDER_PITCH.has(bus_name):
		return null
	if not _placeholders.has(bus_name):
		var rate := 22050
		var count := int(rate * PLACEHOLDER_SECONDS)
		var data := PackedByteArray()
		data.resize(count * 2)
		var gain := db_to_linear(PLACEHOLDER_DB)
		for i in count:
			var t := float(i) / rate
			var sample := sin(TAU * float(PLACEHOLDER_PITCH[bus_name]) * t) * exp(-t * 40.0) * gain
			data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.stereo = false
		stream.data = data
		_placeholders[bus_name] = stream
	return _placeholders[bus_name]


static func _existing(paths: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for path in paths:
		if ResourceLoader.exists(path):
			out.append(path)
	return out


## Problems with the slot folders: a file under art/audio/<category>/ in
## no slot's folder, or named for no take of its slot.
static func check_folders() -> Array[String]:
	var problems: Array[String] = []
	var categories := {}
	for slot: String in slots():
		categories[str(spec(slot).get("category", ""))] = true
	for category: String in categories:
		var base := ROOT + category + "/"
		if not DirAccess.dir_exists_absolute(base):
			continue
		for name in DirAccess.get_directories_at(base):
			if not has(name) or str(spec(name).get("category")) != category:
				problems.append("%s%s/: no slot %s in %s" % [base, name, name, category])
				continue
			var takes := own_files(name)
			for file in DirAccess.get_files_at(base + name):
				if file.get_extension() in ["import", "uid", "txt", "md"]:
					continue
				if base + name + "/" + file not in takes:
					problems.append("%s%s/%s: not a take of %s (%s.ogg, %s.2.ogg ...)" % [base, name, file, name, name, name])
	return problems


# --- docs/sound_status.md and THIRD_PARTY.md ----------------------------------

const THIRD_PARTY_BEGIN := "<!-- sound slots: written by tools/sound_status.gd from art/audio/slots.json; edit there -->"
const THIRD_PARTY_END := "<!-- end of sound slots -->"


## docs/sound_status.md as it should read now: every slot by what it plays
## from, the placeholders first (tools/sound_status.gd writes it;
## sound_kit_test fails while it is out of date).
static func status_markdown() -> String:
	var groups := {"placeholder": [], "fill": [], "own": []}
	var names := slots().keys()
	names.sort()
	for slot: String in names:
		groups[filled_by(slot)].append(slot)
	var unheard: Array[String] = []
	for slot: String in names:
		if positional(slot) and noise(slot) == "":
			unheard.append(slot)
	var lines: Array[String] = [
		"# Sound slots: what each plays from",
		"",
		"Generated by `tools/sound_status.gd` from `art/audio/slots.json` and the slot folders; run",
		"it after sounds land. %d slots: %d with takes of their own, %d from a third-party fill," % [
			names.size(), groups.own.size(), groups.fill.size()],
		"%d placeholders. How slots are played is in `client3d/sound_kit.gd`." % groups.placeholder.size(),
		"",
		"## Placeholders remaining",
		"",
		"No takes: played as its fallback's sound where it has one, else as a blip (a bed: silence).",
		"",
		"| Slot | Type | Bus | Heard | Meanwhile | Used for |",
		"|------|------|-----|-------|-----------|----------|",
	]
	for slot: String in groups.placeholder:
		var from := played_from(slot, false)
		var meanwhile := ("`%s`" % from) if from != "" else ("silence" if placeholder(bus(slot)) == null else "blip")
		lines.append(_row(slot, [_type(slot), bus(slot), _heard(slot), meanwhile, _uses(slot)]))
	lines.append_array(["", "## Third-party fills to replace", "",
		"| Slot | Takes | Heard | From | Licence |", "|------|-------|-------|------|---------|"])
	for slot: String in groups.fill:
		var from_names: Array[String] = []
		var licenses: Array[String] = []
		for key in _sources_of(slot):
			if str(source(key).get("name", key)) not in from_names:
				from_names.append(str(source(key).get("name", key)))
			if str(source(key).get("license", "?")) not in licenses:
				licenses.append(str(source(key).get("license", "?")))
		var count := takes(slot).size() if not takes(slot).is_empty() else fill_files(slot).size()
		lines.append(_row(slot, [str(count), _heard(slot), ", ".join(from_names), ", ".join(licenses)]))
	lines.append_array(["", "## Own takes", "", "| Slot | Takes | By | Licence | Date |", "|------|-------|----|---------|------|"])
	for slot: String in groups.own:
		var source: Dictionary = spec(slot).get("source", {})
		lines.append(_row(slot, [str(own_files(slot).size()), str(source.get("by", "?")), str(source.get("license", "?")), str(source.get("date", ""))]))
	lines.append_array(["", "## Not heard by monsters", "",
		"Positional slots with no sim noise: players hear them (range in cells), monsters do not.", "",
		", ".join(unheard.map(func(slot: String) -> String: return "`%s` (%d)" % [slot, reach(slot)]))])
	return "\n".join(lines) + "\n"


## THIRD_PARTY.md's sound slot block as it should read now: each
## third-party source the manifest names, and the slots played from it.
static func third_party_block() -> String:
	var lines: Array[String] = [THIRD_PARTY_BEGIN, "", "| Source | Licence | Where | Slots played from it |", "|--------|---------|-------|----------------------|"]
	var sources: Dictionary = manifest().get("sources", {})
	var names := sources.keys()
	names.sort()
	var all := slots().keys()
	all.sort()
	for name: String in names:
		var from: Dictionary = sources[name]
		var played: Array[String] = []
		for slot: String in all:
			if filled_by(slot) == "fill" and name in _sources_of(slot):
				played.append(slot)
		var path := str(from.get("path", "")).trim_prefix("res://")
		var where := ("outside the repo (the sound library's `takes/`), copied to `%s` by `tools/sound_sync.ps1`" % path) if str(from.get("store", "")) == "external" else "`%s`" % path
		lines.append("| [%s](%s) | %s (`%s`) | %s | %s |" % [from.get("name", name), from.get("url", ""), from.get("license", "?"),
			from.get("license_file", ""), where, ", ".join(played) if not played.is_empty() else "none now"])
	var own: Array[String] = []
	for slot: String in all:
		var by := str(spec(slot).get("source", {}).get("by", ""))
		if filled_by(slot) == "own" and by != "" and not by.to_lower().begins_with("jeff"):
			own.append("%s (%s, %s)" % [slot, by, spec(slot)["source"].get("license", "?")])
	lines.append("")
	lines.append("Slots whose own takes came from someone else: %s." % (", ".join(own) if not own.is_empty() else "none"))
	var credits: Array[String] = []
	for slot: String in all:
		for take: Dictionary in takes(slot):
			if str(take.get("by", "")) != "":
				credits.append("- `%s` (%s): cut from [%s](%s) by %s, %s" % [slot, take.get("file", ""), str(take.get("original", "")).replace("[", "(").replace("]", ")"),
					take.get("url", ""), take.get("by", ""), take.get("license", source(str(take.get("from", ""))).get("license", "?"))])
	if not credits.is_empty():
		lines.append("")
		lines.append("Takes credited to their makers:")
		lines.append("")
		lines.append_array(credits)
	lines.append("")
	lines.append(THIRD_PARTY_END)
	return "\n".join(lines)


## The sources [param slot] is filled from: its takes', else its fill's.
static func _sources_of(slot: String) -> Array[String]:
	var out: Array[String] = []
	for take: Dictionary in takes(slot):
		if str(take.get("from", "")) not in out:
			out.append(str(take.get("from", "")))
	if out.is_empty() and spec(slot).has("fill"):
		out.append(str(spec(slot)["fill"].get("from", "")))
	return out


static func _row(slot: String, cells: Array) -> String:
	return "| `%s` | %s |" % [slot, " | ".join(cells.map(func(cell: Variant) -> String: return str(cell).replace("|", "/")))]


static func _type(slot: String) -> String:
	return str(spec(slot).get("type", "")) + ("" if positional(slot) else ", flat")


static func _heard(slot: String) -> String:
	if not positional(slot):
		return ""
	return "%s %d" % [noise(slot), reach(slot)] if noise(slot) != "" else "players %d" % reach(slot)


static func _uses(slot: String) -> String:
	var uses := str(spec(slot).get("uses", ""))
	return uses if uses.length() <= 90 else uses.left(87) + "..."
