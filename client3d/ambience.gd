class_name Ambience
extends Node
## The beds of sound under the game (decision 270): each amb.* slot a
## looping, flat bed on the Ambience bus, its loudness weighed from where
## the listener is and what the sky is doing, and eased toward it so beds
## cross-fade as you move, as the day turns and as the weather changes.
##
## weights() says how loud each bed should be (0..1), from:
## - the zone (the level's terrain "zone": outdoors, indoors, cave,
##   dungeon): outdoors the forest's dawn, day and night beds by the clock
##   (DayNight: day by the sky's light, dawn round 6 o'clock), the wind,
##   rain and storm by the weather (World.fields.weather); under stone the
##   dungeon's bed;
## - the sky over the listener (World.fields.under_sky): under a roof the
##   outdoor beds are quieter and muffled (the Ambience bus's low-pass twin);
## - rain quietening the birds;
## - a town: its day or night bed within TOWN_NEAR cells of a building that
##   serves one, fading out by TOWN_FAR;
## - a forest's canopy (decision 466) round the view (Client3D's eased
##   cover, the mean of Fields.canopy_at the drawn canopy uses): the deep
##   forest's day and night beds taking over from the open forest's as the
##   roof closes, rain heard on the crowns instead of falling through, and
##   the drips after it as Weather.drip_at has them (decision 477: the
##   drawn drops read the same).
## A torch is a point, not a bed: the torch loop (amb.torch_fire) plays from
## the nearest torch within hearing (Sfx.hearing, its slot's range). So
## does the barrow's hidden door's draft (amb.draft, 608 amended), from its
## edge, a clue for those who stand close, until the door is opened.
## A camp's fire (777, sound's side: a rest camp's, a raid camp's) is one
## too: amb.campfire, fuller and heard further, from the nearest heard.
## Night's own voices are calls, not beds (Jeff: "no birds at night, maybe
## owls bats"): now and then an owl (amb.owl) up in the trees round the
## listener, more often under a forest's roof, and bats (amb.bat) overhead
## by a canopy's edges and clearings and by a town wall's towers; both
## sparse, hushed by rain, at the rates calls() gives. No insects (decision
## 578 amended; Jeff: "the cricket noise is not good, it is a constant
## rattle"): the night beds keep no take with steady sound over 4 kHz, so
## the town's and the deep forest's are empty and the open forest's is its
## owls.
## A stream (decision 505's terrain "streams") is a line, not a bed: its
## loop (amb.stream) plays from the point of its course nearest the
## listener (nearest_on), sliding along the water as they move, heard
## before the trees let it be seen and muffled only by walls (Sfx.hearing).
## Where a stream falls (decision 557: Client3D.stream_falls) its fall is
## heard over it, from the fall (amb.falls), louder the further it drops.
## A bed with no takes plays nothing.

## Seconds a bed takes to ease most of the way to its new loudness.
const FADE_SECONDS := 2.0
## Weights are worked out this often (s); the loudness eases every frame.
const WEIGH_EVERY := 0.25
## Under a roof, outdoor beds at this share of their weight, muffled.
const ROOFED := 0.35
## How much rain quietens the birds (at full rain).
const RAIN_HUSH := 0.7
## Under a full roof: the share of the open forest's beds the deep forest's
## take over, and the share of the rain kept off (heard on the crowns).
const DEEP := 0.8
const CANOPY_RAIN := 0.7
## A town's bed: full within TOWN_NEAR cells of one of its buildings, gone
## by TOWN_FAR.
const TOWN_NEAR := 10.0
const TOWN_FAR := 22.0
## The hour dawn's bed peaks, and how many hours either side it fades over.
const DAWN_HOUR := 6.2
const DAWN_HOURS := 1.4
## Seconds between owl calls on average at night under a full roof (four
## times as long in the open), and between bats where they are most at home.
const OWL_SECONDS := 45.0
const BAT_SECONDS := 20.0
## Bats by a town wall's tower: always within TOWER_NEAR cells, none by
## TOWER_FAR.
const TOWER_NEAR := 4.0
const TOWER_FAR := 12.0
## A stream's fall (decision 557): dB over amb.falls' own at the least fall
## and at FALL_LOUDEST metres and over.
const FALL_DB := Vector2(-6.0, 0.0)
const FALL_LOUDEST := 1.0
## Below this weight a bed is stopped.
const SILENT := 0.01
const BEDS: Array[String] = ["amb.forest_dawn", "amb.forest_day", "amb.forest_night", "amb.field_wind",
	"amb.rain", "amb.storm", "amb.dungeon", "amb.town_day", "amb.town_night",
	"amb.forest_deep_day", "amb.forest_deep_night", "amb.rain_canopy", "amb.drips",
	"amb.mine_tunnel", "amb.mine_chamber", "amb.lair_cave"]
