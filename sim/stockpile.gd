class_name Stockpile
extends RefCounted
## The town's store: what players have brought home. Each store belongs to a
## place of kind "stockpile" (Holdings, by place id "<area>/<key>"), and
## holds counts of the raw resources (RESOURCES: gold, ore, wood, cloth,
## food) and the gear banked there, one entry per item (its id for now;
## the item book's uid once items are instances). A ledger keeps the last
## LEDGER_SIZE changes, stamped with the World's steps.
##
## Things reach it through a depot (a Chest with depot set) inside a
## stockpile place the town holds: World.try_transfer banks what is put in
## at once. Picking loot up counts for nothing. Players never take from it:
## take is for the town's own use (production, the shop, raids), and a
## store whose place is gone from the levels is kept, never dropped.
## World keeps one (World.stockpile), made by Main at boot from the
## snapshot ("stockpile": to_dict). Null on a client.

const RESOURCES: Array[String] = ["gold", "ore", "wood", "cloth", "food"]
const KIND := "stockpile"
## The faction whose stockpiles take deposits.
const TOWN := "town"
const LEDGER_SIZE := 200

## () -> int: the World's steps, the ledger's clock (0 if unset).
var clock := Callable()

## Place id -> {resources: {name: count}, items: Array[String],
## ledger: Array[{step, what, count, by, from}]}.
var _stores: Dictionary[String, Dictionary] = {}


func _init(saved := {}, with_clock := Callable()) -> void:
	clock = with_clock
	from_dict(saved)


func now() -> int:
	return int(clock.call()) if clock.is_valid() else 0


## The stockpile place whose ground takes in [param cell] of
## [param area_name], if the town holds it; "" if there is none (or it is
## held by someone else).
static func place_at(holdings: Holdings, area_name: String, cell: Vector2i) -> String:
	if holdings == null:
		return ""
	for id in holdings.places_in(area_name):
		if holdings.place(id)["kind"] == KIND and holdings.covers(id, cell) and holdings.holder(id) == TOWN:
			return id
	return ""


# --- Reading -------------------------------------------------------------------------

## Every store's place id, sorted.
func places() -> Array[String]:
	var out: Array[String] = []
	out.assign(_stores.keys())
	out.sort()
	return out


## How many of resource [param what] [param place] holds; for an item id,
## how many of that item.
func count(place: String, what: String) -> int:
	if not _stores.has(place):
		return 0
	if what in RESOURCES:
		return int(_stores[place]["resources"].get(what, 0))
	return _stores[place]["items"].count(what)


func has(place: String, what: String, amount := 1) -> bool:
	return count(place, what) >= amount


## [param place]'s resources, {name: count} for each of RESOURCES.
func resources(place: String) -> Dictionary:
	var out := {}
	for name in RESOURCES:
		out[name] = count(place, name)
	return out


## [param place]'s banked items, in the order they came.
func items(place: String) -> Array[String]:
	var out: Array[String] = []
	if _stores.has(place):
		out.assign(_stores[place]["items"])
	return out


## [param place]'s ledger, oldest first.
func ledger(place: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _stores.has(place):
		out.assign(_stores[place]["ledger"])
	return out


# --- Changing ------------------------------------------------------------------------

## Banks [param amount] of [param what] (a resource, or an item id: one item
## each) at [param place], brought [param by] someone [param from]
## somewhere. False (nothing banked) for no place, an amount under 1, or
## something that is neither a resource nor an item.
func deposit(place: String, what: String, amount := 1, by := "", from := "") -> bool:
	if place.is_empty() or amount < 1 or not (what in RESOURCES or Items.exists(what)):
		return false
	var store := _store(place)
	if what in RESOURCES:
		store["resources"][what] = int(store["resources"].get(what, 0)) + amount
	else:
		for i in amount:
			store["items"].append(what)
	_record(store, what, amount, by, from)
	print("[stockpile] %s banked %d %s at %s (from %s), step %d" % [by if by != "" else "someone", amount,
		Items.name_of(what) if what not in RESOURCES else what, place, from if from != "" else "nowhere said", now()])
	return true


## Takes [param amount] of [param what] from [param place] for the town's
## own use ([param reason]: a production job, the shop, a raid). False
## (nothing taken) if it hasn't that many.
func take(place: String, what: String, amount := 1, reason := "") -> bool:
	if amount < 1 or not has(place, what, amount):
		return false
	var store: Dictionary = _stores[place]
	if what in RESOURCES:
		store["resources"][what] = int(store["resources"][what]) - amount
	else:
		for i in amount:
			store["items"].erase(what)
	_record(store, what, -amount, reason, "")
	return true


func _store(place: String) -> Dictionary:
	if not _stores.has(place):
		var counts := {}
		for name in RESOURCES:
			counts[name] = 0
		_stores[place] = {"resources": counts, "items": [], "ledger": []}
	return _stores[place]


func _record(store: Dictionary, what: String, amount: int, by: String, from: String) -> void:
	var ledger: Array = store["ledger"]
	ledger.append({"step": now(), "what": what, "count": amount, "by": by, "from": from})
	if ledger.size() > LEDGER_SIZE:
		ledger.pop_front()


# --- Saving --------------------------------------------------------------------------

## For the snapshot: place id -> {resources, items, ledger}.
func to_dict() -> Dictionary:
	return _stores.duplicate(true)


## to_dict's [param saved] over what is here. A store whose place is no
## longer in the levels is kept (nothing banked is lost); counts under 0
## and items there are not are left out with a word.
func from_dict(saved: Dictionary) -> void:
	for place: Variant in saved:
		var entry: Variant = saved[place]
		if not entry is Dictionary:
			print("[stockpile] the snapshot's store %s makes no sense; left out" % [place])
			continue
		var store := _store(str(place))
		var counts: Variant = entry.get("resources", {})
		if counts is Dictionary:
			for name in RESOURCES:
				var value: Variant = counts.get(name, 0)
				store["resources"][name] = maxi(int(value), 0) if value is float or value is int else 0
		var banked: Variant = entry.get("items", [])
		if banked is Array:
			for item: Variant in banked:
				if Items.exists(str(item)):
					store["items"].append(str(item))
				else:
					print("[stockpile] the snapshot's %s holds %s, which is no item; left out" % [place, item])
		var lines: Variant = entry.get("ledger", [])
		if lines is Array:
			for line: Variant in lines.slice(-LEDGER_SIZE):
				if line is Dictionary:
					store["ledger"].append({"step": int(line.get("step", 0)), "what": str(line.get("what", "")),
						"count": int(line.get("count", 0)), "by": str(line.get("by", "")), "from": str(line.get("from", ""))})
