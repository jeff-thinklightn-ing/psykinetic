class_name Music
extends Node
## The music under the game (decision 377): layers of music.* slots, each a
## looping, flat bed on the Music bus, weighed from where the listener is,
## the time of day and the tension near them, and eased toward it as
## Ambience eases its beds. Stingers mark moments.
##
## weights() says how loud each layer should be (0..1), from:
## - the music zone (zone_of): a town (or a house), the wilds, a dungeon
##   or cave;
## - the time: a zone's night layer by night, its base by day;
## - phrases: the base and the melody play a phrase (PHRASE_ON seconds),
##   then rest (PHRASE_OFF), so the music comes and goes; tension starts a
##   phrase at once;
## - tension (0..1, step_tension): from the hostile monsters near the
##   listener (tension_from: suspicious ones a little, hunting or fighting
##   ones fully) and blows struck near (fight_near). The tension layers rise
##   with it, the melody leaves above half, and the ambience beds duck a
##   little under a fight (Ambience.duck_db).
## Stingers (sting): a level's first visit, the first hunter from calm, the
## local player's death, a hostile's rout near; rate-limited (may_sting),
## the layers ducked for the stinger's length.
## With the Music slider at 0 no layer plays at all.
## A level's own music (decision 668): a level whose level.json names a music
## slot ("music": "music.barrow") plays it, from its start and always, in
## place of the zone's ground and melody (the tension layers still rise over
## it), eased in on arrival and out on leaving over LEVEL_FADE.

## Seconds a layer takes to ease most of the way to its new loudness.
const FADE_SECONDS := 4.0
## Seconds a level's own music takes to ease in or out (as the title's, 656).
const LEVEL_FADE := 1.0
## Tension rises this fast (s to full) and, past its hold, falls this slowly.
const TENSION_RISE := 1.5
const TENSION_FALL := 10.0
## Seconds tension holds at its peak before it falls.
const TENSION_HOLD := 6.0
## Hostiles within this many cells (Chebyshev) of the listener count.
const TENSION_NEAR := 12
## A suspicious hostile's tension, and a hunting or fighting one's.
const TENSION_SUSPICIOUS := 0.4
const TENSION_HUNTING := 1.0
## Animals that are a threat when they hunt or fight (a wolf, a charging
## boar); other animals never raise tension.
const HOSTILE_ANIMALS: Array[String] = ["wolf", "boar"]
## A phrase's length and the rest after it (s), each picked between these.
const PHRASE_ON := Vector2(60.0, 120.0)
const PHRASE_OFF := Vector2(45.0, 120.0)
## The ambience beds' duck under full tension (dB).
const AMBIENCE_DUCK_DB := -3.0
## The layers' duck under a stinger (dB).
const STING_DUCK_DB := -6.0
## No stinger within STING_GAP s of another, nor the same within STING_SAME.
const STING_GAP := 20.0
const STING_SAME := 120.0
## Weights are worked out this often (s); loudness eases every frame.
const WEIGH_EVERY := 0.25
## Below this weight a layer is stopped.
const SILENT := 0.01
const ZONES: Array[String] = ["town", "wilds", "dungeon", "temple"]
## Zones with no night layer (under stone, in a temple), and with no melody.
const NO_NIGHT: Array[String] = ["dungeon", "temple"]
const NO_MELODY: Array[String] = ["temple"]
## A temple's layer: full within TEMPLE_NEAR cells of one, gone by TEMPLE_FAR
## (Chebyshev, from its walls); it is the zone from half way.
const TEMPLE_NEAR := 3.0
const TEMPLE_FAR := 8.0
const STINGS: Array[String] = ["discovery", "danger", "death", "victory"]

## Levels (World.zone's names) been in this session: a stinger on the
## first visit to each.
static var _visited: Dictionary[String, bool] = {}
## Level -> its own music slot ("" none), read from its level.json once.
static var _level_music: Dictionary[String, String] = {}

