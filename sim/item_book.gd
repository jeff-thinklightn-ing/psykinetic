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
const KEPT_EVENTS: Array[String] = ["named", "reforged", "kept", "back", "bane", "grudge", "avenged", "blessed", "unblessed", "character", "gave way", "short", "bound", "grave goods"]

## Gives World.steps (the clock history is kept in).
var clock: Callable = func() -> int: return 0
var _next := 1
var _book: Dictionary[int, Dictionary] = {}


func _init(steps: Callable = Callable()) -> void:
	if steps.is_valid():
		clock = steps


## A new instance of [param id], come into the world by [param kind]
## ("stocked" in a level's chest, "built", "migrated" from a save before
## instances...) in [param what] at [param zone] [param tile], of
## [param style]'s make (decision 474; one of Items.STYLES, else none). Its
## uid.
func mint(id: String, kind: String, what := "", zone := "", tile := Vector2i(-1, -1), style := "") -> int:
	var uid := _next
	_next += 1
	_book[uid] = {"id": id, "made": _now(), "at": "", "holder": "", "carriers": [], "events": []}
	if style in Items.STYLES:
		_book[uid]["style"] = style
	if Items.condition_max(id) > 0:
		_book[uid]["condition"] = Items.condition_max(id)  # Made whole (decision 375).
	_book[uid]["events"].append(_event(kind, what, zone, tile))
	return uid


func has(uid: int) -> bool:
	return _book.has(uid)


## The further units stacked with [param uid] in one slot (decision 619):
## each its own instance, of the same kind; empty for a thing alone. Kept on
## the slot's first unit, so they go where it goes and save with the book.
func stack_of(uid: int) -> PackedInt32Array:
	var more := PackedInt32Array()
	if _book.has(uid):
		for each: Variant in _book[uid].get("stack", []):
			if _book.has(int(each)) and int(each) != uid:
				more.append(int(each))
	return more


## [param uid]'s further units are [param more] now (none: it is alone).
func set_stack(uid: int, more: PackedInt32Array) -> void:
	if not _book.has(uid):
		return
	if more.is_empty():
		_book[uid].erase("stack")
	else:
		_book[uid]["stack"] = Array(more)


## [param uid]'s make ("dwarven", "dark elven"; decision 474); "" for none.
func style_of(uid: int) -> String:
	return str(_book[uid].get("style", "")) if _book.has(uid) else ""


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


## [param uid] felled a body of [param kind] (decision 415): counted for
## the thing, whoever held it, by kind.
func fell(uid: int, kind: String) -> void:
	if not grows(uid) or kind.is_empty():
		return  # A plain thing keeps no tally (decision 472).
	var felled: Dictionary = _book[uid].get("felled", {})
	felled[kind] = int(felled.get(kind, 0)) + 1
	_book[uid]["felled"] = felled


## What [param uid] has felled, by kind ({kind: count}; decision 415); {}
## for none.
func felled_of(uid: int) -> Dictionary:
	return _book[uid].get("felled", {}) if _book.has(uid) else {}


## Whether [param uid] has character and grows (decision 472, on 415 and
## 417): only a thing held and used does. It earns it by 365's naming
## threshold (World._consider_name), a blessing (bless), or later a reforge
## with a special material; before that it keeps no kill tally, and takes
## no bane or grudge. A bundle of arrows never grows (its bow does).
func grows(uid: int) -> bool:
	return _book.has(uid) and _book[uid].has("character") and Items.ammo_of(id_of(uid)).is_empty()


## How [param uid] earned its character ("named", "blessed", "reforged");
## "" for none.
func character_of(uid: int) -> String:
	return str(_book[uid]["character"].get("how", "")) if _book.has(uid) and _book[uid].has("character") else ""


## [param uid] earns its character (decision 472): it grows from now on,
## for life, noted "character" in its history. Nothing for a bundle of
## arrows or a thing that has it.
func give_character(uid: int, how: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid) or _book[uid].has("character") or not Items.ammo_of(id_of(uid)).is_empty():
		return
	_book[uid]["character"] = {"how": how, "step": _now()}
	note(uid, "character", how, zone, tile)


## The kind [param uid] is the bane of (decision 417); "" for none.
func bane_of(uid: int) -> String:
	return str(_book[uid].get("bane", "")) if _book.has(uid) else ""


## [param uid] made the bane of [param kind], for life (decision 417).
func set_bane(uid: int, kind: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid) or kind.is_empty() or not bane_of(uid).is_empty():
		return
	_book[uid]["bane"] = kind
	note(uid, "bane", kind, zone, tile)


## [param uid]'s grudge (decision 417): {kind, paid}; {} for none.
func grudge_of(uid: int) -> Dictionary:
	return _book[uid].get("grudge", {}) if _book.has(uid) else {}


