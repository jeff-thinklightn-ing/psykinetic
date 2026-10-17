class_name ItemBook
extends RefCounted
## Every thing in the world, one instance each, by uid: what it is (an
## Items id) and its history: who carried it, for how long, and up to
## MAX_EVENTS notable things that happened to it. Server only (World.items),
## saved with the world (Snapshot, "items").
##
## Slots replicate ids; each slot's instance is a uid beside it
## (GridEntity.slot_items), never sent. Other holders (the stockpile, later
## the ground) keep uids too. Nothing here runs per tick: World writes as
## things move (place), and held time is counted when a carrier lets go.
## An instance lives until something ends it (end: eaten, banked); gear is
## never ended.
##
## An entry: {id, made (World.steps), at (where it is: a holder key),
## holder (who carries it now, or ""), carriers: [{who, name, since, held}],
## events: [{kind, step, zone, tile, what}]}. A carrier's held is steps
## held before since; since is -1 unless it carries it now. events[0] is
## where it came from and stays; past MAX_EVENTS the oldest other goes.
##
## Names (decision 365): a carrier row keeps deeds ({kind: count}: felled,
## guarded, shot...) done with the thing while it carried it (deed). A
## thing carried long enough by one named holder, with deeds enough
## (name_due, World._consider_names), takes a name for life (set_name:
## {form, holder, made_step, text}, and a strength): it is never renamed,
## and its "named" event, like a "reforged" one, is never the one that goes.
##
## Curses (decision 370): a named thing taken by anyone but its namer
## other than from its namer's hand is kept from its namer (keep:
## kept_from, kept_by, a "kept" event). While it is kept, a carrier row
## that counts (Items.curse()'s follows: "thing", anyone but the namer;
## "taker", only who took it) gathers ill (0..1) as it holds it, reaching 1
## after full_days of the world clock, and loses it at fade of that rate
## while it does not; counted from the clock as it changes (_settle), never
## per tick. Back in its namer's hands it is lifted (lift, a "back" event).

const MAX_CARRIERS := 8
const MAX_EVENTS := 5
## Events that stay past MAX_EVENTS, as events[0] does.
const KEPT_EVENTS: Array[String] = ["named", "reforged", "kept", "back"]

## Gives World.steps (the clock history is kept in).
var clock: Callable = func() -> int: return 0
var _next := 1
var _book: Dictionary[int, Dictionary] = {}


func _init(steps: Callable = Callable()) -> void:
	if steps.is_valid():
		clock = steps


## A new instance of [param id], come into the world by [param kind]
## ("stocked" in a level's chest, "built", "migrated" from a save before
## instances...) in [param what] at [param zone] [param tile]. Its uid.
func mint(id: String, kind: String, what := "", zone := "", tile := Vector2i(-1, -1)) -> int:
	var uid := _next
	_next += 1
	_book[uid] = {"id": id, "made": _now(), "at": "", "holder": "", "carriers": [], "events": []}
	if Items.condition_max(id) > 0:
		_book[uid]["condition"] = Items.condition_max(id)  # Made whole (decision 375).
	_book[uid]["events"].append(_event(kind, what, zone, tile))
	return uid


func has(uid: int) -> bool:
	return _book.has(uid)


## The Items id of [param uid]; "" for one not in the book.
func id_of(uid: int) -> String:
	return str(_book[uid]["id"]) if _book.has(uid) else ""


## Where [param uid] is (place's at); "" for nowhere known or not in the book.
func at_of(uid: int) -> String:
	return str(_book[uid]["at"]) if _book.has(uid) else ""


func size() -> int:
	return _book.size()


## A copy of [param uid]'s entry, each carrier's held counted up to now;
## {} for one not in the book.
func history(uid: int) -> Dictionary:
	if not _book.has(uid):
		return {}
	var copy: Dictionary = _book[uid].duplicate(true)
	for row: Dictionary in copy["carriers"]:
		if int(row["since"]) >= 0:
			row["held"] = int(row["held"]) + _now() - int(row["since"])
	return copy


