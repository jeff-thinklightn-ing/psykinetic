class_name WorldNews
extends RefCounted
## The "world" message (decision 446): what each player's world map needs
## that only the server has. Server side: who holds the places they know,
## the areas they have stood in and places they have come within SIGHT
## cells of (kept on their PlayerRecord, so it follows them between
## machines), and where the party is in other zones. A full message once
## they are in, then only what changed:
##   {"full": bool, "holdings": {place_id: [faction, strength]},
##    "known": {"areas": [...], "places": [...]},
##    "party": [{"name", "area", "kind": "player"|"companion"}],
##    "trade": [{"id", "from_area", "to_area", "areas", "caravans": [{"area", "fraction"}]}]}
## Holdings go only to players who know the place (fog). Client side,
## merge() folds each into Main.world_state. "trade" (decision 504): the
## trade routes through areas the player knows, and the caravans on them;
## sent like the party, whole when it changes; a client before it ignores it.
## "guide" (decision 551, sent by Main, not here): what the player's
## companion knows the way to, {"companion", "places": [place_id],
## "areas": [area]}, whole when it changes, kept through a full message.

## How near a place's cell a player comes to know it (Senses' sight range).
const SIGHT := 7

var holdings: Holdings
## (peer, data): sends data as a "world" message to that peer (Net.message_to).
var send: Callable
## () -> {peer: player id}: the players in the game.
var peers: Callable
## (player id) -> PlayerRecord, or null.
var record_of: Callable
## () -> [{name, area, kind, peer}]: every player and companion and where
## they are (peer: the player's own, or a companion's keeper's).
var members: Callable
## (known areas) -> the trade routes to show (TradeRoutes.shown); none when
## not set.
var trade: Callable
## Peers sent their full message.
var _full_sent: Dictionary[int, bool] = {}
## Peer -> the party list it was last sent.
var _party_sent: Dictionary[int, Array] = {}
## Peer -> the trade list it was last sent.
var _trade_sent: Dictionary[int, Array] = {}


func _init(with_holdings: Holdings) -> void:
	holdings = with_holdings
	# Holdings.take emits strength_changed too, so this one hears both a
	# place taken and its strength changed, once each. A bound method, not a
	# lambda: a lambda would hold this, which holds holdings, in holdings'
	# own signal, and neither would ever be freed.
	holdings.strength_changed.connect(_on_strength_changed)


func _on_strength_changed(id: String, _value: int) -> void:
	place_changed(id)


## Player [param peer] stands at [param cell] in [param area]: the area, and
## places within SIGHT, are known to them from now on; what is new is sent
## (with the holdings of the places just learned), unless their full
## message has yet to go, which will carry it.
func observe(peer: int, area: String, cell: Vector2i) -> void:
	var record := _record(peer)
	if record == null:
		return
	var areas: Array[String] = []
	if not area.is_empty() and not record.known_areas.has(area):
		record.known_areas.append(area)
		record.known_areas.sort()
		areas.append(area)
	var places: Array[String] = []
	for id in holdings.places_in(area):
		var place := holdings.place(id)
		var d: Vector2i = place["cell"] - cell
		if not record.known_places.has(id) and d.x * d.x + d.y * d.y <= SIGHT * SIGHT:
			record.known_places.append(id)
			places.append(id)
	if not places.is_empty():
		record.known_places.sort()
	if (areas.is_empty() and places.is_empty()) or not _full_sent.has(peer):
		return
	send.call(peer, {"full": false, "known": {"areas": areas, "places": places}, "holdings": _holdings_of(places)})


