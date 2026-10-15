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