## Steps [param who] has carried [param uid], all told, up to now.
func held_by(uid: int, who: String) -> int:
	for row: Dictionary in history(uid).get("carriers", []):
		if row["who"] == who:
			return int(row["held"])
	return 0


## [param uid] is now at [param at] (a holder key: "<zone>/<entity>",
## "player:<id>", "stockpile"...), carried by [param who] (named
## [param carrier_name]), or by nobody ("": a chest, the stockpile, the
## ground). The last carrier's time is counted as it lets go.
func place(uid: int, at: String, who := "", carrier_name := "") -> void:
	if not _book.has(uid):
		return
	var entry: Dictionary = _book[uid]
	entry["at"] = at
	if entry["holder"] == who:
		return
	_settle(entry)
	_let_go(entry)
	if who.is_empty():
		return
	entry["holder"] = who
	var carriers: Array = entry["carriers"]
	for row: Dictionary in carriers:
		if row["who"] == who:
			row["since"] = _now()
			row["name"] = carrier_name
			return
	carriers.append({"who": who, "name": carrier_name, "since": _now(), "held": 0, "deeds": {}, "ill": 0.0, "ill_at": _now()})
	if carriers.size() > MAX_CARRIERS:
		# The one who held it least goes (never who holds it now).
		var least := 0
		for i in carriers.size() - 1:
			if int(carriers[i]["held"]) < int(carriers[least]["held"]):
				least = i
		carriers.remove_at(least)


## Something notable happened to [param uid] ("found", "given", "felled"...),
## to or by [param what], at [param zone] [param tile].
func note(uid: int, kind: String, what := "", zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid):
		return
	var events: Array = _book[uid]["events"]
	events.append(_event(kind, what, zone, tile))
	if events.size() > MAX_EVENTS:
		for i in range(1, events.size()):
			if str(events[i]["kind"]) not in KEPT_EVENTS:
				events.remove_at(i)
				break


## [param who], carrying [param uid] now, did a deed of [param kind] with
## it (decision 365): its carrier row counts it. Nothing for anyone else.
func deed(uid: int, who: String, kind: String) -> void:
	if not _book.has(uid) or who.is_empty() or _book[uid]["holder"] != who:
		return
	for row: Dictionary in _book[uid]["carriers"]:
		if row["who"] == who:
			row["deeds"][kind] = int(row["deeds"].get(kind, 0)) + 1
			return


## [param uid]'s name ({form, holder, who (its namer's carrier key),
## made_step, text}); {} for none.
func name_of(uid: int) -> Dictionary:
	return _book[uid].get("name", {}) if _book.has(uid) else {}


## [param uid]'s strength (a key of Items.naming()'s strengths); "" for none.
func strength_of(uid: int) -> String:
	return str(_book[uid].get("strength", "")) if _book.has(uid) else ""


## The carrier row (a copy, held counted up to now) of who carries
## [param uid] now, when it has carried it [param held] steps or more and
## done [param deeds] deeds or more with it, and it has no name yet; {}
## otherwise.
func name_due(uid: int, held: int, deeds: int) -> Dictionary:
	if not _book.has(uid) or not name_of(uid).is_empty() or str(_book[uid]["holder"]).is_empty():
		return {}
	for row: Dictionary in history(uid)["carriers"]:
		if row["who"] != _book[uid]["holder"]:
			continue
		var done := 0
		for kind: String in row["deeds"]:
			done += int(row["deeds"][kind])
		return row if int(row["held"]) >= held and done >= deeds else {}
	return {}


## [param uid]'s condition (decision 375): what it has of its
## Items.condition_max; -1 for a thing with none.
func condition_of(uid: int) -> int:
	if not _book.has(uid) or Items.condition_max(id_of(uid)) <= 0:
		return -1
	return int(_book[uid].get("condition", Items.condition_max(id_of(uid))))