## A mine (769 amended (4)): a level whose decor has a mine's pieces. Under
## it no amb.dungeon (the crypt's cave bed): a near-silent tunnel's air or a
## chamber's, by how open the floor round the listener is (openness: the
## share of floor within OPEN_REACH cells, a tunnel's at TUNNEL_OPEN or
## less, a chamber's from CHAMBER_OPEN); a drop now and then (DRIP_SECONDS
## on average) from a floor cell DRIP_NEAR..DRIP_FAR off, a creak
## (CREAK_SECONDS) from the nearest arch or beam within TIMBER_NEAR, and a
## wall lamp's soft flame from the nearest lamp heard. Kept sparse: Jeff
## turned down the crypt's look as busy.
const MINE_KINDS: Array[String] = ["mine_lamp", "mine_arch", "mine_beam", "mine_track"]
const OPEN_REACH := 3
const TUNNEL_OPEN := 0.35
const CHAMBER_OPEN := 0.75
const DRIP_SECONDS := 12.0
const CREAK_SECONDS := 40.0
const DRIP_NEAR := 3
const DRIP_FAR := 10
const TIMBER_NEAR := 8
## A beast's cave (level.json "ambience": "cave_lair", 795 amended): its own
## bed, amb.lair_cave, in place of the crypt's or a mine's, and the mine's
## drops LAIR_DRIP_SLOWER times as rarely. Any level's skylights (797) let
## in the outside's faint air, amb.skylight_air, from the nearest heard.
## Its way out (terrain "lair_mouths", 795 amended (3)) breathes wind,
## amb.cave_mouth_wind, from the nearest mouth heard, fading inward.
const LAIR_DRIP_SLOWER := 2.0
## Beds of the open air: muffled under a roof.
const OUTDOOR_BEDS: Array[String] = ["amb.forest_dawn", "amb.forest_day", "amb.forest_night", "amb.field_wind",
	"amb.rain", "amb.storm", "amb.forest_deep_day", "amb.forest_deep_night", "amb.rain_canopy", "amb.drips"]

## The view this plays for (its listener, zone, torches and buildings).
var view: Client3D
## Bed -> its player (made the first time it is heard).
var players: Dictionary[String, AudioStreamPlayer] = {}
## Bed -> the weight it eases toward, and the weight it is at.
var targets: Dictionary[String, float] = {}
var levels: Dictionary[String, float] = {}
## Every bed this much quieter (dB): Music's duck under a fight.
var duck_db := 0.0
## A point loop's slot -> its player, at the source heard best (_place_point).
var points: Dictionary[String, AudioStreamPlayer3D] = {}
## The draft through the hidden door (608 amended), while it is heard.
var _draft: AudioStreamPlayer3D
## Stream (its index in the terrain's "streams") -> its held loop, while
## the listener is within its reach; and the streams they were made for.
var _streams := {}
var _stream_paths: Array = []
## Pond (its index in the terrain's "waters", a closed one) -> its held
## still-water lap (amb.pond, 805 amended (9)), as streams'.
var _ponds := {}
var _pond_waters: Array = []
## Fall (its index in Client3D.stream_falls) -> its held loop, as streams'.
var _falls := {}
var _fall_list: Array = []
var _since_weigh := INF
## The terrain the mine's parts were read from, and those parts (mine_parts);
## from the same terrain, its floor (cell -> true) and its skylights' cells.
var _mine_terrain: Dictionary = {}
var _mine := {}
var _floor: Dictionary[Vector2i, bool] = {}
var _skylights: Array[Vector2i] = []