## The view this plays for (its listener, zone and town).
var view: Client3D
## Layer -> its player, the weight it eases toward, and the weight it is at.
var players: Dictionary[String, AudioStreamPlayer] = {}
var targets: Dictionary[String, float] = {}
var levels: Dictionary[String, float] = {}
## Tension now (0..1), and how long it holds there.
var tension := 0.0
var _hold := 0.0
## A fight heard near, raising tension to full at the next weighing.
var _fight_heard := false
## In a phrase or resting, and the seconds left of it.
var phrase_on := false
var _phrase_left := 0.0
var rng := RandomNumberGenerator.new()
## Seconds since this started (the stinger clock), the last stinger's time
## and each kind's.
var clock := 0.0
var _last_sting := -INF
var _last_sting_of: Dictionary[String, float] = {}
var _sting_player: AudioStreamPlayer
var _since_weigh := INF
var _zone_name := ""
## Level music slots heard this session: eased out (to 0) once left.
var _own_layers: Dictionary[String, bool] = {}


func _ready() -> void:
	rng.randomize()
	_phrase_left = rng.randf_range(5.0, 20.0)  # A first phrase soon after arriving.


func _process(delta: float) -> void:
	clock += delta
	_since_weigh += delta
	if _since_weigh >= WEIGH_EVERY:
		_weigh(_since_weigh)
		_since_weigh = 0.0
	var ease := 1.0 - exp(-delta * 3.0 / FADE_SECONDS)
	var level_ease := 1.0 - exp(-delta * 3.0 / LEVEL_FADE)
	var duck := STING_DUCK_DB if _sting_player != null and _sting_player.playing else 0.0
	for layer: String in targets:
		var level := lerpf(float(levels.get(layer, 0.0)), targets[layer], level_ease if _own_layers.has(layer) else ease)
		levels[layer] = level
		_set_level(layer, level, duck)


## Every sound stopped as this goes: a stream still playing at quit is
## reported as a leak.
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null


## Blows struck within TENSION_NEAR of the listener: tension to full.
func fight_near() -> void:
	_fight_heard = true


## Plays the stinger of [param kind] (STINGS) unless one played too lately
## (may_sting). False when it doesn't.
func sting(kind: String) -> bool:
	if not muted() and may_sting(kind, clock, _last_sting, _last_sting_of):
		var files := SoundKit.files("music.sting_" + kind)
		if files.is_empty():
			return false
		if _sting_player == null:
			_sting_player = AudioStreamPlayer.new()
			_sting_player.bus = "Music"
			add_child(_sting_player)
		_sting_player.stream = load(files[rng.randi() % files.size()])
		_sting_player.volume_db = SoundKit.volume_db("music.sting_" + kind)
		_sting_player.play()
		_last_sting = clock
		_last_sting_of[kind] = clock
		return true
	return false


## True when the Music slider is at 0: nothing plays.
static func muted() -> bool:
	return float(Net.music_volume) <= 0.001


## Whether a stinger of [param kind] may play at [param now], the last of
## any at [param last], each kind's last in [param last_of].
static func may_sting(kind: String, now: float, last: float, last_of: Dictionary) -> bool:
	return now - last >= STING_GAP and now - float(last_of.get(kind, -INF)) >= STING_SAME


## The music zone for the terrain's [param zone] ("outdoors", "indoors",
## "cave", "dungeon"), [param town] (0..1, Ambience's nearness) and
## [param temple] (0..1, temple_nearness).
static func zone_of(zone: String, town: float, temple := 0.0) -> String:
	if zone in ["cave", "dungeon"]:
		return "dungeon"
	if temple >= 0.5:
		return "temple"
	return "town" if zone == "indoors" or town >= 0.5 else "wilds"


## The tension the monsters near say: [param near] holds one
## [code][alert, hostile][/code] per monster within TENSION_NEAR (Monster.Alert,
## and whether it is a threat at all).
static func tension_from(near: Array) -> float:
	var most := 0.0
	for one: Array in near:
		if not bool(one[1]):
			continue
		match int(one[0]):
			Monster.Alert.SUSPICIOUS:
				most = maxf(most, TENSION_SUSPICIOUS)
			Monster.Alert.HUNTING, Monster.Alert.FIGHTING:
				most = maxf(most, TENSION_HUNTING)
	return most


