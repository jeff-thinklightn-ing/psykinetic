class_name Lore
extends RefCounted
## The world's facts, read once from levels/lore/ (DIR: the entries of
## FILES, and knowers.json), as docs/lore/README.md describes them
## (decisions 257, 258). known_by says what one knower knows: the facts a
## prompt may state for that character, never lines to say.
##
## A fact counts only when its status and its entry's are both agreed (or,
## asked for with least "draft", agreed or draft; asked is an open question
## and never counts). A knower must pass the same gate. A knower knows the
## common facts and rumours whose where meets its own (or is empty), those
## sharing a tag with its tags wherever they are, and the secret and lived
## facts that name it. A rumour comes back as hearsay and a lived fact as
## memory; whether a rumour is true stays here.
##
## names.json (decision 366) says how things are named: forms by how a name
## came (holder, deed, maker) and lore's word for a thing, under the same
## gate. Items stores a name as {form, holder, ...} and render_name fills it
## at display time, so a reforged thing keeps its name with its new word.
##
## roles.json (decision 376) says who is bound to lore facts: professions by
## trade id and hidden personality types, each a profile whose stats make
## the binding. An official speaks only what it knows here, a free one (a
## thieving smith, a bard) may embellish and lie in character, and anyone
## else is townsfolk.

const DIR := "res://levels/lore/"
const FILES := ["world", "factions", "regions", "materials", "creatures", "people", "history"]
const KNOWN := ["common", "rumour", "secret", "lived"]
## A fact's weight when it gives none: how much it matters beside others,
## for a prompt that has room for only some. Left at this until Jeff weighs
## them.
const DEFAULT_WEIGHT := 1.0
## How a name came, and what a form may be filled from.
const NAME_HOWS := ["holder", "deed", "maker"]
const NAME_SLOTS := ["holder", "thing", "deed", "maker"]
## How a role is bound to lore facts; TOWNSFOLK for a trade roles.json does
## not list.
const BINDINGS := ["official", "free"]
const TOWNSFOLK := "townsfolk"
## A role's profile (Jeff, 2026-10-17): each stat a word in roles.json,
## given back as a number on 1..10 too.
const STATS := ["superstition", "creativity", "intellect", "integrity"]
const LEVELS := {"low": 2, "mid": 5, "high": 8}
static var _townsfolk: Dictionary = {}

static var _entries: Dictionary = {}
static var _knowers: Dictionary = {}
static var _forms: Array = []
static var _things: Array = []
static var _names_read := false
static var _professions: Dictionary = {}
static var _types: Dictionary = {}
static var _default_type := "steady"
static var _roles_read := false


## Every entry by id, read on first use.
static func entries() -> Dictionary:
	_load()
	return _entries


## Every knower by id, read on first use.
static func knowers() -> Dictionary:
	_load()
	return _knowers


## Forgets what was read, so the next ask reads the files again (a data
## file live-reloaded).
static func reload() -> void:
	_entries = {}
	_knowers = {}
	_forms = []
	_things = []
	_names_read = false
	_professions = {}
	_types = {}
	_townsfolk = {}
	_roles_read = false


## Uses [param entry_list] and [param knower_list] (and, given, the name
## forms and thing words) in place of the files (tests, tools).
static func use(entry_list: Array, knower_list: Array, form_list := [], thing_list := []) -> void:
	_entries = {}
	_knowers = {}
	_forms = form_list.filter(func(form: Variant) -> bool: return form is Dictionary)
	_things = thing_list.filter(func(thing: Variant) -> bool: return thing is Dictionary)
	_names_read = true
	for entry: Variant in entry_list:
		if entry is Dictionary and entry.get("id") is String:
			_entries[entry["id"]] = entry
	for knower: Variant in knower_list:
		if knower is Dictionary and knower.get("id") is String:
			_knowers[knower["id"]] = knower