func _process(delta: float) -> void:
	_since_weigh += delta
	if _since_weigh >= WEIGH_EVERY:
		_since_weigh = 0.0
		_weigh()
	var ease := 1.0 - exp(-delta * 3.0 / FADE_SECONDS)
	for bed: String in targets:
		var level := lerpf(float(levels.get(bed, 0.0)), targets[bed], ease)
		levels[bed] = level
		_set_level(bed, level)


## Every sound stopped as this goes: a stream still playing at quit is
## reported as a leak.
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null


## Each bed's weight now, for the view's listener.
func _weigh() -> void:
	if view == null or view.sfx == null or view.sfx.listener == null:
		return
	var cell: Vector2i = view.sfx.listener
	var steps := DayNight.now()
	var under_sky := World.fields.under_sky(cell) if World.fields != null else true
	var weather: Dictionary = World.fields.weather if World.fields != null else {}
	var zone := str(view._terrain.get("zone", "outdoors" if view._outdoor else "indoors"))
	var canopy := view._canopy_cover
	var drip := Weather.drip_at(World.fields.region, steps, canopy) if World.fields != null else 0.0
	var mine := _mine_of()
	var lair := str(view._terrain.get("ambience", ""))
	targets.assign(weights(zone, under_sky, DayNight.daylight(steps), DayNight.hour(steps), weather, _town_nearness(cell),
			canopy, drip, openness(mine["floor"], cell) if not mine.is_empty() else -1.0, lair))
	if lair == "cave_lair" and randf() < WEIGH_EVERY / (DRIP_SECONDS * LAIR_DRIP_SLOWER):
		_drip(cell, _floor)
	_place_point("amb.skylight_air", _skylights, cell)
	var mouths: Array[Vector2i] = []
	mouths.assign(view._terrain.get("lair_mouths", []))
	_place_point("amb.cave_mouth_wind", mouths, cell)
	_place_torch(cell)
	var lamps: Array[Vector2i] = []
	if not mine.is_empty():
		lamps = mine["lamps"]
		if randf() < WEIGH_EVERY / DRIP_SECONDS:
			_drip(cell, mine["floor"])
		if randf() < WEIGH_EVERY / CREAK_SECONDS:
			_creak(cell, mine["timbers"])
	_place_point("amb.lamp_hiss", lamps, cell)
	_place_draft(cell)
	_place_point("amb.forge_roar", lit_forges(view._terrain.get("plates", []), _door_open), cell)
	_place_streams(cell)
	_place_ponds(cell)
	_place_falls(cell)
	var rates := calls(zone, DayNight.daylight(steps), weather, canopy, _tower_nearness(cell))
	for slot: String in rates:
		if randf() < rates[slot] * WEIGH_EVERY:
			_call(slot, cell)


## How loud each bed should be (0..1) in [param zone] ("outdoors",
## "indoors", "cave", "dungeon"), [param under_sky] or under a roof, with
## the sky's [param daylight] (DayNight: NIGHT .. 1) at [param hour],
## [param weather] (Weather's: rain, wind, ... each 0..1) and
## [param town] (0..1: how near a town's buildings), under a forest's
## [param canopy] (0..1: its cover round the view) with its [param drip]
## (0..1, Weather.drip_at); in a mine (769 amended (4)) [param mine_open]
## its openness there (0 a tunnel .. 1 a chamber), else below 0; under
## level.json's [param lair] "ambience" (795 amended) "cave_lair", its bed.
static func weights(zone: String, under_sky: bool, daylight: float, hour: float, weather: Dictionary, town: float,
		canopy := 0.0, drip := 0.0, mine_open := -1.0, lair := "") -> Dictionary:
	var out := {}
	for bed in BEDS:
		out[bed] = 0.0
	var rain := float(weather.get("rain", 0.0))
	var wind := float(weather.get("wind", 0.0))
	if zone == "outdoors":
		var day := clampf((daylight - DayNight.NIGHT) / (1.0 - DayNight.NIGHT), 0.0, 1.0)
		var dawn := clampf(1.0 - absf(hour - DAWN_HOUR) / DAWN_HOURS, 0.0, 1.0)
		var hush := 1.0 - RAIN_HUSH * rain
		var open := 1.0 - DEEP * canopy
		out["amb.forest_dawn"] = dawn * hush * open
		out["amb.forest_day"] = day * (1.0 - dawn) * hush * open
		out["amb.forest_night"] = (1.0 - day) * (1.0 - dawn) * hush * open
		out["amb.forest_deep_day"] = day * (1.0 - dawn) * hush * canopy
		out["amb.forest_deep_night"] = (1.0 - day) * (1.0 - dawn) * hush * canopy
		out["amb.field_wind"] = wind
		var storm := clampf(rain * wind * 2.0 - 0.2, 0.0, 1.0) if str(weather.get("kind", "")) == "storm" else 0.0
		out["amb.storm"] = storm
		out["amb.rain"] = rain * (1.0 - storm) * (1.0 - CANOPY_RAIN * canopy)
		out["amb.rain_canopy"] = rain * canopy
		out["amb.drips"] = drip
		out["amb.town_day"] = town * day
		out["amb.town_night"] = town * (1.0 - day)
		if not under_sky:
			for bed in OUTDOOR_BEDS:
				out[bed] = out[bed] * ROOFED
	elif lair == "cave_lair":
		out["amb.lair_cave"] = 1.0
	elif mine_open >= 0.0:
		out["amb.mine_tunnel"] = 1.0 - mine_open
		out["amb.mine_chamber"] = mine_open
	else:
		out["amb.dungeon"] = 1.0 if zone in ["cave", "dungeon"] else 0.0
	return out


