class_name Resident
extends GridEntity
## A town's resident as a body in it (decision 333). The record is the
## economy's (Towns.residents, Production.worker); the body is Main's,
## spawned while the zone is awake (Main._sync_residents) and never saved:
## at a spawn it stands where its day puts it at that hour.
##
## Its day is levels/residents.json: by its trade, the hours at work and at
## home (DayNight's clock), the square any other hour. Main gives it its
## places (cells: the inside of the building its trade works in, its home,
## the square round the town's store); it walks there as a companion does
## (World.find_path, a route kept till it is blocked) and, in the square,
## strolls to another cell now and then. A raider (a monster not of the
## wild, or a wolf) it sees or hears, or a blow, and it hides at home till
## none has been about for HIDE_TICKS. It never fights and says nothing
## yet. Far from every player and companion (FAR_TILES) it thinks every
## FAR_EVERY ticks and is walked there at once (World.walk), as monsters
## are by the world tick.

enum Doing { WORK, HOME, SQUARE, HIDE }
const FILE := "res://levels/residents.json"
const SIGHT_RANGE := 7
## It looks and listens for raiders every so many ticks.
const LOOK_EVERY := 5
## It stays hidden so long after a raider was last about (ticks).
const HIDE_TICKS := 600
## In the square it strolls to another cell about this often (ticks).
const WANDER_TICKS := 80
const FAR_TILES := 30
const FAR_EVERY := 20
## A step blocked so many times, and it looks for a new way.
const STUCK_TRIES := 3
const NO_CELL := Vector2i(-99999, -99999)
const PLACE_OF := {Doing.WORK: "work", Doing.HOME: "home", Doing.SQUARE: "square", Doing.HIDE: "home"}

## Production's worker id ("companion:<player id>" for a companion resting
## in town: decision 333 amended), the town (a stockpile place id) and its
## trade ("" for none: the default day, its work the square).
var worker_id := ""
## A companion's player's id, "" for a town's own resident.
var player_id := ""
## Its name (the worker's, or the companion's), and for a companion her own
## card (her record's), "" for a town's resident: theirs is rolled.
var person := ""
var card := ""
## Its town's name, as the world map has it (Main's).
var town_name := ""
var town := ""
var trade := ""
## Where it goes: "work", "home", "square" -> Rect2i of cells (Main's).
var places: Dictionary = {}
var senses: Senses
var doing := Doing.SQUARE
var _goal := NO_CELL
var _route: Array[Vector2i] = []
var _stuck := 0
var _hide_until := -1
var _wander_at := -1
var _listened := -1
static var _days := {}


## Its voice (decision 336): asked only when spoken to, one ask at a time
## for all residents (Main), with facts only: who it is, its work, the
## town's wants and shop, the hour and weather.
const VOICE := """You are %s, who lives in %s and works there%s. You are no adventurer: you live and work in the town. Someone has just spoken to you.

Who you are:
%s

What is true now:
%s

Say what you would say out loud right now, as yourself, in one or two short sentences, to %s, speaking to them as "you". Your words are only what you say aloud: never describe what you do. What is written above is what you know; anything else you don't know, so say so rather than guess."""


func _init() -> void:
	super()
	max_hp = 10
	move_ticks = 3.0
	senses = Senses.new(self, SIGHT_RANGE, -1.0)


## The days by trade, read on first use.
static func days() -> Dictionary:
	if _days.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if data is Dictionary:
			for key: String in data:
				if not key.begins_with("_") and data[key] is Dictionary:
					_days[key] = data[key]
		if not _days.has("default"):
			_days["default"] = {"work": [8, 18], "home": [21, 6]}
	return _days


## What one of [param of_trade] is doing at [param hour] (0..24): WORK, HOME
## or SQUARE.
static func doing_at(of_trade: String, hour: float) -> Doing:
	var day: Dictionary = days().get(of_trade, days()["default"])
	if _within(hour, day.get("work", [])):
		return Doing.WORK
	if _within(hour, day.get("home", [])):
		return Doing.HOME
	return Doing.SQUARE


