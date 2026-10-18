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
## - rain quietening the birds and crickets;
## - a town: its day or night bed within TOWN_NEAR cells of a building that
##   serves one, fading out by TOWN_FAR.
## A torch is a point, not a bed: the torch loop (amb.torch_fire) plays from
## the nearest torch within hearing (Sfx.hearing, its slot's range).
## A bed with no takes plays nothing.

## Seconds a bed takes to ease most of the way to its new loudness.
const FADE_SECONDS := 2.0
## Weights are worked out this often (s); the loudness eases every frame.
const WEIGH_EVERY := 0.25
## Under a roof, outdoor beds at this share of their weight, muffled.
const ROOFED := 0.35
## How much rain quietens birds and crickets (at full rain).
const RAIN_HUSH := 0.7
## A town's bed: full within TOWN_NEAR cells of one of its buildings, gone
## by TOWN_FAR.
const TOWN_NEAR := 10.0
const TOWN_FAR := 22.0
## The hour dawn's bed peaks, and how many hours either side it fades over.
const DAWN_HOUR := 6.2
const DAWN_HOURS := 1.4
## Below this weight a bed is stopped.
const SILENT := 0.01
const BEDS: Array[String] = ["amb.forest_dawn", "amb.forest_day", "amb.forest_night", "amb.field_wind",
	"amb.rain", "amb.storm", "amb.dungeon", "amb.town_day", "amb.town_night"]
## Beds of the open air: muffled under a roof.
const OUTDOOR_BEDS: Array[String] = ["amb.forest_dawn", "amb.forest_day", "amb.forest_night", "amb.field_wind",
	"amb.rain", "amb.storm"]

## The view this plays for (its listener, zone, torches and buildings).
var view: Client3D
## Bed -> its player (made the first time it is heard).
var players: Dictionary[String, AudioStreamPlayer] = {}
## Bed -> the weight it eases toward, and the weight it is at.
var targets: Dictionary[String, float] = {}
var levels: Dictionary[String, float] = {}
## Every bed this much quieter (dB): Music's duck under a fight.
var duck_db := 0.0
var _torch: AudioStreamPlayer3D
var _since_weigh := INF


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
	targets.assign(weights(zone, under_sky, DayNight.daylight(steps), DayNight.hour(steps), weather, _town_nearness(cell)))
	_place_torch(cell)


## How loud each bed should be (0..1) in [param zone] ("outdoors",
## "indoors", "cave", "dungeon"), [param under_sky] or under a roof, with
## the sky's [param daylight] (DayNight: NIGHT .. 1) at [param hour],
## [param weather] (Weather's: rain, wind, ... each 0..1) and
## [param town] (0..1: how near a town's buildings).
static func weights(zone: String, under_sky: bool, daylight: float, hour: float, weather: Dictionary, town: float) -> Dictionary:
	var out := {}
	for bed in BEDS:
		out[bed] = 0.0
	var rain := float(weather.get("rain", 0.0))
	var wind := float(weather.get("wind", 0.0))
	if zone == "outdoors":
		var day := clampf((daylight - DayNight.NIGHT) / (1.0 - DayNight.NIGHT), 0.0, 1.0)
		var dawn := clampf(1.0 - absf(hour - DAWN_HOUR) / DAWN_HOURS, 0.0, 1.0)
		var hush := 1.0 - RAIN_HUSH * rain
		out["amb.forest_dawn"] = dawn * hush
		out["amb.forest_day"] = day * (1.0 - dawn) * hush
		out["amb.forest_night"] = (1.0 - day) * (1.0 - dawn) * hush
		out["amb.field_wind"] = wind
		var storm := clampf(rain * wind * 2.0 - 0.2, 0.0, 1.0) if str(weather.get("kind", "")) == "storm" else 0.0
		out["amb.storm"] = storm
		out["amb.rain"] = rain * (1.0 - storm)
		out["amb.town_day"] = town * day
		out["amb.town_night"] = town * (1.0 - day)
		if not under_sky:
			for bed in OUTDOOR_BEDS:
				out[bed] = out[bed] * ROOFED
	else:
		out["amb.dungeon"] = 1.0 if zone in ["cave", "dungeon"] else 0.0
	return out


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


## The torch loop at the nearest torch heard from [param cell], else off.
func _place_torch(cell: Vector2i) -> void:
	var best := {}
	var best_cell := Vector2i.ZERO
	for torch: Vector2i in view.torch_cells:
		if maxi(absi(torch.x - cell.x), absi(torch.y - cell.y)) > SoundKit.reach("amb.torch_fire"):
			continue
		var heard := Sfx.hearing("amb.torch_fire", torch, cell)
		if heard.heard and (best.is_empty() or float(heard.db) > float(best.db)):
			best = heard
			best_cell = torch
	if best.is_empty():
		if _torch != null and _torch.playing:
			_torch.stop()
		return
	if _torch == null:
		var stream := _stream("amb.torch_fire")
		if stream == null:
			return
		_torch = AudioStreamPlayer3D.new()
		_torch.stream = stream
		_torch.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		add_child(_torch)
	_torch.bus = "Ambience" + (Sfx.MUFFLED_SUFFIX if best.muffled else "")
	_torch.position = view._tile_position(best_cell) + Vector3.UP
	_torch.volume_db = SoundKit.volume_db("amb.torch_fire") + float(best.db)
	if not _torch.playing:
		_torch.play()


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