## The mine's parts of [param terrain] (769 amended (4)): {floor (cell ->
## true), lamps (each mine_lamp's cell), timbers (each arch's and beam's
## middle cell)}; empty for a level with no mine piece.
static func mine_parts(terrain: Dictionary) -> Dictionary:
	var lamps: Array[Vector2i] = []
	var timbers: Array[Vector2i] = []
	var any := false
	for entry: Dictionary in terrain.get("decor", []):
		var kind := str(entry.get("kind", ""))
		if kind not in MINE_KINDS:
			continue
		any = true
		if kind == "mine_lamp":
			lamps.append(entry["cell"])
		elif kind != "mine_track":
			timbers.append((entry["cell"] as Vector2i) + (entry["out"] as Vector2i) * (int(entry.get("width", 1)) / 2))
	if not any:
		return {}
	var floor_cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain.get("floor", []):
		floor_cells[cell] = true
	return {"floor": floor_cells, "lamps": lamps, "timbers": timbers}


## How open [param floor_cells] is round [param cell] (769 amended (4)): 0 a
## tunnel's (TUNNEL_OPEN of the cells within OPEN_REACH floor, or fewer)
## .. 1 a chamber's (CHAMBER_OPEN or more).
static func openness(floor_cells: Dictionary, cell: Vector2i) -> float:
	var open := 0
	var all := 0
	for dx in range(-OPEN_REACH, OPEN_REACH + 1):
		for dy in range(-OPEN_REACH, OPEN_REACH + 1):
			if dx == 0 and dy == 0:
				continue
			all += 1
			if floor_cells.has(cell + Vector2i(dx, dy)):
				open += 1
	return clampf((float(open) / all - TUNNEL_OPEN) / (CHAMBER_OPEN - TUNNEL_OPEN), 0.0, 1.0)


## The view's mine parts, read again only when its terrain is another.
func _mine_of() -> Dictionary:
	if not is_same(_mine_terrain, view._terrain):
		_mine_terrain = view._terrain
		_mine = mine_parts(view._terrain)
		_floor.clear()
		for at: Vector2i in view._terrain.get("floor", []):
			_floor[at] = true
		_skylights.clear()
		for skylight: Dictionary in view._terrain.get("skylights", []):
			_skylights.append(skylight["at"])
	return _mine


## A drop falling from a floor cell DRIP_NEAR..DRIP_FAR off [param cell]
## (none if a few tries find no floor), high up, heard through the rock.
func _drip(cell: Vector2i, floor_cells: Dictionary) -> void:
	for _try in 8:
		var away := Vector2.from_angle(randf() * TAU) * randf_range(DRIP_NEAR, DRIP_FAR)
		var at := cell + Vector2i(roundi(away.x), roundi(away.y))
		if floor_cells.has(at):
			view.sfx.play("amb.mine_drip", view._tile_position(at) + Vector3.UP * 2.5)
			return