static func _within(hour: float, span: Variant) -> bool:
	if not span is Array or span.size() != 2:
		return false
	var from := float(span[0])
	var to := float(span[1])
	return from <= hour and hour < to if from <= to else hour >= from or hour < to


func _sim_tick() -> void:
	if not Net.is_authority():
		return
	var far := _far()
	if far and (World.tick + id) % FAR_EVERY != 0:
		return
	if not far and World.tick % LOOK_EVERY == 0:
		_look()
	if World.tick - hurt_tick <= 1:
		_hide_until = World.tick + HIDE_TICKS
	var now := Doing.HIDE if World.tick < _hide_until else doing_at(trade, DayNight.hour(DayNight.now()))
	if now != doing or _goal == NO_CELL:
		doing = now
		_pick_goal()
	elif doing == Doing.SQUARE and tile == _goal and World.tick >= _wander_at:
		_pick_goal()
	if far:
		if tile != _goal:
			World.walk(self, _goal, FAR_EVERY)
		return
	_step()


## Whether no player or companion is within FAR_TILES.
func _far() -> bool:
	for entity in World.sought():
		if entity.spawned and World.distance(tile, entity.tile) <= FAR_TILES:
			return false
	return true


## A raider seen, or heard since it last listened (a monster not of the
## wild, or a wolf, or a fight): it hides.
func _look() -> void:
	for entity in World.monsters():
		if entity.spawned and not Companion.harmless(entity) \
				and World.distance(tile, entity.tile) <= SIGHT_RANGE and senses.sees(entity):
			_hide_until = World.tick + HIDE_TICKS
			return
	for noise: Dictionary in senses.heard:
		if int(noise["tick"]) <= _listened:
			continue
		var source: Variant = noise["source"]
		var raider: bool = is_instance_valid(source) and source is Monster and not Companion.harmless(source)
		if raider or noise["kind"] == &"fight" or noise["kind"] == &"door_broken":
			_hide_until = World.tick + HIDE_TICKS
	if not senses.heard.is_empty():
		_listened = int(senses.heard.back()["tick"])


## Where it goes for what it is doing now: where it stands, if that is in
## the place already (but for a stroll in the square), else a free cell of
## the place; with no such place, the square's.
func _pick_goal() -> void:
	_route.clear()
	_stuck = 0
	var area: Rect2i = places.get(PLACE_OF[doing], places.get("square", Rect2i()))
	if area.size == Vector2i.ZERO:
		_goal = tile
		return
	if area.has_point(tile) and not (doing == Doing.SQUARE and _goal != NO_CELL):
		_goal = tile
	else:
		_goal = _free_cell(area)
	if doing == Doing.SQUARE:
		_wander_at = World.tick + WANDER_TICKS + (id * 7) % 40


## A free cell of [param area], from a start its id and the tick choose;
## where it stands if none.
func _free_cell(area: Rect2i) -> Vector2i:
	var count := area.size.x * area.size.y
	var start := absi(id * 31 + World.tick) % count
	for i in count:
		var at := area.position + Vector2i((start + i) % count % area.size.x, (start + i) % count / area.size.x)
		if at != tile and World.is_free(at):
			return at
	return tile


## The voice ask for [param line], said to it by [param speaker]
## (CompanionMind.voice's shape, plain text back).
func voice_ask(speaker: String, line: String, serial: int) -> Dictionary:
	var system := VOICE % [person, town_name if not town_name.is_empty() else "a town", " as a " + trade if not trade.is_empty() else "", card_words(),
		" ".join(facts_now()), speaker]
	var user := "%s says to you: \"%s\"" % [speaker, line]
	return {"kind": "voice", "serial": serial, "trigger": "%s spoke to %s." % [speaker, person], "speaker": person,
		"system": system, "user": user, "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
		"spoken_to": true, "asked": true, "heard": line}