## What [param knower] knows, in file order: [{id, text, hearsay, memory,
## secret, kept, where, weight}] (kept: a secret the knower is named in the
## fact's kept_by for, which it acts on and never tells; where: the fact's region
## ids; weight: its own, else DEFAULT_WEIGHT). [param about], when given, keeps the facts on any of
## those topics (_about). [param least] is "agreed" (what code uses) or
## "draft" (to preview drafts).
static func known_by(knower: String, about := PackedStringArray(), least := "agreed", type := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var who: Dictionary = knowers().get(knower, {})
	if who.is_empty() or not _counts(str(who.get("status", "")), least):
		return out
	var where: Array = who.get("where", [])
	var tags: Array = who.get("tags", [])
	var domain := PackedStringArray(profile(knower, type, least).get("domain", []) if _knows_as_role(knower, type) else [])
	for id: String in entries():
		var entry: Dictionary = _entries[id]
		var entry_status := str(entry.get("status", ""))
		if not _counts(entry_status, least):
			continue
		for fact: Variant in entry.get("facts", []):
			if fact is not Dictionary or not _counts(str(fact.get("status", entry_status)), least):
				continue
			var known := str(fact.get("known", ""))
			var knows := false
			match known:
				"common", "rumour":
					var at: Array = fact.get("where", [])
					knows = at.is_empty() or _meets(at, where) or _meets(fact.get("tags", []), tags) \
							or (not domain.is_empty() and _about(fact, entry, domain))
				"secret", "lived":
					knows = knower in fact.get("knowers", [])
			if knows and (about.is_empty() or _about(fact, entry, about)):
				out.append({"id": fact.get("id", ""), "text": fact.get("text", ""),
						"hearsay": known == "rumour", "memory": known == "lived", "secret": known == "secret",
						"kept": known == "secret" and knower in fact.get("kept_by", []),
						"where": fact.get("where", []).duplicate(), "weight": float(fact.get("weight", DEFAULT_WEIGHT))})
	return out


## The name forms that count ([param least] as for known_by), in file
## order: [{id, how, form}], those of [param how] when given.
static func name_forms(how := "", least := "agreed") -> Array[Dictionary]:
	_load_names()
	var out: Array[Dictionary] = []
	for form: Dictionary in _forms:
		if _counts(str(form.get("status", "")), least) and (how.is_empty() or form.get("how") == how):
			out.append({"id": str(form.get("id", "")), "how": str(form.get("how", "")), "form": str(form.get("form", ""))})
	return out


## Lore's word for a thing ([param item_id] first, then any of [param tags]),
## or "" when it has none and the item's own word stands.
static func thing_word(item_id: String, tags := PackedStringArray(), least := "agreed") -> String:
	_load_names()
	for pass_tags: bool in [false, true]:
		for thing: Dictionary in _things:
			var match_for: Variant = thing.get("for")
			if _counts(str(thing.get("status", "")), least) and (match_for in tags if pass_tags else match_for == item_id):
				return str(thing.get("words", ""))
	return ""


## A stored name ([param name]: {form, holder, deed, maker}) as text, its
## {thing} lore's word for the item or else [param noun] (the item's own).
## The form is used whatever its status now, so a name given stays given (the
## thing's word goes by [param least]); "" when the form is unknown or a slot
## it needs is empty.
static func render_name(name: Dictionary, item_id: String, tags := PackedStringArray(), noun := "", least := "agreed") -> String:
	_load_names()
	var text := ""
	for form: Dictionary in _forms:
		if form.get("id") == name.get("form"):
			text = str(form.get("form", ""))
	if text.is_empty():
		return ""
	var word := thing_word(item_id, tags, least)
	var slots := {"holder": str(name.get("holder", "")), "thing": word if not word.is_empty() else noun,
			"deed": str(name.get("deed", "")), "maker": str(name.get("maker", ""))}
	for slot: String in NAME_SLOTS:
		var key := "{%s}" % slot
		if text.contains(key):
			if slots[slot].is_empty():
				return ""
			text = text.replace(key, slots[slot])
	return text


## How someone of [param trade] (and of personality [param type], none
## for the steady default) is bound to lore facts: "official" (speaks only
## what it knows here), "free" (may embellish and lie, in character) or
## "townsfolk". It derives from their stats (derived_binding); a profession
## or type whose profile does not count yet stands on its binding, Jeff's
## word, so a draft profile never turns an official into townsfolk.
static func binding(trade: String, type := "", least := "agreed") -> String:
	_load_roles()
	var words := _layer(_professions.get(trade, {}), least, true)
	if not _professions.has(trade):
		words = _counted(_townsfolk, least)
	words.merge(_layer(_types.get(_type_of(type), {}), least, true), true)
	return derived_binding(words) if not words.is_empty() else TOWNSFOLK


## The profile of someone of [param trade] and personality [param type]:
## {domain, binding, words: {stat: "low" | "mid" | "high"}} and each of
## STATS as its number (LEVELS). The profession's stats (the townsfolk's
## for a trade not listed), then the type's where it sets them, else mid;
## the domain is both. {} when neither profile counts under [param least]
## (economy then rolls a plain resident). The type is hidden: never shown.
static func profile(trade: String, type := "", least := "agreed") -> Dictionary:
	_load_roles()
	var base: Dictionary = _professions[trade].get("profile", {}) if _professions.has(trade) else _townsfolk
	var base_words := _counted(base, least)
	var kind: Dictionary = _types.get(_type_of(type), {}).get("profile", {})
	var kind_words := _counted(kind, least)
	if base_words.is_empty() and kind_words.is_empty():
		return {}
	var out := {"domain": [], "binding": binding(trade, type, least), "words": {}}
	for shown: Dictionary in [base, kind]:
		if _counts(str(shown.get("status", "")), least):
			for topic: Variant in shown.get("domain", []):
				if not topic in out["domain"]:
					out["domain"].append(topic)
	for stat: String in STATS:
		var word := str(kind_words.get(stat, base_words.get(stat, "mid")))
		out["words"][stat] = word
		out[stat] = LEVELS.get(word, LEVELS["mid"])
	return out


## The personality types that count under [param least], to roll from.
static func types(least := "agreed") -> PackedStringArray:
	_load_roles()
	var out := PackedStringArray()
	for id: String in _types:
		if _counts(str(_types[id].get("status", "")), least):
			out.append(id)
	return out


## The binding a profile's stats make: creativity low and integrity high
## speak only lore (official), creativity high or integrity low may make
## things up (free), and anything else is townsfolk.
static func derived_binding(words: Dictionary) -> String:
	var creativity := str(words.get("creativity", "mid"))
	var integrity := str(words.get("integrity", "mid"))
	if creativity == "low" and integrity == "high":
		return "official"
	if creativity == "high" or integrity == "low":
		return "free"
	return TOWNSFOLK


## The knower to ask known_by for someone of [param trade]: the trade's own
## knower when there is one, else the townsfolk.
static func knower_for(trade: String) -> String:
	return trade if knowers().has(trade) else TOWNSFOLK


## Uses these professions and types (and [param townsfolk], the profile for
## a trade not listed) in place of roles.json (tests).
static func use_roles(profession_list: Array, type_list := [], townsfolk := {}, default_type := "steady") -> void:
	_professions = {}
	_types = {}
	_townsfolk = townsfolk
	_default_type = default_type
	for each: Variant in profession_list:
		if each is Dictionary and each.get("id") is String:
			_professions[each["id"]] = each
	for each: Variant in type_list:
		if each is Dictionary and each.get("id") is String:
			_types[each["id"]] = each
	_roles_read = true


## A profile's stats as set (only those it sets), when it counts.
static func _counted(shown: Dictionary, least: String) -> Dictionary:
	var out := {}
	if _counts(str(shown.get("status", "")), least):
		for stat: String in STATS:
			if shown.has(stat):
				out[stat] = str(shown[stat])
	return out


## [param role]'s stats for its binding: its profile's when that counts,
## else (with [param stand_on_binding]) the stats its binding stands for.
static func _layer(role: Dictionary, least: String, stand_on_binding: bool) -> Dictionary:
	if role.is_empty() or not _counts(str(role.get("status", "")), least):
		return {}
	var words := _counted(role.get("profile", {}), least)
	if words.is_empty() and stand_on_binding:
		match str(role.get("binding", "")):
			"official":
				words = {"creativity": "low", "integrity": "high"}
			"free":
				words = {"creativity": "high"}
	return words


static func _type_of(type: String) -> String:
	return type if not type.is_empty() else _default_type


## Whether [param fact] (in [param entry]) is on one of the topics in
## [param about]: a topic that is one of the fact's or the entry's tags or
## the entry's id, or a word or phrase of its text or the entry's name
## (whole words, any case, a plural "s" allowed: "ore" finds "ores").
static func _about(fact: Dictionary, entry: Dictionary, about: PackedStringArray) -> bool:
	var tags: Array = fact.get("tags", []) + entry.get("tags", []) + [entry.get("id", "")]
	var words := " %s %s " % [_words(str(fact.get("text", ""))), _words(str(entry.get("name", "")))]
	for topic: String in about:
		var each := _words(topic)
		if each.is_empty():
			continue
		if each in tags or each.replace(" ", "_") in tags or words.contains(" %s " % each) or words.contains(" %ss " % each):
			return true
	return false


## [param text] lower case, with everything but letters, digits and
## hyphens turned to single spaces.
static func _words(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" else " "
	return " ".join(out.split(" ", false))


static func _counts(status: String, least: String) -> bool:
	return status == "agreed" or (least == "draft" and status == "draft")


static func _meets(a: Array, b: Array) -> bool:
	for each: Variant in a:
		if each in b:
			return true
	return false


static func _load() -> void:
	if not _entries.is_empty():
		return
	for file: String in FILES:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + file + ".json"))
		if data is not Dictionary or data.get("entries") is not Array:
			push_warning("Lore: %s%s.json has no entries list" % [DIR, file])
			continue
		for entry: Variant in data["entries"]:
			if entry is Dictionary and entry.get("id") is String:
				_entries[entry["id"]] = entry
	var known: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "knowers.json"))
	if known is Dictionary and known.get("knowers") is Array:
		for knower: Variant in known["knowers"]:
			if knower is Dictionary and knower.get("id") is String:
				_knowers[knower["id"]] = knower


static func _load_roles() -> void:
	if _roles_read:
		return
	_roles_read = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "roles.json"))
	if data is not Dictionary or data.get("professions") is not Array or data.get("types") is not Array:
		push_warning("Lore: %sroles.json has no professions and types lists" % DIR)
		return
	use_roles(data["professions"], data["types"], data.get("townsfolk", {}) if data.get("townsfolk") is Dictionary else {},
			str(data.get("default_type", "steady")))


## Whether [param knower] knows by a profile's domain: a profession's
## knower, or anyone given a personality type.
static func _knows_as_role(knower: String, type: String) -> bool:
	_load_roles()
	return _professions.has(knower) or not type.is_empty()


static func _load_names() -> void:
	if _names_read:
		return
	_names_read = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "names.json"))
	if data is not Dictionary or data.get("forms") is not Array or data.get("things") is not Array:
		push_warning("Lore: %snames.json has no forms and things lists" % DIR)
		return
	_forms = data["forms"].filter(func(form: Variant) -> bool: return form is Dictionary)
	_things = data["things"].filter(func(thing: Variant) -> bool: return thing is Dictionary)