## A creak from the nearest of [param timbers] within TIMBER_NEAR of
## [param cell], up at the beam; none with none near.
func _creak(cell: Vector2i, timbers: Array) -> void:
	var best := Vector2i(-1, -1)
	var nearest := TIMBER_NEAR + 1
	for at: Vector2i in timbers:
		var apart := maxi(absi(at.x - cell.x), absi(at.y - cell.y))
		if apart < nearest:
			nearest = apart
			best = at
	if nearest <= TIMBER_NEAR:
		view.sfx.play("amb.timber_creak", view._tile_position(best) + Vector3.UP * 2.7)


## How often each night call comes (calls a second) in [param zone] with
## the sky's [param daylight], [param weather], a forest's [param canopy]
## round the view (0..1) and [param tower] (0..1: how near a town wall's
## tower): an owl more under the roof, bats by its edges and clearings (a
## cover half way) and by towers; none by day or away from the open air.
static func calls(zone: String, daylight: float, weather: Dictionary, canopy: float, tower: float) -> Dictionary:
	var out := {"amb.owl": 0.0, "amb.bat": 0.0}
	if zone != "outdoors":
		return out
	var night := 1.0 - clampf((daylight - DayNight.NIGHT) / (1.0 - DayNight.NIGHT), 0.0, 1.0)
	var hush := 1.0 - RAIN_HUSH * float(weather.get("rain", 0.0))
	var edge := clampf(4.0 * canopy * (1.0 - canopy), 0.0, 1.0)
	out["amb.owl"] = night * hush * (0.25 + 0.75 * canopy) / OWL_SECONDS
	out["amb.bat"] = night * hush * maxf(edge, tower) / BAT_SECONDS
	return out


## One night call of [param slot] from somewhere round [param cell]: an owl
## up in the trees a way off, bats overhead near by.
func _call(slot: String, cell: Vector2i) -> void:
	var reach := float(SoundKit.reach(slot))
	var away := Vector2.from_angle(randf() * TAU) * randf_range(reach * 0.3, reach * 0.7)
	var at := view._tile_position(cell + Vector2i(roundi(away.x), roundi(away.y)))
	at.y += 6.0 if slot == "amb.owl" else 3.5
	view.sfx.play(slot, at)


## 0..1: how near [param cell] is to a town wall's drawn tower.
func _tower_nearness(cell: Vector2i) -> float:
	var nearest := INF
	for ring: Dictionary in view._town_walls:
		for vertex: Vector2i in (ring["towers"] as Dictionary):
			nearest = minf(nearest, maxf(absi(vertex.x - cell.x), absi(vertex.y - cell.y)))
	return clampf((TOWER_FAR - nearest) / (TOWER_FAR - TOWER_NEAR), 0.0, 1.0)


## 0..1: how near [param cell] is to a building that serves a town.
func _town_nearness(cell: Vector2i) -> float:
	var nearest := INF
	for building: Dictionary in view._terrain.get("buildings", []):
		if str(building.get("town", "")) == "" or not building.get("rect") is Rect2i:
			continue
		var rect: Rect2i = building["rect"]
		var dx := maxi(0, maxi(rect.position.x - cell.x, cell.x - rect.end.x + 1))
		var dy := maxi(0, maxi(rect.position.y - cell.y, cell.y - rect.end.y + 1))
		nearest = minf(nearest, maxf(dx, dy))
	return clampf((TOWN_FAR - nearest) / (TOWN_FAR - TOWN_NEAR), 0.0, 1.0)


## Each stream's loop at the point of its course nearest [param cell],
## held while it is within the stream's reach (and a little over, so it
## isn't made and freed at the edge).
func _place_streams(cell: Vector2i) -> void:
	var streams: Array = view._terrain.get("streams", [])
	if not is_same(streams, _stream_paths):
		for player: Variant in _streams.values():
			if is_instance_valid(player):
				player.queue_free()
		_streams.clear()
		_stream_paths = streams
	var reach := float(SoundKit.reach("amb.stream"))
	for i in streams.size():
		var path: Array = (streams[i] as Dictionary).get("path", [])
		var player: Variant = _streams.get(i)
		if player != null and not is_instance_valid(player):
			player = null
		var near := nearest_on(path, Vector2(cell))
		if near.is_empty() or float(near.distance) > reach + 2.0:
			if player != null:
				player.queue_free()
			_streams.erase(i)
			continue
		var at := view._tile_position(path[near.at])
		if int(near.at) + 1 < path.size():
			at = at.lerp(view._tile_position(path[int(near.at) + 1]), float(near.t))
		if player == null:
			player = view.sfx.hold("amb.stream", at)
			if player == null:
				continue
			_streams[i] = player
		view.sfx.steer(player, at, 1.0, duck_db)