## Who it is: a companion's own card; else a card rolled as a companion's
## is, by its worker id (the same every time), its name and trade its own.
func card_words() -> String:
	if not card.is_empty():
		return card
	var traits := CompanionCard.roll(worker_id, person)
	traits.erase("aspiration")
	traits["profession"] = "a " + trade if not trade.is_empty() else "without a trade of %s own" % {"she": "her", "he": "his"}.get(str(traits.get("pronoun", "")), "their")
	return CompanionCard.plain_card(traits)


## What is true now, a sentence each: the hour and the weather, its work,
## what the town is short of, what its shop has.
func facts_now() -> Array[String]:
	var out: Array[String] = []
	var hour := Companion.time_words(DayNight.hour(DayNight.now()))
	var sky := ""
	if World.fields.outdoor and Companion.WEATHER_WORDS.has(str(World.fields.weather.get("kind", ""))):
		sky = ", and " + Companion.WEATHER_WORDS[World.fields.weather["kind"]]
	out.append("It is %s%s." % [hour, sky])
	out.append(work_words())
	if World.production != null:
		var short: Dictionary = World.production.signals_of(town, Production.items_catalog()).get("short", {})
		var wants: Array = short.keys()
		wants.sort()
		out.append("The town is short of %s." % _listed(wants) if not wants.is_empty() else "The town is short of nothing it needs.")
	if World.economy != null:
		var counts := {}
		for each: Dictionary in World.economy.goods(town):
			var what := str(each["id"]).replace("_", " ")
			counts[what] = int(counts.get(what, 0)) + 1
		var goods: Array = []
		var kinds: Array = counts.keys()
		kinds.sort()
		for what: String in kinds:
			goods.append(Companion.counted(what, counts[what]))
		out.append("The town's shop has %s." % _listed(goods) if not goods.is_empty() else "The town's shop has nothing for sale.")
	return out


## What it is making now, from its workshop's job (Production): what, how
## far along, and what went into it; or that it has no work and why.
func work_words() -> String:
	if World.production == null or trade.is_empty():
		return "You have no trade to work at."
	var shop_id := World.production.workshop_of(worker_id)
	if shop_id.is_empty():
		return "You have no workshop to work in yet: the town has no building for your trade."
	var job := World.production.job(int(World.production.workshop(shop_id).get("job", 0)))
	if job.is_empty():
		return "Your workshop is idle: you are making nothing now."
	var what := str(job.get("recipe", "")).replace("_", " ")
	if str(job.get("kind", "")) == "build":
		what = "the town's " + what.trim_prefix("build:").trim_prefix(Towns.REPAIR)
	var made: Array = []
	var resources: Dictionary = job.get("resources", {})
	for each: String in resources:
		made.append(Companion.counted(each.replace("_", " "), int(resources[each])))
	var into := ", from %s" % _listed(made) if not made.is_empty() else ""
	if str(job.get("state", "")) == "waiting":
		return "Your next work is %s, waiting for its materials." % Companion._a(what)
	if str(job.get("state", "")) != "working":
		return "Your next work is %s%s, not yet begun." % [Companion._a(what), into]
	var share := float(job.get("worked", 0)) / maxf(float(job.get("needed", 1)), 1.0)
	var far := "just begun" if share < 0.25 else "under half done" if share < 0.5 else "over half done" if share < 0.9 else "nearly done"
	return "You are making %s%s: it is %s." % [Companion._a(what), into, far]


## [param parts] in words: "a, b and c".
static func _listed(parts: Array) -> String:
	if parts.size() <= 1:
		return "" if parts.is_empty() else str(parts[0])
	return "%s and %s" % [", ".join(parts.slice(0, -1)), parts.back()]


## A step along its route to its goal, a new route when it has none or is
## stuck.
func _step() -> void:
	if tile == _goal or World.tick < next_move_tick:
		return
	if _route.is_empty():
		_route = World.find_path(tile, _goal, false)
		if _route.is_empty():
			_goal = tile  # No way there now: it waits, and chooses again later.
			return
	if World.try_move(self, _route[0] - tile):
		_route.pop_front()
		_stuck = 0
		return
	_stuck += 1
	if _stuck >= STUCK_TRIES:
		_route.clear()
		_stuck = 0
		if not World.is_free(_goal):
			_pick_goal()
