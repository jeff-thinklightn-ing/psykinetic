class_name Stockpile
extends RefCounted
## The town's store: what players have brought home. Each store belongs to a
## place of kind "stockpile" (Holdings, by place id "<area>/<key>"), and
## holds counts of the raw resources (RESOURCES: gold, ore, wood, cloth,
## food) and the gear banked there, by its uid in the item book (book,
## World.items), its history kept there and never copied here: in the
## book it is at "stockpile:<place>", carried by nobody. A ledger keeps
## the last LEDGER_SIZE changes, stamped with the World's steps.
##
## Things reach it through a depot (a Chest with depot set) inside a
## stockpile place the town holds: World.try_transfer banks what is put in
## at once, a resource item (Items.yield_of) as its yield, its instance
## ended, gear as itself. Picking loot up counts for nothing. Players never take from it:
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
## The item book the banked gear's uids are in.
var book: ItemBook

## Place id -> {resources: {name: count}, items: Array[int] (uids),
## ledger: Array[{step, what, count, by, from, uid}]}.
var _stores: Dictionary[String, Dictionary] = {}


## The stores [param saved] (to_dict's) holds, their gear in [param with_book]
## (a new one if none), on [param with_clock].
func _init(saved := {}, with_clock := Callable(), with_book: ItemBook = null) -> void:
	clock = with_clock
	book = with_book if with_book != null else ItemBook.new(with_clock)
	from_dict(saved)


## The book's holder key for [param place]'s store.
static func holder(place: String) -> String:
	return "stockpile:" + place


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
	return _stores[place]["items"].filter(func(uid: int) -> bool: return book.id_of(uid) == what).size()


func has(place: String, what: String, amount := 1) -> bool:
	return count(place, what) >= amount


## [param place]'s resources, {name: count} for each of RESOURCES.
func resources(place: String) -> Dictionary:
	var out := {}
	for name in RESOURCES:
		out[name] = count(place, name)
	return out


## [param place]'s banked gear, uids in the order they came.
func items(place: String) -> Array[int]:
	var out: Array[int] = []
	if _stores.has(place):
		out.assign(_stores[place]["items"])
	return out


## [param place]'s banked gear by id (ItemBook.id_of), in the order it came.
func item_ids(place: String) -> Array[String]:
	var out: Array[String] = []
	for uid in items(place):
		out.append(book.id_of(uid))
	return out


## [param place]'s shop: the things the town has made for sale, uids in the
## order they came (still the town's; prices come with the shop itself).
func shop(place: String) -> Array[int]:
	var out: Array[int] = []
	if _stores.has(place):
		out.assign(_stores[place]["shop"])
	return out


## Every uid every store and its shop holds (ItemBook.orphans' known).
func all_items() -> Array[int]:
	var out: Array[int] = []
	for place: String in _stores:
		out.append_array(_stores[place]["items"])
		out.append_array(_stores[place]["shop"])
	return out