## Sends each player not yet sent it their full message, and each one
## whose party list changed the new one. Main calls it now and then.
func update() -> void:
	var now: Dictionary = peers.call()
	for peer: int in _full_sent.keys():
		if not now.has(peer):
			_full_sent.erase(peer)
			_party_sent.erase(peer)
			_trade_sent.erase(peer)
	var everyone: Array = members.call()
	for peer: int in now:
		var record := _record(peer)
		if record == null:
			continue
		var party := party_for(peer, everyone)
		var routes: Array = trade.call(record.known_areas) if trade.is_valid() else []
		if not _full_sent.has(peer):
			_full_sent[peer] = true
			_party_sent[peer] = party
			_trade_sent[peer] = routes
			send.call(peer, {"full": true, "holdings": _holdings_of(record.known_places),
				"known": {"areas": record.known_areas.duplicate(), "places": record.known_places.duplicate()}, "party": party,
				"trade": routes})
			continue
		var changed := {}
		if _party_sent.get(peer, []) != party:
			_party_sent[peer] = party
			changed["party"] = party
		if _trade_sent.get(peer, []) != routes:
			_trade_sent[peer] = routes
			changed["trade"] = routes
		if not changed.is_empty():
			changed["full"] = false
			send.call(peer, changed)


## [param peer] is sent its full message again on the next update: what
## it knows has shrunk (a regenerated area's places gone, decision 465),
## and a full message starts the client's state over.
func resend(peer: int) -> void:
	_full_sent.erase(peer)


## Place [param id] changed hands or strength: told to the players who know it.
func place_changed(id: String) -> void:
	if not peers.is_valid():
		return
	var now: Dictionary = peers.call()
	for peer: int in now:
		var record := _record(peer)
		if record != null and _full_sent.has(peer) and record.known_places.has(id):
			send.call(peer, {"full": false, "holdings": _holdings_of([id])})


## The party as [param peer] sees it from [param everyone] (members()):
## the others and the companions, not in its own zone, without peers,
## sorted by kind and name.
func party_for(peer: int, everyone: Array) -> Array:
	var here := ""
	for member: Dictionary in everyone:
		if member.get("kind") == "player" and int(member.get("peer", 0)) == peer:
			here = str(member.get("area", ""))
	var out: Array = []
	for member: Dictionary in everyone:
		var mine: bool = member.get("kind") == "player" and int(member.get("peer", 0)) == peer
		if mine or str(member.get("area", "")) == here:
			continue
		out.append({"name": str(member.get("name", "")), "area": str(member.get("area", "")), "kind": str(member.get("kind", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a["kind"], a["name"], a["area"]] < [b["kind"], b["name"], b["area"]])
	return out


func _holdings_of(ids: Array[String]) -> Dictionary:
	var out := {}
	for id in ids:
		if not holdings.place(id).is_empty():
			out[id] = [holdings.holder(id), holdings.strength(id)]
	return out


func _record(peer: int) -> PlayerRecord:
	var id := str((peers.call() as Dictionary).get(peer, "")) if peers.is_valid() else ""
	return record_of.call(id) if not id.is_empty() and record_of.is_valid() else null


## Client: [param data] (a "world" message) folded into [param state]
## ({holdings, known_areas, known_places, party}); a full one replaces it.
static func merge(state: Dictionary, data: Dictionary) -> Dictionary:
	var out := {"holdings": {}, "known_areas": [], "known_places": [], "party": [], "trade": []} if data.get("full", false) else state.duplicate(true)
	for key in ["holdings", "known_areas", "known_places", "party", "trade"]:
		if not out.has(key):
			out[key] = {} if key == "holdings" else []
	var held: Variant = data.get("holdings", {})
	if held is Dictionary:
		for id: Variant in held:
			out["holdings"][str(id)] = held[id]
	var known: Variant = data.get("known", {})
	if known is Dictionary:
		for pair: Array in [["areas", "known_areas"], ["places", "known_places"]]:
			for each: Variant in known.get(pair[0], []):
				if not out[pair[1]].has(str(each)):
					out[pair[1]].append(str(each))
			out[pair[1]].sort()
	if data.get("party") is Array:
		out["party"] = (data["party"] as Array).duplicate(true)
	if data.get("trade") is Array:
		out["trade"] = (data["trade"] as Array).duplicate(true)
	# What the player's companion knows the way to (decision 551, Main's):
	# whole when it changes, and kept through a full message.
	if data.get("guide") is Dictionary:
		out["guide"] = (data["guide"] as Dictionary).duplicate(true)
	elif data.get("full", false) and state.get("guide") is Dictionary:
		out["guide"] = (state["guide"] as Dictionary).duplicate(true)
	return out