## [param uid]'s condition set to [param amount], within 0 and its most
## (wear, the fletcher's mending). Nothing for a thing with none.
func set_condition(uid: int, amount: int) -> void:
	if condition_of(uid) >= 0:
		_book[uid]["condition"] = clampi(amount, 0, Items.condition_max(id_of(uid)))


## Who [param uid] is kept from (its namer's carrier key; decision
## 370); "" when it is not kept.
func kept_from(uid: int) -> String:
	return str(_book[uid].get("kept_from", "")) if _book.has(uid) else ""


## [param uid], named, is kept from its namer by [param who] (named
## [param who_name]): noted "kept". Nothing if it is kept already or
## has no namer.
func keep(uid: int, who: String, who_name: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid) or not kept_from(uid).is_empty() or str(name_of(uid).get("who", "")).is_empty():
		return
	_settle(_book[uid])
	_book[uid]["kept_from"] = name_of(uid)["who"]
	_book[uid]["kept_by"] = who
	note(uid, "kept", "from %s by %s" % [name_of(uid).get("holder", ""), who_name], zone, tile)


## [param uid] is back in its namer's hands: no longer kept, noted
## "back"; the ill on it fades from now. Nothing if it is not kept.
func lift(uid: int, zone := "", tile := Vector2i(-1, -1)) -> void:
	if kept_from(uid).is_empty():
		return
	_settle(_book[uid])
	_book[uid].erase("kept_from")
	_book[uid].erase("kept_by")
	note(uid, "back", "with %s" % name_of(uid).get("holder", ""), zone, tile)


## The ill (0..1) [param who] has from carrying [param uid], counted up
## to now; 0 for none.
func ill_of(uid: int, who: String) -> float:
	if not _book.has(uid):
		return 0.0
	var entry: Dictionary = _book[uid]
	for row: Dictionary in entry["carriers"]:
		if row["who"] == who:
			return _ill_now(entry, row)
	return 0.0


## [param uid] takes its name for life (decision 365): [param name]
## ({form, holder, made_step, text}) and [param strength], noted "named".
## Nothing if it has one already.
func set_name(uid: int, name: Dictionary, strength: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid) or not name_of(uid).is_empty():
		return
	_book[uid]["name"] = name.duplicate()
	_book[uid]["strength"] = strength
	note(uid, "named", str(name.get("text", "")), zone, tile)


## [param uid] leaves the world ("banked", "eaten"): its entry, the last
## event added, is returned and it is gone from the book. {} for one not in it.
func end(uid: int, kind: String, what := "", zone := "", tile := Vector2i(-1, -1)) -> Dictionary:
	if not _book.has(uid):
		return {}
	_let_go(_book[uid])
	note(uid, kind, what, zone, tile)
	var last: Dictionary = _book[uid]
	_book.erase(uid)
	return last


## The uids in the book that are not in [param known] (everything every
## holder has): what has leaked. For tests and the console.
func orphans(known: Array) -> Array[int]:
	var seen := {}
	for uid: Variant in known:
		seen[int(uid)] = true
	var lost: Array[int] = []
	for uid: int in _book:
		if not seen.has(uid):
			lost.append(uid)
	return lost


func to_dict() -> Dictionary:
	var book := {}
	for uid: int in _book:
		book[str(uid)] = _book[uid]
	return {"next": _next, "book": book}