## Whether [param monster] can raise tension: any goblin; an animal only
## of HOSTILE_ANIMALS, and only hunting or fighting (a boar's charge).
static func hostile(monster: Monster) -> bool:
	if not monster is Animal:
		return true
	return str(monster.spawn_spec.get("kind", "")) in HOSTILE_ANIMALS \
			and monster.alert in [Monster.Alert.HUNTING, Monster.Alert.FIGHTING]


## Tension after [param delta] s toward [param target]: up quickly
## (TENSION_RISE), held TENSION_HOLD s at its peak, then down slowly
## (TENSION_FALL). Returns [code][tension, hold][/code].
static func step_tension(now: float, hold: float, target: float, delta: float) -> Array:
	if target >= now:
		return [minf(target, now + delta / TENSION_RISE), TENSION_HOLD]
	if hold > 0.0:
		return [now, maxf(hold - delta, 0.0)]
	return [maxf(target, now - delta / TENSION_FALL), 0.0]


## How loud each layer should be (0..1) in [param zone] (ZONES) by
## [param day] (0 night .. 1 day), at [param level_tension] (0..1), in a
## phrase or not ([param in_phrase]); a level's own music [param own] (668)
## in place of the zone's ground and melody.
static func weights(zone: String, day: float, level_tension: float, in_phrase: bool, own := "") -> Dictionary:
	var out := {}
	for name: String in ZONES:
		out["music.%s_base" % name] = 0.0
		if name not in NO_MELODY:
			out["music.melody_" + name] = 0.0
		if name not in NO_NIGHT:
			out["music.%s_night" % name] = 0.0
	out["music.tension_low"] = 0.0
	out["music.tension_high"] = 0.0
	var high := clampf((level_tension - 0.5) / 0.5, 0.0, 1.0)
	out["music.tension_high"] = high
	out["music.tension_low"] = clampf(level_tension / TENSION_SUSPICIOUS, 0.0, 1.0) * (1.0 - high)
	if own != "":
		out[own] = 1.0 - 0.5 * level_tension
		return out
	if not in_phrase and level_tension <= 0.0:
		return out
	var ground := 1.0 - 0.5 * level_tension
	if zone in NO_NIGHT:
		out["music.%s_base" % zone] = ground
	else:
		out["music.%s_base" % zone] = ground * clampf(day, 0.0, 1.0)
		out["music.%s_night" % zone] = ground * (1.0 - clampf(day, 0.0, 1.0))
	if in_phrase and zone not in NO_MELODY:
		out["music.melody_" + zone] = 0.8 * clampf(1.0 - (level_tension - 0.25) / 0.25, 0.0, 1.0)
	return out


