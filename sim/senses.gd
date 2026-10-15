class_name Senses
extends RefCounted
## What an agent (a monster now, a companion later) sees, hears and
## remembers: one layer both use. It never acts; its agent asks it.
##
## Sight (sees): within sight_range; in its cone (cone_cos of its facing),
## unless within NOTICE_ALWAYS; lit (the target glows, the map's light, or
## a lantern carried near it, at least DARK); and in line of sight. The
## cheap checks first, line of sight last.
##
## Hearing: World.noise pushes a noise to the agents within its radius as it
## happens (hear); nobody listens every tick. The last HEARD_MAX are kept.
##
## Memory: where and when (World.tick) it last saw each one it saw
## (last_seen), dropped after MEMORY_TICKS. Every time is a World.tick, so
## an agent that thinks one tick in four reads the same.

## Light under which it is too dark to see (World.light_at, 0..1), and
## under which it is too dark even for a glimpse (glimpses).
const DARK := 0.35
const GLIMPSE := 0.15
## So near (cells) it is noticed whatever the light or the way it faces.
const NOTICE_ALWAYS := 1
## A cone of 120 degrees: the cosine of half of it.
const CONE_COS := 0.5
const HEARD_MAX := 8
## How far (cells) each noise carries (World.noise), by kind: "step" (a
## player's; others' by their mass, step_radius), "speech" (in capitals a
## shout; /w, a whisper), "fight" (a blow or a swing), "door" (opened or
## shut), "door_struck", "door_broken", "door_rattle" (a locked door
## tried), "latch" (a lock or a bar worked), "thud" (something dropped or
## landing, light or heavy), "rummage" (a chest's things taken or put),
## "break" (a crate or a barrel smashed), "call" (a monster calling its
## side for help), "rout" (a monster breaking and running). The sound of
## each is played as
## far as it carries (the sound worktree's slots name these kinds).
const NOISE_STEP := 3
const NOISE_SPEECH := 10
const NOISE_SHOUT := 20
const NOISE_WHISPER := 2
const NOISE_FIGHT := 5
const NOISE_DOOR := 6
const NOISE_DOOR_STRUCK := 10
const NOISE_DOOR_BROKEN := 14
const NOISE_RATTLE := 6
const NOISE_LATCH := 3
const NOISE_THUD_LIGHT := 2
const NOISE_THUD_HEAVY := 4
const NOISE_RUMMAGE := 4
const NOISE_BREAK := 8
const NOISE_CALL := 12
const NOISE_ROUT := 8
## A step's noise by mass: NOISE_STEP for a player's (80), STEP_MASS a cell
## of it, from STEP_RADIUS_MIN to STEP_RADIUS_MAX.
const STEP_MASS := 27.0
const STEP_RADIUS_MIN := 2
const STEP_RADIUS_MAX := 4
const MEMORY_TICKS := 600

var agent: GridEntity
var sight_range := 7
## Off (-1.0 or less): it sees all the way round.
var cone_cos := CONE_COS
## {at, radius, kind, source, tick}, oldest first.
var heard: Array[Dictionary] = []
## When it last heard anything (World.tick; -1 never): a number to compare
## each think, where looking at what it heard is not.
var last_tick := -1
## Instance id -> {at, tick}.
var _seen: Dictionary[int, Dictionary] = {}


func _init(owner: GridEntity, range_cells := 7, cone := CONE_COS) -> void:
	agent = owner
	sight_range = range_cells
	cone_cos = cone


## Whether it sees [param entity] now; [param d], its distance (Chebyshev)
## when the caller has it already. Remembered when seen.
func sees(entity: GridEntity, d := -1, in_cone := true) -> bool:
	var at := entity.tile
	var from := agent.tile
	if d < 0:
		d = maxi(absi(at.x - from.x), absi(at.y - from.y))
	# Fog and rain shorten sight (Weather), but a carried light shows as far.
	if d > (sight_range if entity.emit_light > 0.0 else sight_range * World.weather_sight_at(from)):
		return false
	if d > NOTICE_ALWAYS:
		if in_cone and not _in_cone(at):
			return false
		if entity.emit_light <= 0.0 and not is_lit(at):
			return false
	if not World.has_line_of_sight(from, at):
		return false
	_seen[entity.get_instance_id()] = {"at": at, "tick": World.tick}
	return true


## Whether it glimpses [param entity], not seeing it (sees false): in
## range, in its cone and in line of sight, but lit only dimly (GLIMPSE or
## more, under DARK) and carrying no light. [param d] as sees.
func glimpses(entity: GridEntity, d := -1) -> bool:
	var at := entity.tile
	if d < 0:
		d = maxi(absi(at.x - agent.tile.x), absi(at.y - agent.tile.y))
	if d <= NOTICE_ALWAYS or d > sight_range * World.weather_sight_at(agent.tile) or entity.emit_light > 0.0 or not _in_cone(at):
		return false
	var light := _light(at, DARK)
	return light >= GLIMPSE and light < DARK and World.has_line_of_sight(agent.tile, at)