## [param uid] takes a grudge against [param kind] (its holders were hurt
## enough by one; decisions 417, 473), unless it holds one already.
func set_grudge(uid: int, kind: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not grows(uid) or kind.is_empty() or not grudge_of(uid).is_empty():
		return
	_book[uid]["grudge"] = {"kind": kind, "paid": 0}
	note(uid, "grudge", kind, zone, tile)


## [param amount] of harm a [param kind] did to [param uid]'s holder while
## it was in their hands (decision 473): a thing with character keeps the
## tally ("hurt" {kind: hp}, saved); a vengeance grows from it.
func hurt(uid: int, kind: String, amount: int) -> void:
	if not grows(uid) or kind.is_empty() or amount <= 0:
		return
	var tally: Dictionary = _book[uid].get("hurt", {})
	tally[kind] = int(tally.get(kind, 0)) + amount
	_book[uid]["hurt"] = tally


## The harm done to [param uid]'s holders by kind ({kind: hp}; decision
## 473); {} for none.
func hurt_of(uid: int) -> Dictionary:
	return _book[uid].get("hurt", {}) if _book.has(uid) else {}


## [param uid]'s grudge gives way to the bane it has become (decision 473:
## one growth per thing): gone, its kind's hurt forgotten, "gave way" in its
## history.
func drop_grudge(uid: int, zone := "", tile := Vector2i(-1, -1)) -> void:
	var grudge := grudge_of(uid)
	if grudge.is_empty():
		return
	_book[uid].erase("grudge")
	hurt_of(uid).erase(str(grudge["kind"]))
	note(uid, "gave way", "its grudge on %s to %s-bane" % [grudge["kind"], bane_of(uid)], zone, tile)


## One of [param uid]'s grudge's kind felled with it; [param paid] of them
## and the grudge lifts ("avenged"). True when it lifted.
func pay_grudge(uid: int, paid: int, zone := "", tile := Vector2i(-1, -1)) -> bool:
	var grudge := grudge_of(uid)
	if grudge.is_empty():
		return false
	grudge["paid"] = int(grudge["paid"]) + 1
	if int(grudge["paid"]) < paid:
		return false
	_book[uid].erase("grudge")
	hurt_of(uid).erase(str(grudge["kind"]))  # Paid: its hurt starts over (decision 473).
	note(uid, "avenged", str(grudge["kind"]), zone, tile)
	return true


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
func name_due(uid: int, held: int, deeds: int, deeds_alone := 0) -> Dictionary:
	if not _book.has(uid) or not name_of(uid).is_empty() or str(_book[uid]["holder"]).is_empty():
		return {}
	for row: Dictionary in history(uid)["carriers"]:
		if row["who"] != _book[uid]["holder"]:
			continue
		var done := 0
		for kind: String in row["deeds"]:
			done += int(row["deeds"][kind])
		# Held long enough with its deeds, or deeds_alone however long (decision 472).
		return row if int(row["held"]) >= held and done >= deeds or deeds_alone > 0 and done >= deeds_alone else {}
	return {}


## [param uid]'s condition (decision 375): what it has of its
## Items.condition_max; -1 for a thing with none.
func condition_of(uid: int) -> int:
	if not _book.has(uid) or Items.condition_max(id_of(uid)) <= 0:
		return -1
	return int(_book[uid].get("condition", Items.condition_max(id_of(uid))))


## [param uid] made short (decision 493): a measured thing (Items.measured)
## holds [param fraction] of its full measure, for life. A bundle's count
## (its condition) drops to that share; a resource keeps "short" (saved) and
## banks that share of its yield (yields_of). Noted "short", naming no one:
## the maker is in its "made" event. False, and nothing, for a thing not
## measured or already short.
func make_short(uid: int, fraction := 0.6, zone := "", tile := Vector2i(-1, -1)) -> bool:
	if not _book.has(uid) or not Items.measured(id_of(uid)) or _book[uid].has("short"):
		return false
	var share := clampf(fraction, 0.0, 1.0)
	_book[uid]["short"] = share
	if condition_of(uid) >= 0:
		set_condition(uid, maxi(floori(Items.condition_max(id_of(uid)) * share), 1))
	note(uid, "short", "", zone, tile)
	return true


## The share of its full measure [param uid] holds (decision 493): 1.0 for
## a full or unmeasured thing.
func short_of(uid: int) -> float:
	return float(_book[uid].get("short", 1.0)) if _book.has(uid) else 1.0


## The gold an old coin purse [param uid] held of its own (decision 601,
## before 601 amended made gold a count, never a thing): read once, by
## World's migration of a saved purse (World.purse_gold); -1 for none.
func legacy_gold(uid: int) -> int:
	return int(_book[uid].get("gold", -1)) if _book.has(uid) else -1


## What banking [param uid] gives (Items.yield_of its id), a short one's
## each count cut to its share, rounded down, at least 1 (decision 493).
func yields_of(uid: int) -> Dictionary:
	var yields := Items.yield_of(id_of(uid))
	var share := short_of(uid)
	if share < 1.0:
		for what: String in yields:
			yields[what] = maxi(floori(int(yields[what]) * share), 1)
	return yields


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


## Who [param uid] is blessed for (a carrier key; decision 424); "" when
## it is not blessed.
func blessed_for(uid: int) -> String:
	return str(_book[uid].get("blessed", {}).get("for", "")) if _book.has(uid) else ""


## [param uid] blessed at the temple for [param owner] (a carrier key;
## decision 424): a kept thing cleansed (no longer kept, every carrier's ill
## gone), and while it is blessed no ill gathers on it. Noted "blessed".
func bless(uid: int, owner: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid) or owner.is_empty():
		return
	_settle(_book[uid])
	_book[uid].erase("kept_from")
	_book[uid].erase("kept_by")
	for row: Dictionary in _book[uid]["carriers"]:
		row["ill"] = 0.0
		row["ill_at"] = _now()
	_book[uid]["blessed"] = {"for": owner, "step": _now()}
	note(uid, "blessed", owner, zone, tile)
	give_character(uid, "blessed", zone, tile)  # Decision 472.


## Where [param uid] was taken from the dead (decision 555): the grave
## goods source's label ("Altar"); "" for a thing that is not grave goods.
func grave_of(uid: int) -> String:
	return str(_book[uid].get("grave", "")) if _book.has(uid) else ""


## Whether [param uid] is grave goods (decision 555): a superstitious
## companion will not carry it.
func is_grave(uid: int) -> bool:
	return not grave_of(uid).is_empty()


## [param uid] marked grave goods from [param place] for life (decision
## 555): set where it is minted, in a grave goods source (World.grave_from).
## Noted "grave goods". Nothing for an empty place or a thing marked already.
func mark_grave(uid: int, place: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid) or place.is_empty() or is_grave(uid):
		return
	_book[uid]["grave"] = place
	note(uid, "grave goods", place, zone, tile)


## Who [param uid] is bound to (a carrier key; decision 544); "" when it is
## not bound.
func bound_to(uid: int) -> String:
	return str(_book[uid].get("bound", "")) if _book.has(uid) else ""


## [param uid] bound to [param owner] for life (a carrier key; decision
## 544: the draugr's device). Not 424's blessing: given, dropped or stolen
## it stays bound and works for nobody else, and it gives no character.
## Noted "bound". Nothing if it is bound already.
func bind(uid: int, owner: String, zone := "", tile := Vector2i(-1, -1)) -> void:
	if not _book.has(uid) or owner.is_empty() or not bound_to(uid).is_empty():
		return
	_book[uid]["bound"] = owner
	note(uid, "bound", owner, zone, tile)


## The charges [param uid] holds (decision 573 amended: the Draugr's
## Totem's, its player's resurrection charges, held nowhere else); 0 for
## none.
func charges_of(uid: int) -> int:
	return int(_book[uid].get("charges", 0)) if _book.has(uid) else 0


## The knight and deal tier a relic carries (decision 714): {knight, tier},
## {} for anything else.
func relic_of(uid: int) -> Dictionary:
	return _book[uid].get("relic", {}).duplicate() if _book.has(uid) else {}


## [param uid] marked a relic of [param knight], won at [param tier].
func mark_relic(uid: int, knight: String, tier: int) -> void:
	if _book.has(uid):
		_book[uid]["relic"] = {"knight": knight, "tier": tier}


## [param uid]'s charges set to [param amount] (at least 0).
func set_charges(uid: int, amount: int) -> void:
	if _book.has(uid):
		_book[uid]["charges"] = maxi(amount, 0)


## [param uid] given by its blessed owner to [param owner]: the blessing
## goes with the gift (decision 424).
func pass_blessing(uid: int, owner: String) -> void:
	if not blessed_for(uid).is_empty() and not owner.is_empty():
		_book[uid]["blessed"]["for"] = owner


## [param uid]'s blessing lost: taken from its owner, not given (decision
## 424). Noted "unblessed".
func unbless(uid: int, zone := "", tile := Vector2i(-1, -1)) -> void:
	if blessed_for(uid).is_empty():
		return
	_settle(_book[uid])
	_book[uid].erase("blessed")
	note(uid, "unblessed", "", zone, tile)


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
	give_character(uid, "named", zone, tile)  # A named thing grows (decision 472).


## [param uid], a named thing, reforged into [param to_id] (decision 432;
## economy's job finishes with it, while the job holds it): the same uid, its
## id the new one; its name (rendered with the new thing's word), its curse,
## its marks and its tally stay; its strength stays if it fits the new verb
## (Items.strength_fits), else it is lost and the history says so. A
## condition is set whole for a thing that has one. Noted "reforged" (never
## evicted). False, nothing done, for an unnamed thing or a pair
## Items.reforge_cost refuses.
func reforge(uid: int, to_id: String, zone := "", tile := Vector2i(-1, -1)) -> bool:
	if not _book.has(uid) or name_of(uid).is_empty() or Items.reforge_cost(id_of(uid), to_id).is_empty():
		return false
	var from := id_of(uid)
	var lost := ""
	if not strength_of(uid).is_empty() and not Items.strength_fits(strength_of(uid), to_id):
		lost = strength_of(uid)
		_book[uid]["strength"] = ""
	_book[uid]["id"] = to_id
	if Items.condition_max(to_id) > 0:
		_book[uid]["condition"] = Items.condition_max(to_id)
	else:
		_book[uid].erase("condition")
	note(uid, "reforged", "%s into %s%s" % [from, to_id, "; %s lost" % lost if not lost.is_empty() else ""], zone, tile)
	return true


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
		for more in stack_of(int(uid)):
			seen[more] = true  # Stacked with a known one (decision 619).
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
			items._book[int(key)] = {"id": str(Items.RENAMED.get(entry["id"], entry["id"])), "made": int(entry.get("made", 0)),
				"at": str(entry.get("at", "")), "holder": str(entry.get("holder", "")),
				"carriers": carriers, "events": events}
			if entry.get("condition") is float or entry.get("condition") is int:
				items._book[int(key)]["condition"] = int(entry["condition"])
			if (entry.get("short") is float or entry.get("short") is int) and float(entry["short"]) >= 0.0 and float(entry["short"]) < 1.0:
				items._book[int(key)]["short"] = float(entry["short"])
			if str(entry.get("style", "")) in Items.STYLES:
				items._book[int(key)]["style"] = str(entry["style"])
			if entry.get("blessed") is Dictionary and entry["blessed"].get("for") is String:
				items._book[int(key)]["blessed"] = {"for": entry["blessed"]["for"], "step": int(entry["blessed"].get("step", 0))}
			if entry.get("grave") is String and not entry["grave"].is_empty():
				items._book[int(key)]["grave"] = entry["grave"]
			if entry.get("bound") is String and not entry["bound"].is_empty():
				items._book[int(key)]["bound"] = entry["bound"]
			if entry.get("gold") is float or entry.get("gold") is int:
				items._book[int(key)]["gold"] = maxi(int(entry["gold"]), 0)  # An old purse's (601), for its migration.
			if entry.get("stack") is Array and not entry["stack"].is_empty():
				items._book[int(key)]["stack"] = entry["stack"].map(func(each: Variant) -> int: return int(each))  # Decision 619.
			if entry.get("charges") is float or entry.get("charges") is int:
				items._book[int(key)]["charges"] = maxi(int(entry["charges"]), 0)  # Decision 573 amended.
			if entry.get("relic") is Dictionary and entry["relic"].get("knight") is String:
				items._book[int(key)]["relic"] = {"knight": entry["relic"]["knight"], "tier": int(entry["relic"].get("tier", 0))}  # Decision 714.
			if entry.get("bane") is String and not entry["bane"].is_empty():
				items._book[int(key)]["bane"] = entry["bane"]
			if entry.get("grudge") is Dictionary and entry["grudge"].get("kind") is String:
				items._book[int(key)]["grudge"] = {"kind": entry["grudge"]["kind"], "paid": int(entry["grudge"].get("paid", 0))}
			if entry.get("character") is Dictionary:
				items._book[int(key)]["character"] = {"how": str(entry["character"].get("how", "")), "step": int(entry["character"].get("step", 0))}
			elif entry.get("name") is Dictionary or entry.get("blessed") is Dictionary or entry.get("felled") is Dictionary:
				# Saved before 472: a named, blessed or tallied thing has grown already.
				items._book[int(key)]["character"] = {"how": "named" if entry.get("name") is Dictionary else "blessed" if entry.get("blessed") is Dictionary else "used", "step": int(entry.get("made", 0))}
			if entry.get("hurt") is Dictionary and not entry["hurt"].is_empty():
				var harm := {}
				for kind: Variant in entry["hurt"]:
					if int(entry["hurt"][kind]) > 0:
						harm[str(kind)] = int(entry["hurt"][kind])
				items._book[int(key)]["hurt"] = harm
			if entry.get("felled") is Dictionary and not entry["felled"].is_empty():
				var felled := {}
				for kind: Variant in entry["felled"]:
					if int(entry["felled"][kind]) > 0:
						felled[str(kind)] = int(entry["felled"][kind])
				items._book[int(key)]["felled"] = felled
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
	var counts: bool = not kept.is_empty() and row["who"] != kept and not entry.has("blessed") \
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
