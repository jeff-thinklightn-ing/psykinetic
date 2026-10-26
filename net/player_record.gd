class_name PlayerRecord
extends RefCounted
## What the server remembers about a player between sessions, keyed by the
## player_id the client keeps in its settings.cfg. Saved in the snapshot.

var player_id := ""
## Join order on this server, from 1. Gives the entity its node name
## ("Player3") and its colour, and never changes.
var index := 0
var name := "Player"
## The body the player wears (Net.BODIES; decision 388): what they asked for
## at their last join.
var body: StringName = &"male"
## The look they chose beside it (Net.tidy_look's words; decision 439), as
## they asked at their last join; "" for none chosen (seeded by their name).
var look := ""
var tile := Vector2i.ZERO
var hp := 0
var stamina := 0
var facing := Vector2i(0, 1)
var color := Color.WHITE
## The zone (map) the player is in: where they come back to.
var zone := ""
## Unix time of the last join or leave.
var last_seen := 0
## The player's companion: {name, card, hp, stamina, tile: [x, y], alive,
## said: her last lines, newest last, slots: her pack, traits (rolled:
## CompanionCard), how_we_met, card_by ("plain" or "model"), facts and
## beliefs (CompanionFacts), talk (not yet read for them), and resident while
## she stays in a town working: {place, zone, trade} (decision 284), and
## taken while raiders hold her: {by: the group's id, zone, at: the world
## step} (decision 314)}.
## Empty until one has been given. A tile of null means beside its owner.
var companion: Dictionary = {}
## Her traits that are tables, not words: her look (293 amended) and her
## leanings (442).
const TABLE_TRAITS: Array[String] = ["look", "leanings"]
## The commissions and errands they took on from the town's people (decision
## 435): the asks as the residents' cards hold them, by id.
var commissions: Array = []
## What is in the player's slots (Items ids, "" empty), kept through
## death, travel and leaving.
var slots := Items.tidy([], Player.SLOTS)
## The instance in each slot (ItemBook uids, 0 none), beside slots.
var slot_items := PackedInt32Array()
## The areas they have stood in and the places they have come within sight
## of (decision 446, WorldNews), sorted: what their world map shows.
var known_areas: Array[String] = []
var known_places: Array[String] = []
## The generation of each regenerating area they were last in (decision
## 465), area -> n: coming back to a newer one is told "The ways have
## shifted since you were last here."
var seen_generation: Dictionary = {}
## The marks on them (decision 540), sorted words a sealed link reads
## (level.json link "sealed": the mark it opens for): "draugr" once the
## draugr is beaten (enemy-ai's call to Main.mark_player).
var marks: Array[String] = []
## The draugr's blessing (decisions 544, 573): {tokens, best, containers},
## the resurrection charges this player holds, the hardest deal they beat
## (their capacity derives from it: Economy.barrow_capacity) and the named
## containers they earned; {} unblessed. A record from before 573 ({uses,
## of, difficulty, day}) is migrated on load (Economy.barrow_migrated).
var barrow: Dictionary = {}
## The healer's care (decision 584 amended): healer's hut place id -> the
## way in ("gold", "herbs", "antlers": the bypass, handed at his hut;
## "quest": his first errand, npc's). A hut brings back only a player in
## its care.
var care: Dictionary = {}
## The draugr's deals this player paid for and has not yet won (548 amended;
## Jeff: "as long as you paid once you get unlimited attempts"): his zone ->
## {level ("easy" | "normal" | "hard"), paid_step (World.steps when bought)}.
## Kept when the pact is lost, erased when he yields; the draugr reads and
## writes it through World.paid_deal and World.deal_paid (Main's).
var paid_deals: Dictionary = {}
## The levels a paid deal may name (Draugr.SCALE's).
const PAID_LEVELS: Array[String] = ["easy", "normal", "hard"]
## The tally toward that care (584 amended (2); the pack holds four and
## nothing stacks): hut place id -> {herbs, antlers: handed so far toward
## the way in; brew_herbs, brew_antlers: toward npc's brew}, each cleared
## when its count is met.
var care_given: Dictionary = {}
## The caches they have searched (decision 599: Chest.cache, a loot
## table's name): each gives a player its find once.
var caches: Array[String] = []