## Whether it can see [param cell] (a spot, not someone): in range, in its
## cone, lit ([param dark] or more: light_level) and in line of sight.
func sees_cell(cell: Vector2i, dark := DARK) -> bool:
	var from := agent.tile
	if cell == from:
		return true
	var d := maxi(absi(cell.x - from.x), absi(cell.y - from.y))
	if d > NOTICE_ALWAYS and d > sight_range * World.weather_sight_at(from):
		return false
	if d > NOTICE_ALWAYS and (not _in_cone(cell) or not is_lit(cell, dark)):
		return false
	return World.has_line_of_sight(from, cell)


func _in_cone(at: Vector2i) -> bool:
	if cone_cos <= -1.0:
		return true
	var offset := Vector2(at - agent.tile)
	var facing := Vector2(agent.facing)
	# Unnormalized: offset . facing >= cos * |offset| * |facing|.
	return offset.dot(facing) >= cone_cos * offset.length() * facing.length()


## Whether [param cell] has light enough ([param dark]) to see by: the
## map's (a lookup), else the lanterns carried near it
## (World.carried_lights, a short list), stopping once there is enough.
static func is_lit(cell: Vector2i, dark := DARK) -> bool:
	return _light(cell, dark) >= dark


## The light at [param cell], 0 dark to 1, as is_lit counts it: the map's
## and the carried lanterns' (for "it is dark there").
static func light_level(cell: Vector2i) -> float:
	return minf(_light(cell, INF), 1.0)


static func _light(cell: Vector2i, enough: float) -> float:
	var light := World.light_at(cell, false)
	if light >= enough:
		return light
	for carrier in World.carried_lights():
		var d := maxi(absi(carrier.tile.x - cell.x), absi(carrier.tile.y - cell.y))
		if d > Fields.CARRIED_REACH:
			continue
		light += World.fields.carried_light(World, carrier.tile, cell, carrier.emit_light)
		if light >= enough:
			return light
	return light


## World.noise: it heard [param kind] at [param at].
## [param muffled]: through a wall or a closed door.
func hear(at: Vector2i, radius: int, kind: StringName, source: GridEntity, muffled := false) -> void:
	if heard.size() >= HEARD_MAX:
		heard.pop_front()
	heard.append({"at": at, "radius": radius, "kind": kind, "source": source, "tick": World.tick, "muffled": muffled})
	last_tick = World.tick


## The noises heard after [param tick], oldest first: {at, radius, kind,
## tick, muffled, source}, source who made it only if it sees them now (asked now,
## not when the noise came), else null.
func heard_since(tick: int) -> Array[Dictionary]:
	var since: Array[Dictionary] = []
	for noise in heard:
		if int(noise["tick"]) > tick:
			var told := noise.duplicate()
			var source: Variant = noise["source"]
			told["source"] = source if is_instance_valid(source) and (source as GridEntity).spawned \
					and sees(source) else null
			since.append(told)
	return since


## Lets go of all it saw and heard (a new zone, a rebuilt one).
func forget() -> void:
	heard.clear()
	last_tick = -1
	_seen.clear()


## Where and when it last saw [param entity] ({at, tick}), or {} if not
## within MEMORY_TICKS.
func last_seen(entity: GridEntity) -> Dictionary:
	var id := entity.get_instance_id()
	var seen: Dictionary = _seen.get(id, {})
	if not seen.is_empty() and World.tick - int(seen["tick"]) > MEMORY_TICKS:
		_seen.erase(id)
		return {}
	return seen


## How far [param entity]'s steps carry: by its mass (a sneak's 2, a
## player's 3, anything of 100 or more 4).
static func step_radius(entity: GridEntity) -> int:
	return clampi(roundi(entity.mass / STEP_MASS), STEP_RADIUS_MIN, STEP_RADIUS_MAX)


## How far [param line] carries said aloud: a shout when it has three
## letters or more and none of them small.
static func speech_radius(line: String) -> int:
	var letters := 0
	for c in line:
		if c.to_upper() != c.to_lower():
			if c != c.to_upper():
				return NOISE_SPEECH
			letters += 1
	return NOISE_SHOUT if letters >= 3 else NOISE_SPEECH


## The one of the eight ways round (Monster.AROUND) nearest the way from
## [param from] to [param to]; ZERO when they are the same cell.
static func way_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var offset := Vector2(to - from)
	if offset == Vector2.ZERO:
		return Vector2i.ZERO
	# Clockwise from north, in cell space (y down).
	var index := posmod(roundi(rad_to_deg(atan2(offset.x, -offset.y)) / 45.0), 8)
	return Monster.AROUND[index]