## Each pond (a closed water of the terrain's "waters", 559) within its reach
## of [param cell] held at the point of its shore nearest the listener
## (pond_shore), sliding round it as they walk the bank (805 amended (9)).
func _place_ponds(cell: Vector2i) -> void:
	var waters: Array = view._terrain.get("waters", [])
	if not is_same(waters, _pond_waters):
		for player: Variant in _ponds.values():
			if is_instance_valid(player):
				player.queue_free()
		_ponds.clear()
		_pond_waters = waters
	var reach := float(SoundKit.reach("amb.pond"))
	for i in waters.size():
		var player: Variant = _ponds.get(i)
		if player != null and not is_instance_valid(player):
			player = null
		var near := pond_shore(waters[i], Vector2(cell))
		if near.is_empty() or float(near.distance) > reach + 2.0:
			if player != null:
				player.queue_free()
			_ponds.erase(i)
			continue
		var on: Vector2 = near.at
		var at := Vector3(on.x, view._tile_position(Vector2i(on.round())).y, on.y)
		if player == null:
			player = view.sfx.hold("amb.pond", at)
			if player == null:
				continue
			_ponds[i] = player
		view.sfx.steer(player, at, 1.0, duck_db)


## The point of [param water]'s shore nearest [param to] (cells), and how far:
## {at: Vector2, distance}; {} for a water that isn't a pond (not closed, or
## under three points). The closed curve is its shore (Client3D._curve_near).
static func pond_shore(water: Dictionary, to: Vector2) -> Dictionary:
	if not bool(water.get("closed", false)):
		return {}
	var points: PackedVector2Array = (water.get("curve", {}) as Dictionary).get("points", PackedVector2Array())
	if points.size() < 3:
		return {}
	var ring: Array = Array(points)
	ring.append(points[0])
	var near := nearest_on(ring, to)
	var a: Vector2 = ring[near.at]
	var b: Vector2 = ring[mini(int(near.at) + 1, ring.size() - 1)]
	return {"at": a.lerp(b, float(near.t)), "distance": float(near.distance)}


## Each stream's fall within its reach of [param cell] held, at the fall
## (the cell below its step), as loud as fall_db has its drop.
func _place_falls(cell: Vector2i) -> void:
	var falls: Array = view.stream_falls
	if not is_same(falls, _fall_list):
		for player: Variant in _falls.values():
			if is_instance_valid(player):
				player.queue_free()
		_falls.clear()
		_fall_list = falls
	var reach := SoundKit.reach("amb.falls")
	for i in falls.size():
		var fall: Dictionary = falls[i]
		var player: Variant = _falls.get(i)
		if player != null and not is_instance_valid(player):
			player = null
		var at_cell: Vector2i = fall["cell"]
		if maxi(absi(at_cell.x - cell.x), absi(at_cell.y - cell.y)) > reach + 2:
			if player != null:
				player.queue_free()
			_falls.erase(i)
			continue
		var at := view._tile_position(at_cell)
		if player == null:
			player = view.sfx.hold("amb.falls", at)
			if player == null:
				continue
			_falls[i] = player
		view.sfx.steer(player, at, 1.0, fall_db(float(fall["drop"])) + duck_db)


## How much louder or quieter (dB) a fall of [param drop] metres is heard
## than its slot: FALL_DB.x at Client3D.FALL_LEAST, up to FALL_DB.y at
## FALL_LOUDEST and over.
static func fall_db(drop: float) -> float:
	return lerpf(FALL_DB.x, FALL_DB.y, clampf(inverse_lerp(Client3D.FALL_LEAST, FALL_LOUDEST, drop), 0.0, 1.0))


