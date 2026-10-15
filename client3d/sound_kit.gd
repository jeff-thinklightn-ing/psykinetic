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
const ROOT := "res://art/audio/"
const TYPES := ["oneshot", "loop", "bed"]
const BUSES := ["sfx", "ambience", "voice", "ui", "music"]
const EXTENSIONS := ["ogg", "wav"]
## The sim's noise kinds, cells heard (Chebyshev; half with no clear line).
## The first are Senses' own; the rest enemy-ai agreed for sounds the sim
## does not make yet, and move to Senses when it does.
const NOISES := {
	"step": Senses.NOISE_STEP, "speech": Senses.NOISE_SPEECH, "shout": Senses.NOISE_SHOUT,
	"whisper": Senses.NOISE_WHISPER, "fight": Senses.NOISE_FIGHT, "door": Senses.NOISE_DOOR,
	"door_struck": Senses.NOISE_DOOR_STRUCK, "door_broken": Senses.NOISE_DOOR_BROKEN,
	"thud": 4, "rummage": 4, "break": 8, "latch": 3, "door_rattle": 6,
}
## The placeholder blip: its pitch by bus (Hz), how long (s) and how loud.
const PLACEHOLDER_PITCH := {"sfx": 660.0, "voice": 440.0, "ui": 990.0}
const PLACEHOLDER_SECONDS := 0.09
const PLACEHOLDER_DB := -14.0

static var _manifest: Dictionary = {}
## Slot -> the files it plays (res:// paths), resolved once.
static var _files: Dictionary[String, Array] = {}
static var _placeholders: Dictionary[String, AudioStreamWAV] = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		_manifest = parsed if parsed is Dictionary else {"slots": {}}
	return _manifest


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


## The sim noise kind [param slot] goes with, or "" when monsters do not
## hear it.
static func noise(slot: String) -> String:
	var kind: Variant = spec(slot).get("noise")
	return str(kind) if kind != null else ""


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


## What [param slot] plays from now: "own", "fill" (a third party's) or
## "placeholder" (its fallback's sound or the blip).
static func filled_by(slot: String) -> String:
	if not own_files(slot).is_empty():
		return "own"
	return "fill" if not _existing(fill_files(slot)).is_empty() else "placeholder"


## The slot whose takes [param slot] plays: itself, or the first along its
## fallbacks that has some; "" for none (the placeholder).
static func played_from(slot: String) -> String:
	var seen: Array[String] = []
	var at := slot
	while has(at) and at not in seen:
		if filled_by(at) != "placeholder":
			return at
		seen.append(at)
		at = str(spec(at).get("fallback", ""))
	return ""


## The files [param slot] plays (res:// paths); empty for the placeholder.
static func files(slot: String) -> Array:
	if not _files.has(slot):
		var from := played_from(slot)
		var found: Array[String] = []
		if from != "":
			found = own_files(from)
			if found.is_empty():
				found = _existing(fill_files(from))
		_files[slot] = found
	return _files[slot]


## The slot for opening [param entity]'s slots: a chest's lid, a crate's or
## cart's (Cargo), else a pack's leather.
static func opening(entity: GridEntity) -> String:
	if entity is Chest:
		return "sfx.chest_open"
	return "sfx.crate_open" if entity is Cargo else "sfx.pack_open"


## Forget what was resolved (after takes land, for tools and tests).
static func reload() -> void:
	_manifest = {}
	_files.clear()


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
		var from := played_from(slot)
		var meanwhile := ("`%s`" % from) if from != "" else ("silence" if placeholder(bus(slot)) == null else "blip")
		lines.append(_row(slot, [_type(slot), bus(slot), _heard(slot), meanwhile, _uses(slot)]))
	lines.append_array(["", "## Third-party fills to replace", "",
		"| Slot | Takes | Heard | From | Licence |", "|------|-------|-------|------|---------|"])
	for slot: String in groups.fill:
		var source: Dictionary = manifest().get("sources", {}).get(str(spec(slot)["fill"].get("from", "")), {})
		lines.append(_row(slot, [str(files(slot).size()), _heard(slot), str(source.get("name", "?")), str(source.get("license", "?"))]))
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
		var source: Dictionary = sources[name]
		var played: Array[String] = []
		for slot: String in all:
			if filled_by(slot) == "fill" and str(spec(slot)["fill"].get("from", "")) == name:
				played.append(slot)
		lines.append("| [%s](%s) | %s (`%s`) | `%s` | %s |" % [source.get("name", name), source.get("url", ""), source.get("license", "?"),
			source.get("license_file", ""), str(source.get("path", "")).trim_prefix("res://"), ", ".join(played) if not played.is_empty() else "none now"])
	var own: Array[String] = []
	for slot: String in all:
		var by := str(spec(slot).get("source", {}).get("by", ""))
		if filled_by(slot) == "own" and by != "" and not by.to_lower().begins_with("jeff"):
			own.append("%s (%s, %s)" % [slot, by, spec(slot)["source"].get("license", "?")])
	lines.append("")
	lines.append("Slots whose own takes came from someone else: %s." % (", ".join(own) if not own.is_empty() else "none"))
	lines.append("")
	lines.append(THIRD_PARTY_END)
	return "\n".join(lines)


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