## Each layer's weight now, for the view's listener; [param delta] s since
## the last weighing.
func _weigh(delta: float) -> void:
	if view == null or view.sfx == null or view.sfx.listener == null:
		return
	if muted():
		targets.clear()
		for layer: String in players:
			players[layer].stop()
		return
	var cell: Vector2i = view.sfx.listener
	var zone_name := World.zone.name if World.zone != null else ""
	if zone_name != _zone_name:
		_zone_name = zone_name
		if zone_name != "" and not _visited.has(zone_name):
			_visited[zone_name] = true
			sting("discovery")
	var near: Array = []
	var hunted := false
	for entity in World.get_entities():
		var monster := entity as Monster
		if monster == null or not monster.spawned or monster.hp <= 0:
			continue
		if maxi(absi(monster.tile.x - cell.x), absi(monster.tile.y - cell.y)) > TENSION_NEAR:
			continue
		var threat := hostile(monster)
		near.append([monster.alert, threat])
		hunted = hunted or (threat and monster.alert in [Monster.Alert.HUNTING, Monster.Alert.FIGHTING])
	var target := 1.0 if _fight_heard else tension_from(near)
	_fight_heard = false
	if hunted and tension <= 0.0:
		sting("danger")
	var stepped := step_tension(tension, _hold, target, delta)
	tension = stepped[0]
	_hold = stepped[1]
	_phrase_left -= delta
	if tension > 0.0 and not phrase_on:
		_phrase_left = 0.0
	if _phrase_left <= 0.0:
		phrase_on = not phrase_on
		_phrase_left = rng.randf_range(PHRASE_ON.x, PHRASE_ON.y) if phrase_on else rng.randf_range(PHRASE_OFF.x, PHRASE_OFF.y)
	var steps := DayNight.now()
	var day := clampf((DayNight.daylight(steps) - DayNight.NIGHT) / (1.0 - DayNight.NIGHT), 0.0, 1.0)
	var terrain_zone := str(view._terrain.get("zone", "outdoors" if view._outdoor else "indoors"))
	var town: float = view.ambience._town_nearness(cell) if view.ambience != null else 0.0
	var own := level_music(str(view._terrain.get("level", "")))
	if own != "":
		_own_layers[own] = true
	var wanted := weights(zone_of(terrain_zone, town, temple_nearness(view._terrain.get("buildings", []), cell)), day, tension, phrase_on, own)
	for layer: String in _own_layers:
		if not wanted.has(layer):
			wanted[layer] = 0.0  # Left: eased out.
	targets.assign(by_take(wanted))
	if view.ambience != null:
		view.ambience.duck_db = AMBIENCE_DUCK_DB * clampf((tension - 0.5) / 0.5, 0.0, 1.0)


## Level [param level_name]'s own music slot (668): its level.json's "music"
## when that names a slot, else "". The registered config (a generated or
## edited level, Level.register) when there is one, else its file, read once.
static func level_music(level_name: String) -> String:
	if level_name.is_empty():
		return ""
	if Level._registered.has(level_name):
		var slot := str(Level._registered[level_name].get("config", {}).get("music", ""))
		return slot if SoundKit.has(slot) else ""
	if not _level_music.has(level_name):
		var slot := ""
		var path := Level.folder_of(level_name) + "level.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				slot = str(parsed.get("music", ""))
		_level_music[level_name] = slot if SoundKit.has(slot) else ""
	return _level_music[level_name]


## 0..1: how near [param cell] is to a temple among [param buildings]
## (the terrain's: slot building.temple, rect).
static func temple_nearness(buildings: Array, cell: Vector2i) -> float:
	var nearest := INF
	for building: Dictionary in buildings:
		if str(building.get("slot", "")) != "building.temple" or not building.get("rect") is Rect2i:
			continue
		var rect: Rect2i = building["rect"]
		var dx := maxi(0, maxi(rect.position.x - cell.x, cell.x - rect.end.x + 1))
		var dy := maxi(0, maxi(rect.position.y - cell.y, cell.y - rect.end.y + 1))
		nearest = minf(nearest, maxf(dx, dy))
	return clampf((TEMPLE_FAR - nearest) / (TEMPLE_FAR - TEMPLE_NEAR), 0.0, 1.0)


## [param wanted]'s weights summed by the slot each plays from
## (SoundKit.played_from: a night layer with no takes is its base's), so
## one recording never plays twice at once; a layer with nothing to play
## is left out.
static func by_take(wanted: Dictionary) -> Dictionary:
	var out := {}
	for layer: String in wanted:
		var from := SoundKit.played_from(layer)
		if from != "":
			out[from] = minf(float(out.get(from, 0.0)) + float(wanted[layer]), 1.0)
	return out


func _set_level(layer: String, level: float, duck_db: float) -> void:
	var player: AudioStreamPlayer = players.get(layer)
	if level < SILENT:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		var stream := Ambience._stream(layer)
		if stream == null:
			return
		player = AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Music"
		add_child(player)
		players[layer] = player
	player.volume_db = SoundKit.volume_db(layer) + linear_to_db(level) + duck_db
	if not player.playing and player.stream != null:  # A player let go (stream null) stays quiet.
		# A level's own music from its start; the beds anywhere along.
		player.play(0.0 if _own_layers.has(layer) else rng.randf() * maxf(player.stream.get_length() - 1.0, 0.0))