## [param place]'s ledger, oldest first.
func ledger(place: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _stores.has(place):
		out.assign(_stores[place]["ledger"])
	return out


# --- Changing ------------------------------------------------------------------------

## Banks [param amount] of resource [param what] at [param place], brought
## [param by] someone [param from] somewhere. False (nothing banked) for no
## place, an amount under 1, or no such resource.
func deposit(place: String, what: String, amount := 1, by := "", from := "") -> bool:
	if place.is_empty() or amount < 1 or what not in RESOURCES:
		return false
	var store := _store(place)
	store["resources"][what] = int(store["resources"].get(what, 0)) + amount
	_record(store, what, amount, by, from)
	print("[stockpile] %s banked %d %s at %s (from %s), step %d" % [by if by != "" else "someone", amount,
		what, place, from if from != "" else "nowhere said", now()])
	return true


## Banks the gear [param uid] (in the book, not already here) at
## [param place], brought [param by] someone [param from] somewhere, at
## [param zone] [param tile]: the book has it at the store, carried by
## nobody, with an [param event] ("banked"; none for "", as for a thing a
## cancelled job gives back). False (nothing banked) if not.
func bank(place: String, uid: int, by := "", from := "", zone := "", tile := Vector2i(-1, -1), event := "banked") -> bool:
	if place.is_empty() or not book.has(uid) or uid in all_items():
		return false
	var store := _store(place)
	store["items"].append(uid)
	book.place(uid, holder(place))
	if not event.is_empty():
		book.note(uid, event, "%s by %s" % [place, by if by != "" else "someone"], zone, tile)
	_record(store, book.id_of(uid), 1, by, from, uid)
	print("[stockpile] %s banked %s (#%d) at %s (from %s), step %d" % [by if by != "" else "someone",
		Items.name_of(book.id_of(uid)), uid, place, from if from != "" else "nowhere said", now()])
	return true


## Takes [param amount] of resource [param what] from [param place] for the
## town's own use ([param reason]: a production job, the shop, a raid).
## False (nothing taken) if it hasn't that many.
func take(place: String, what: String, amount := 1, reason := "") -> bool:
	if amount < 1 or what not in RESOURCES or not has(place, what, amount):
		return false
	var store: Dictionary = _stores[place]
	store["resources"][what] = int(store["resources"][what]) - amount
	_record(store, what, -amount, reason, "")
	return true


## Takes the gear [param uid] out of [param place] for the town's use
## ([param reason]: the shop, the smith): in the book it is nowhere until
## World.put_item puts it somewhere. False (nothing taken) if it isn't here.
func take_item(place: String, uid: int, reason := "") -> bool:
	if not _stores.has(place) or uid not in _stores[place]["items"]:
		return false
	var store: Dictionary = _stores[place]
	store["items"].erase(uid)
	book.place(uid, "")
	_record(store, book.id_of(uid), -1, reason, "", uid)
	return true


## Puts [param uid] (in the book, held by no store) in [param place]'s
## shop, made or reworked [param by] someone. False if it can't.
func stock_shop(place: String, uid: int, by := "") -> bool:
	if place.is_empty() or not book.has(uid) or uid in all_items():
		return false
	var store := _store(place)
	store["shop"].append(uid)
	book.place(uid, shop_holder(place))
	_record(store, book.id_of(uid), 1, by, "to the shop", uid)
	return true


## The book's holder key for [param place]'s shop.
static func shop_holder(place: String) -> String:
	return "shop:" + place


func _store(place: String) -> Dictionary:
	if not _stores.has(place):
		var counts := {}
		for name in RESOURCES:
			counts[name] = 0
		_stores[place] = {"resources": counts, "items": [], "shop": [], "ledger": []}
	return _stores[place]


func _record(store: Dictionary, what: String, amount: int, by: String, from: String, uid := 0) -> void:
	var ledger: Array = store["ledger"]
	ledger.append({"step": now(), "what": what, "count": amount, "by": by, "from": from, "uid": uid})
	if ledger.size() > LEDGER_SIZE:
		ledger.pop_front()


# --- Saving --------------------------------------------------------------------------

## For the snapshot: place id -> {resources, items, ledger}.
func to_dict() -> Dictionary:
	return _stores.duplicate(true)


## to_dict's [param saved] over what is here, the book already loaded. A
## store whose place is no longer in the levels is kept (nothing banked is
## lost). Gear saved as an id (from before uids) gets an instance
## ("migrated"); a uid the book no longer has, counts under 0 and items
## there are not are left out with a word.
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
				var uid := 0
				if item is String and Items.exists(item):
					uid = book.mint(item, "migrated", str(place))
					book.place(uid, holder(str(place)))
				elif (item is float or item is int) and book.has(int(item)) and int(item) not in all_items():
					uid = int(item)
				if uid == 0:
					print("[stockpile] the snapshot's %s holds %s, which is no item in the book; left out" % [place, item])
					continue
				store["items"].append(uid)
		var for_sale: Variant = entry.get("shop", [])
		if for_sale is Array:
			for item: Variant in for_sale:
				if (item is float or item is int) and book.has(int(item)) and int(item) not in all_items():
					store["shop"].append(int(item))
				else:
					print("[stockpile] the snapshot's %s shop holds %s, which is no item in the book; left out" % [place, item])
		var lines: Variant = entry.get("ledger", [])
		if lines is Array:
			for line: Variant in lines.slice(-LEDGER_SIZE):
				if line is Dictionary:
					store["ledger"].append({"step": int(line.get("step", 0)), "what": str(line.get("what", "")),
						"count": int(line.get("count", 0)), "by": str(line.get("by", "")), "from": str(line.get("from", "")),
						"uid": int(line.get("uid", 0))})