## Copies the live state off the player's entity.
func remember(entity: GridEntity) -> void:
	tile = entity.tile
	if not entity.zone.is_empty():
		zone = entity.zone
	hp = entity.hp
	stamina = entity.stamina
	facing = entity.facing
	slots = entity.slots.duplicate()
	slot_items = World.slot_uids(entity)
	last_seen = int(Time.get_unix_time_from_system())


func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"index": index,
		"name": name,
		"body": String(body),
		"look": look,
		"tile": [tile.x, tile.y],
		"hp": hp,
		"stamina": stamina,
		"facing": [facing.x, facing.y],
		"color": color.to_html(false),
		"zone": zone,
		"last_seen": last_seen,
		"companion": companion.duplicate(true),
		"commissions": commissions.duplicate(true),
		"slots": Array(slots),
		"items": Array(slot_items),
		"known_areas": known_areas.duplicate(),
		"known_places": known_places.duplicate(),
		"seen_generation": seen_generation.duplicate(),
		"marks": marks.duplicate(),
		"barrow": barrow.duplicate(),
		"care": care.duplicate(),
		"care_given": care_given.duplicate(true),
		"paid_deals": paid_deals.duplicate(true),
		"caches": caches.duplicate(),
	}


## Null if the entry is not a usable record.
static func from_dict(entry: Variant) -> PlayerRecord:
	if entry is not Dictionary or entry.get("player_id") is not String or entry["player_id"].is_empty():
		return null
	var tile_value: Variant = Snapshot.vector(entry.get("tile"))
	if tile_value == null:
		return null
	var record := PlayerRecord.new()
	record.player_id = entry["player_id"]
	record.index = int(entry.get("index", 0))
	record.name = str(entry.get("name", "Player"))
	record.body = Net.tidy_body(entry.get("body", ""))  # Older snapshots have none: male.
	record.look = Net.tidy_look(entry.get("look", ""))  # Nor a look: seeded by name.
	record.tile = tile_value
	record.hp = int(entry.get("hp", 0))
	record.stamina = int(entry.get("stamina", 0))
	var facing_value: Variant = Snapshot.vector(entry.get("facing"))
	record.facing = facing_value if facing_value != null else Vector2i(0, 1)
	var html: String = str(entry.get("color", ""))
	record.color = Color.html(html) if Color.html_is_valid(html) else Color.WHITE
	record.last_seen = int(entry.get("last_seen", 0))
	record.zone = str(entry.get("zone", ""))
	record.slots = Items.tidy(entry.get("slots", []), Player.SLOTS)
	record.slot_items = _uids(entry.get("items", []))
	record.known_areas = _strings(entry.get("known_areas", []))
	record.known_places = _strings(entry.get("known_places", []))
	record.marks = _strings(entry.get("marks", []))
	record.caches = _strings(entry.get("caches", []))
	var barrow: Variant = entry.get("barrow", {})
	if barrow is Dictionary and not barrow.is_empty():
		record.barrow = Economy.barrow_migrated(barrow)
	var cared: Variant = entry.get("care", {})
	if cared is Dictionary:
		for place: Variant in cared:
			if str(cared[place]) in Economy.CARE_WAYS:
				record.care[str(place)] = str(cared[place])
	var paid: Variant = entry.get("paid_deals", {})
	if paid is Dictionary:
		for zone_name: Variant in paid:
			var deal: Variant = paid[zone_name]
			if deal is Dictionary and str(deal.get("level", "")) in PAID_LEVELS:
				record.paid_deals[str(zone_name)] = {"level": str(deal["level"]), "paid_step": int(deal.get("paid_step", 0))}
	var tallies: Variant = entry.get("care_given", {})
	if tallies is Dictionary:
		for place: Variant in tallies:
			if tallies[place] is Dictionary:
				var mine := {}
				for key: Variant in tallies[place]:
					if int(tallies[place][key]) > 0:
						mine[str(key)] = int(tallies[place][key])
				if not mine.is_empty():
					record.care_given[str(place)] = mine
	var seen: Variant = entry.get("seen_generation", {})
	if seen is Dictionary:
		for area: Variant in seen:
			if seen[area] is float or seen[area] is int:
				record.seen_generation[str(area)] = int(seen[area])
	var asks: Variant = entry.get("commissions", [])
	record.commissions = asks.duplicate(true) if asks is Array else []
	var pet: Variant = entry.get("companion", {})
	if pet is Dictionary and pet.get("name") is String:
		record.companion = {
			"name": str(pet["name"]),
			"card": str(pet.get("card", "")),
			"hp": int(pet.get("hp", 0)),
			"stamina": int(pet.get("stamina", 0)),
			"tile": pet.get("tile"),
			"alive": bool(pet.get("alive", true)),
			"said": _lines(pet.get("said", [])),
			"slots": Array(Items.tidy(pet.get("slots", []), Companion.SLOTS)),
			"items": Array(_uids(pet.get("items", []))),
		}
		var traits: Variant = pet.get("traits")
		if traits is Dictionary and not traits.is_empty():
			var kept := {}
			for key: Variant in traits:
				# Her look and leanings are tables of their own (293
				# amended, 442); every other trait is a word. One loaded
				# before this kept them as text: read back as a table.
				var value: Variant = traits[key]
				if value is String and str(key) in TABLE_TRAITS:
					value = JSON.parse_string(value) if value.begins_with("{") else null
					if not value is Dictionary:
						continue  # Not a table: her seed's again (CompanionCard.look_of, leaning).
				# A number stays one (her justice, 581 amended); a word, a word.
				kept[str(key)] = value.duplicate(true) if value is Dictionary else int(value) if value is float or value is int else str(value)
			record.companion["traits"] = kept
			record.companion["how_we_met"] = str(pet.get("how_we_met", ""))
			record.companion["card_by"] = str(pet.get("card_by", "plain"))
		# What has become true of her (decision 294), and talk not yet read for it.
		var grown := CompanionFacts.from_record(pet.get("facts", []), pet.get("beliefs", []))
		if not grown.facts.is_empty() or not grown.beliefs.is_empty():
			record.companion["facts"] = grown.facts
			record.companion["beliefs"] = grown.beliefs
		var talk: Variant = pet.get("talk", [])
		if talk is Array and not talk.is_empty():
			record.companion["talk"] = Array(talk.map(func(line: Variant) -> String: return str(line)))
		var resident: Variant = pet.get("resident")
		if resident is Dictionary and str(resident.get("place", "")) != "" and str(resident.get("zone", "")) != "":
			record.companion["resident"] = {"place": str(resident["place"]), "zone": str(resident["zone"]),
				"trade": str(resident.get("trade", ""))}
		var taken: Variant = pet.get("taken")
		if taken is Dictionary and str(taken.get("by", "")) != "":
			record.companion["taken"] = {"by": str(taken["by"]), "zone": str(taken.get("zone", "")), "at": int(taken.get("at", 0))}
		# Her home town (381) and what she has heard (442): kept through a
		# save, as written (they were dropped on load before).
		var home: Variant = pet.get("home")
		if home is Dictionary and str(home.get("zone", "")) != "":
			record.companion["home"] = {"place": str(home.get("place", "")), "zone": str(home["zone"]), "trade": str(home.get("trade", ""))}
		var heard: Variant = pet.get("heard")
		if heard is Array and not heard.is_empty():
			record.companion["heard"] = heard.filter(func(entry: Variant) -> bool: return entry is Dictionary).duplicate(true)
		# Her bond with her player (444, Standing's entries) and its daily counts.
		var standing: Variant = pet.get("standing")
		if standing is Dictionary and not standing.is_empty():
			record.companion["standing"] = standing.duplicate(true)
		for key: String in ["bond_day", "bond_best"]:
			if pet.get(key) is float or pet.get(key) is int:
				record.companion[key] = int(pet[key])
		# Her tiers' counts (decision 621): the half point carried, the deeds raised today.
		if pet.get("bond_carry") is float or pet.get("bond_carry") is int:
			record.companion["bond_carry"] = float(pet["bond_carry"])
		var games: Variant = pet.get("games")
		if games is Dictionary:
			record.companion["games"] = {"hers": int(games.get("hers", 0)), "theirs": int(games.get("theirs", 0))}
		var said: Variant = pet.get("bond_said")
		if said is Dictionary:
			record.companion["bond_said"] = {"day": int(said.get("day", -1)), "hurt": int(said.get("hurt", 0)), "sorry": int(said.get("sorry", 0))}
		var today: Variant = pet.get("bond_today")
		if today is Dictionary:
			record.companion["bond_today"] = {"day": int(today.get("day", -1)), "deeds": Array(_strings(today.get("deeds", [])))}
		# Her sickness (decision 501, npc's Townsfolk) and one ended, still to be told.
		# Her marks (decision 544: "draugr", the draugr's blessing), as a player's.
		var her_marks := _strings(pet.get("marks", []))
		if not her_marks.is_empty():
			record.companion["marks"] = Array(her_marks)
		for key: String in ["sick", "was_sick"]:
			var sick: Variant = pet.get(key)
			if sick is Dictionary and not sick.is_empty():
				record.companion[key] = _numbers(sick)
		# Her focus (577) and its day's growth, her mood (555), and her
		# leaving (581): gone home, or about to go, and the road she was
		# warned off (581 amended). Dropped on load before: one who left
		# came back with her player after a restart, her focus re-rolled.
		var focus: Variant = pet.get("focus")
		if focus is Dictionary and not focus.is_empty():
			var kinds := {}
			for kind: Variant in focus:
				if focus[kind] is float or focus[kind] is int:
					kinds[str(kind)] = float(focus[kind])
			record.companion["focus"] = kinds
		var focus_day: Variant = pet.get("focus_day")
		if focus_day is Dictionary:
			record.companion["focus_day"] = {"day": int(focus_day.get("day", -1)), "grown": float(focus_day.get("grown", 0.0))}
		for key: String in ["mood", "warned_area"]:
			if pet.get(key) is String and not str(pet[key]).is_empty():
				record.companion[key] = str(pet[key])
		var left: Variant = pet.get("left")
		if left is Dictionary and not left.is_empty():
			record.companion["left"] = _whole(left)
		var parted: Variant = pet.get("parted")
		if parted is Dictionary and not parted.is_empty():
			record.companion["parted"] = _whole(parted)  # Parted as friends (581 amended (3)).
		var leaving: Variant = pet.get("leaving")
		if leaving is Dictionary and not leaving.is_empty():
			# Her walk starts again (Main._leaving_tick): only what she leaves over.
			record.companion["leaving"] = {"deed": str(leaving.get("deed", "")), "why": str(leaving.get("why", "")),
				"day": int(leaving.get("day", 0))}
		# Her roads (decision 551): where she has been with her player, and
		# the dangers she lived through there.
		var roads: Variant = pet.get("roads")
		if roads is Dictionary:
			var dangers: Array = []
			for danger: Variant in roads.get("dangers", []):
				if danger is Dictionary:
					dangers.append(_numbers(danger))
			# The areas she came through safely, and on which day (551 phase 2).
			var passed := {}
			var went: Variant = roads.get("passed", {})
			if went is Dictionary:
				for area: Variant in went:
					if went[area] is float or went[area] is int:
						passed[str(area)] = int(went[area])
			record.companion["roads"] = {"areas": Array(_strings(roads.get("areas", []))),
				"places": Array(_strings(roads.get("places", []))), "dangers": dangers, "passed": passed}
	return record