## The point of [param path] (cells in order, each beside the one before)
## nearest [param to], as the cells' line runs: {at: the index of the
## segment's first cell, t: 0..1 along it, distance: in cells}; {} for
## an empty path.
static func nearest_on(path: Array, to: Vector2) -> Dictionary:
	var best := {}
	for i in maxi(1, path.size() - 1) if not path.is_empty() else 0:
		var a := Vector2(path[i])
		var along := Vector2(path[mini(i + 1, path.size() - 1)]) - a
		var t := 0.0 if along.is_zero_approx() else clampf((to - a).dot(along) / along.length_squared(), 0.0, 1.0)
		var distance := to.distance_to(a + along * t)
		if best.is_empty() or distance < float(best.distance):
			best = {"at": i, "t": t, "distance": distance}
	return best


## The draft (amb.draft, 608 amended's clue): a cool breath through the
## hidden door, from the middle of its edge (terrain "niches", the entry of
## kind "hidden"), heard from whichever cell beside the edge hears it best,
## while that edge's Door is shut; off once it opens, or with no such niche.
func _place_draft(cell: Vector2i) -> void:
	var best := {}
	var edge := Vector3i.ZERO
	for niche: Variant in view._terrain.get("niches", []):
		if not (niche is Dictionary and str(niche.get("kind", "")) == "hidden"):
			continue
		# As the niche's draw reads it (Client3D, 608): its edge, else the one
		# behind its cell.
		edge = niche.get("edge", Terrain.edge_key(niche["cell"], -(niche["out"] as Vector2i)))
		var door := World.door_on(edge)
		if door != null and door.is_open():
			break
		for side: Vector2i in Terrain.edge_cells(edge):
			if maxi(absi(side.x - cell.x), absi(side.y - cell.y)) > SoundKit.reach("amb.draft"):
				continue
			var heard := Sfx.hearing("amb.draft", side, cell)
			if heard.heard and (best.is_empty() or float(heard.db) > float(best.db)):
				best = heard
		break
	if best.is_empty():
		if _draft != null and _draft.playing:
			_draft.stop()
		return
	if _draft == null:
		var stream := _stream("amb.draft")
		if stream == null:
			return
		_draft = AudioStreamPlayer3D.new()
		_draft.stream = stream
		_draft.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		add_child(_draft)
	var cells := Terrain.edge_cells(edge)
	_draft.bus = "Ambience" + (Sfx.MUFFLED_SUFFIX if best.muffled else "")
	_draft.position = (view._tile_position(cells[0]) + view._tile_position(cells[1])) / 2.0 + Vector3.UP
	_draft.volume_db = SoundKit.volume_db("amb.draft") + float(best.db)
	if not _draft.playing:
		_draft.play()


