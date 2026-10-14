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

const MAX_CARRIERS := 8
const MAX_EVENTS := 5

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
	carriers.append({"who": who, "name": carrier_name, "since": _now(), "held": 0})
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
		events.remove_at(1)


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
					carriers.append({"who": row["who"], "name": str(row.get("name", "")),
						"since": int(row.get("since", -1)), "held": int(row.get("held", 0))})
			var events: Array = []
			for event: Variant in entry.get("events", []):
				if event is Dictionary and event.get("kind") is String:
					events.append({"kind": event["kind"], "step": int(event.get("step", 0)),
						"zone": str(event.get("zone", "")), "tile": _tile(event.get("tile")), "what": str(event.get("what", ""))})
			items._book[int(key)] = {"id": entry["id"], "made": int(entry.get("made", 0)),
				"at": str(entry.get("at", "")), "holder": str(entry.get("holder", "")),
				"carriers": carriers, "events": events}
	items._next = maxi(int(data.get("next", 1)), 1)
	for uid: int in items._book:
		items._next = maxi(items._next, uid + 1)
	return items


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