## [param entry] with JSON's floats made ints again (days, ticks), the rest kept.
static func _numbers(entry: Dictionary) -> Dictionary:
	var kept := {}
	for key: Variant in entry:
		var value: Variant = entry[key]
		kept[str(key)] = int(value) if value is float else value
	return kept


## [param value] with JSON's whole floats made ints again, all the way down
## (days, ticks, uids in lists); other values kept.
static func _whole(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)):
		return int(value)
	if value is Dictionary:
		var kept := {}
		for key: Variant in value:
			kept[str(key)] = _whole(value[key])
		return kept
	if value is Array:
		return Array(value).map(func(each: Variant) -> Variant: return _whole(each))
	return value


## [param value] as ItemBook uids (0 for none), or none.
static func _uids(value: Variant) -> PackedInt32Array:
	var uids := PackedInt32Array()
	if value is Array:
		for uid: Variant in value:
			uids.append(int(uid) if uid is float or uid is int else 0)
	return uids


## [param value] as lines of text, or none.
static func _lines(value: Variant) -> Array[String]:
	var lines: Array[String] = []
	if value is Array:
		for line: Variant in value:
			lines.append(str(line))
	return lines


## [param value] as sorted, distinct strings (the known lists), or none.
static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for each: Variant in value:
			if each is String and not each.is_empty() and not out.has(each):
				out.append(each)
	out.sort()
	return out