## The cold forge lit (813 amended (6)): the forge cells of [param plates]
## (terrain "plates") whose set is of kind "forge" and whose door, on its
## "edge", [param is_open] says is open (dungeon's 813 amended (4): it opens
## as the forge catches and stays open the generation), where Ambience holds
## amb.forge_roar.
static func lit_forges(plates: Array, is_open: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for plate: Variant in plates:
		if plate is Dictionary and str(plate.get("kind", "")) == "forge" and plate.get("forge") is Vector2i \
				and plate.has("edge") and bool(is_open.call(plate["edge"])):
			out.append(plate["forge"])
	return out


## Whether the Door on [param edge] stands open (none: shut).
func _door_open(edge: Variant) -> bool:
	if not edge is Vector3i:
		return false
	var door := World.door_on(edge)
	return door != null and door.is_open()


## The torch loop at the nearest torch heard from [param cell], and the
## campfire's at the nearest camp's fire (777, sound's side) or place fire
## (the square's: Client3D.place_fires, heard as a camp's, not a torch), else off.
func _place_torch(cell: Vector2i) -> void:
	_place_point("amb.torch_fire", view.torch_fires(), cell)
	_place_point("amb.campfire", view.campfire_cells(), cell)
	var held := held_camps(view._terrain.get("camps", []), _camp_people())
	for slot: String in CAMP_TALK:
		_place_point(slot, held[slot], cell)


## The camps' murmur (795 amended (2), reading 793, maps' side's "mix"): each
## loop, the mixes it is heard at and who must be by the fire for it: the
## bandits' talk while a bandit holds a "bandit" or "mixed" camp, the
## traders' while its trader is there, so an emptied camp falls silent but
## for its fire, and a mixed one cleared of bandits keeps only its trader's.
const CAMP_TALK := {"amb.camp_bandit": {"mixes": ["bandit", "mixed"], "who": "bandits"},
		"amb.camp_trader": {"mixes": ["trader", "mixed"], "who": "traders"}}
## The bandits, by monster kind (enemy-ai's 793 rows); a captive never counts.
const CAMP_HOLDERS: Array[String] = ["bandit", "bandit_brute"]
## A camp trader (799, npc's side), by the start of his node's name
## ("Resident_" + Offers.CAMP): he has no kind on a client.
const CAMP_TRADER_PREFIX := "Resident_camp_"
const CAMP_HELD_CELLS := 4


## Each CAMP_TALK loop's fires of [param camps] (Level.camps_of) with one of
## its people within CAMP_HELD_CELLS: [param people] is {"bandits": cells,
## "traders": cells}.
static func held_camps(camps: Array, people: Dictionary) -> Dictionary:
	var out := {}
	for slot: String in CAMP_TALK:
		out[slot] = [] as Array[Vector2i]
	for camp: Dictionary in camps:
		var at: Vector2i = camp["at"]
		for slot: String in CAMP_TALK:
			var talk: Dictionary = CAMP_TALK[slot]
			var near: Array = people.get(talk["who"], [])
			if str(camp["mix"]) in talk["mixes"] and near.any(func(h: Vector2i) -> bool:
					return maxi(absi(h.x - at.x), absi(h.y - at.y)) <= CAMP_HELD_CELLS):
				(out[slot] as Array[Vector2i]).append(at)
	return out


## The cells of the living bandits and camp traders the view draws.
func _camp_people() -> Dictionary:
	var bandits: Array[Vector2i] = []
	var traders: Array[Vector2i] = []
	for id: int in view._puppets:
		var body := instance_from_id(id) as GridEntity
		if body == null or (body is Monster and body.hp <= 0):
			continue
		if body is Monster and str((body as Monster).spawn_spec.get("kind", "")) in CAMP_HOLDERS:
			bandits.append(body.tile)
		elif body is Resident and str(body.name).begins_with(CAMP_TRADER_PREFIX):
			traders.append(body.tile)
	return {"bandits": bandits, "traders": traders}


## [param slot]'s loop at whichever of [param cells] is heard best from
## [param cell] within its reach (Sfx.hearing), else off.
func _place_point(slot: String, cells: Array[Vector2i], cell: Vector2i) -> void:
	var best := {}
	var best_cell := Vector2i.ZERO
	var reach := SoundKit.reach(slot)
	for at: Vector2i in cells:
		if maxi(absi(at.x - cell.x), absi(at.y - cell.y)) > reach:
			continue
		var heard := Sfx.hearing(slot, at, cell)
		if heard.heard and (best.is_empty() or float(heard.db) > float(best.db)):
			best = heard
			best_cell = at
	var player: AudioStreamPlayer3D = points.get(slot)
	if best.is_empty():
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		var stream := _stream(slot)
		if stream == null:
			return
		player = AudioStreamPlayer3D.new()
		player.name = slot.replace(".", "_")
		player.stream = stream
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		add_child(player)
		points[slot] = player
	player.bus = "Ambience" + (Sfx.MUFFLED_SUFFIX if best.muffled else "")
	player.position = view._tile_position(best_cell) + Vector3.UP
	player.volume_db = SoundKit.volume_db(slot) + float(best.db)
	if not player.playing:
		player.play()


func _set_level(bed: String, level: float) -> void:
	var player: AudioStreamPlayer = players.get(bed)
	if level < SILENT:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		var stream := _stream(bed)
		if stream == null:
			return
		player = AudioStreamPlayer.new()
		player.stream = stream
		add_child(player)
		players[bed] = player
	var roofed := bed in OUTDOOR_BEDS and view != null and view.sfx.listener != null and World.fields != null \
			and not World.fields.under_sky(view.sfx.listener)
	player.bus = "Ambience" + (Sfx.MUFFLED_SUFFIX if roofed else "")
	player.volume_db = SoundKit.volume_db(bed) + linear_to_db(level) + duck_db
	if not player.playing:
		# Start somewhere along it, so two visits don't begin alike.
		player.play(randf() * maxf(player.stream.get_length() - 1.0, 0.0))


## A take of [param slot], set to loop; null when it has none.
static func _stream(slot: String) -> AudioStream:
	return Sfx.looping(slot)