## The book saved by to_dict; entries that make no sense are skipped.
static func from_dict(data: Variant, steps: Callable = Callable()) -> ItemBook:
	var items := ItemBook.new(steps)
	if data is not Dictionary:
		return items
	var book: Variant = data.get("book", {})
	if book is Dictionary:
		for key: Variant in book:
			var entry: Variant = book[key]
			if not str(key).is_valid_int() or entry is not Dictionary or entry.get("id") is not String:
				continue
			var carriers: Array = []
			for row: Variant in entry.get("carriers", []):
				if row is Dictionary and row.get("who") is String:
					var deeds := {}
					if row.get("deeds") is Dictionary:
						for kind: Variant in row["deeds"]:
							deeds[str(kind)] = int(row["deeds"][kind])
					carriers.append({"who": row["who"], "name": str(row.get("name", "")),
						"since": int(row.get("since", -1)), "held": int(row.get("held", 0)), "deeds": deeds,
						"ill": clampf(float(row.get("ill", 0.0)), 0.0, 1.0), "ill_at": int(row.get("ill_at", 0))})
			var events: Array = []
			for event: Variant in entry.get("events", []):
				if event is Dictionary and event.get("kind") is String:
					events.append({"kind": event["kind"], "step": int(event.get("step", 0)),
						"zone": str(event.get("zone", "")), "tile": _tile(event.get("tile")), "what": str(event.get("what", ""))})
			items._book[int(key)] = {"id": entry["id"], "made": int(entry.get("made", 0)),
				"at": str(entry.get("at", "")), "holder": str(entry.get("holder", "")),
				"carriers": carriers, "events": events}
			if entry.get("condition") is float or entry.get("condition") is int:
				items._book[int(key)]["condition"] = int(entry["condition"])
			var name: Variant = entry.get("name")
			if name is Dictionary and name.get("form") is String and name.get("holder") is String:
				items._book[int(key)]["name"] = {"form": name["form"], "holder": name["holder"],
					"made_step": int(name.get("made_step", 0)), "text": str(name.get("text", ""))}
				if name.get("who") is String and not name["who"].is_empty():
					items._book[int(key)]["name"]["who"] = name["who"]
				items._book[int(key)]["strength"] = str(entry.get("strength", ""))
				if entry.get("kept_from") is String and not entry["kept_from"].is_empty():
					items._book[int(key)]["kept_from"] = entry["kept_from"]
					items._book[int(key)]["kept_by"] = str(entry.get("kept_by", ""))
	items._next = maxi(int(data.get("next", 1)), 1)
	for uid: int in items._book:
		items._next = maxi(items._next, uid + 1)
	return items


## Every carrier row's ill counted up to now and kept from now.
func _settle(entry: Dictionary) -> void:
	for row: Dictionary in entry["carriers"]:
		row["ill"] = _ill_now(entry, row)
		row["ill_at"] = _now()


## [param row]'s ill now: what it had at ill_at, grown while it held a
## kept thing it counts for (Items.curse()'s follows), else faded.
func _ill_now(entry: Dictionary, row: Dictionary) -> float:
	var ill := float(row.get("ill", 0.0))
	var since := _now() - int(row.get("ill_at", _now()))
	if since <= 0:
		return ill
	var curse := Items.curse()
	var full := maxf(1.0, float(curse["full_days"]) * DayNight.day_steps)
	var kept := str(entry.get("kept_from", ""))
	var counts: bool = not kept.is_empty() and row["who"] != kept \
			and (curse["follows"] == "thing" or row["who"] == entry.get("kept_by", ""))
	if counts and int(row["since"]) >= 0:
		return minf(1.0, ill + since / full)
	return maxf(0.0, ill - since * float(curse["fade"]) / full)


## A saved [x, y] as ints; null for none.
static func _tile(value: Variant) -> Variant:
	return [int(value[0]), int(value[1])] if value is Array and value.size() == 2 else null


func _let_go(entry: Dictionary) -> void:
	for row: Dictionary in entry["carriers"]:
		if int(row["since"]) >= 0:
			row["held"] = int(row["held"]) + _now() - int(row["since"])
			row["since"] = -1
	entry["holder"] = ""


func _event(kind: String, what: String, zone: String, tile: Vector2i) -> Dictionary:
	return {"kind": kind, "step": _now(), "zone": zone, "tile": [tile.x, tile.y] if tile.x >= 0 else null, "what": what}


func _now() -> int:
	return int(clock.call())
