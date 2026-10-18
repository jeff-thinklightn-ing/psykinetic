class_name Sfx
extends Node3D
## The game's sounds, played. Every sound is a slot of SoundKit
## (art/audio/slots.json: sfx.door_wood_open, sfx.hit_flesh, ...); play()
## picks one of the slot's takes (never the same one twice running), varies
## its pitch and volume a little so repeats do not machine-gun, and plays it
## once on its bus: from a point in the world, or flat (play_flat) for one
## that is not positional (UI, ambience beds). A slot with no takes plays
## its fallback's or a placeholder blip. Nothing here decides when a sound
## plays: the view calls play() on events the server sent (see Client3D),
## so nothing beyond a client's interest is heard.
##
## What you hear is what monsters hear (decision 269): a positional sound is
## heard by the rule World._hear tells monsters a noise by. Its radius is its
## slot's sim noise (SoundKit.reach: Senses' radii; a footstep's the body's,
## Senses.step_radius, passed in), counted in cells, Chebyshev, from the
## listener's cell (the local player's, set by the view); with no clear line
## (a wall or a closed door between: World.has_clear_line) it carries half
## as far and is played through a low-pass. Beyond that it isn't played at
## all. Within it, it falls from full at a cell to EDGE_DB at the edge; the
## 3D player only pans it (its own distance falloff is off).
##
## Buses (made here if the project has none), each under Master: SFX, Voice,
## Ambience, UI and Music, each with a muffled twin (a low-pass) sending to
## it. Volumes come from settings.cfg, each 0..1: master_volume=,
## sfx_volume=, voice_volume=, ambience_volume=, ui_volume= and
## music_volume= (Net; the options panel sets them).

const BUS := "SFX"
## A slot's bus -> the audio bus it plays on.
const BUSES := {"sfx": "SFX", "voice": "Voice", "ambience": "Ambience", "ui": "UI", "music": "Music"}
## Each bus's volume setting (Net's variable of that name).
const VOLUME_SETTINGS := {"SFX": "sfx_volume", "Voice": "voice_volume", "Ambience": "ambience_volume",
	"UI": "ui_volume", "Music": "music_volume"}
## The muffled twin of a bus: "<bus>_Muffled", a low-pass at this.
const MUFFLED_SUFFIX := "_Muffled"
const MUFFLED_CUTOFF_HZ := 900.0
## How much quieter a muffled sound is, on top of its distance.
const MUFFLED_DB := -4.0
## Loudness by distance: full within a cell, EDGE_DB at the radius, a
## straight line in dB between.
const EDGE_DB := -24.0
## Each play: pitch times 1 ± this, volume from -VOLUME_JITTER_DB to half
## that above.
const PITCH_JITTER := 0.07
const VOLUME_JITTER_DB := 2.0
## The farthest any sound carries (cells): the loudest noise, a shout.
const MAX_DISTANCE := float(Senses.NOISE_SHOUT)

## The cell sounds are heard from (the local player's), or null: then every
## sound is played, unmuffled, at full loudness (no one to hear it from).
var listener: Variant = null
## Every sound played as if there were no listener: for tests of which
## sounds events make, not of who hears them.
var hear_everything := false
## Slot -> its streams, loaded on first use.
var _loaded: Dictionary[String, Array] = {}
## Slot -> the index played last.
var _last: Dictionary[String, int] = {}
## Slot -> the take to play next time, once, instead of a random one (a
## listening reel plays each in turn: tools/clip.gd sound_reel).
var next_take: Dictionary[String, int] = {}
## Plays made, for tests: [slot, file ("" for the placeholder), bus] each.
var played: Array[Array] = []
## Sounds not played because they were out of hearing, for tests: slot each.
var unheard: Array[String] = []


func _ready() -> void:
	apply_volumes()
	if not Net.volumes_changed.is_connected(apply_volumes):  # Static: one connection for every view.
		Net.volumes_changed.connect(apply_volumes)


## Every sound stopped as this goes: a stream still playing at quit is
## reported as a leak.
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null


## Every bus (and its muffled twin) made if missing, and each at its volume
## from Net.
static func apply_volumes() -> void:
	for name: String in VOLUME_SETTINGS:
		_bus(name, "Master")
		var muffled := _bus(name + MUFFLED_SUFFIX, name)
		if AudioServer.get_bus_effect_count(muffled) == 0:
			var low_pass := AudioEffectLowPassFilter.new()
			low_pass.cutoff_hz = MUFFLED_CUTOFF_HZ
			AudioServer.add_bus_effect(muffled, low_pass)
	_set_bus_volume(0, Net.master_volume)
	for name: String in VOLUME_SETTINGS:
		_set_bus_volume(AudioServer.get_bus_index(name), float(Net.get(VOLUME_SETTINGS[name])))


## The bus [param name], made sending to [param send] if there is none.
static func _bus(name: String, send: String) -> int:
	var index := AudioServer.get_bus_index(name)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, send)
	return index


static func _set_bus_volume(index: int, linear: float) -> void:
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


## How [param slot] made at [param at] sounds from [param from]: {heard,
## muffled, db}, by the sim's rule (World._hear): heard within
## [param radius] cells (Chebyshev), half that with no clear line, falling
## from 0 dB at a cell to EDGE_DB at the edge. [param radius] -1 is the
## slot's own (SoundKit.reach). Rain and wind shorten it under the sky
## as World.noise has them (World.weather_hearing_at).
static func hearing(slot: String, at: Vector2i, from: Vector2i, radius := -1) -> Dictionary:
	var reach := radius if radius >= 0 else SoundKit.reach(slot)
	if reach > 0 and SoundKit.noise_kind(slot) != "speech":
		# Rain and wind cover it as World.noise has them cover a noise.
		var cover := World.weather_hearing_at(at)
		if cover < 1.0:
			reach = maxi(1, roundi(reach * cover))
	var d := maxi(absi(at.x - from.x), absi(at.y - from.y))
	var muffled := d > 0 and not World.has_clear_line(at, from)
	var carries := reach / 2.0 if muffled else float(reach)
	if reach <= 0 or d > reach or (muffled and d * 2 > reach):
		return {"heard": false, "muffled": muffled, "db": -80.0}
	var db := 0.0 if d <= 1 or carries <= 1.0 else EDGE_DB * clampf((d - 1.0) / (carries - 1.0), 0.0, 1.0)
	return {"heard": true, "muffled": muffled, "db": db + (MUFFLED_DB if muffled else 0.0)}


## One sound of [param slot] at [param at], [param pitch] times its own
## (before the jitter), [param volume_db] on top of the slot's volume,
## heard over [param radius] cells (-1: the slot's own). One that isn't
## positional is played flat.
func play(slot: String, at: Vector3, pitch := 1.0, volume_db := 0.0, radius := -1) -> void:
	if not SoundKit.has(slot):
		push_warning("[sfx] no sound slot %s" % slot)
		return
	if not SoundKit.positional(slot):
		play_flat(slot, pitch, volume_db)
		return
	var muffled := false
	if listener != null and not hear_everything:
		var heard := _best_hearing(slot, at, radius)
		if not heard.heard:
			unheard.append(slot)
			return
		muffled = heard.muffled
		volume_db += heard.db
	var stream := _pick(slot)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = _bus_of(slot) + (MUFFLED_SUFFIX if muffled else "")
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	_mark(player, slot, pitch)
	player.volume_db = _volume(slot, volume_db)
	player.position = at
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	played.append([slot, stream.resource_path, player.bus])


## How [param slot] at [param at] sounds from the listener: from its cell,
## or, on a cell edge (a door, a blow on a wall: half a cell off the grid),
## from whichever cell beside the edge is heard best, since it faces both.
func _best_hearing(slot: String, at: Vector3, radius: int) -> Dictionary:
	var best := {}
	for x: int in _cells_beside(at.x):
		for y: int in _cells_beside(at.z):
			var heard := hearing(slot, Vector2i(x, y), listener, radius)
			if best.is_empty() or (heard.heard and (not best.heard or float(heard.db) > float(best.db))):
				best = heard
	return best


## The cell coordinates [param value] is in: one, or the two beside it
## when it lies on the line between them.
static func _cells_beside(value: float) -> Array[int]:
	if absf(value - floorf(value) - 0.5) < 0.05:
		return [floori(value), ceili(value)]
	return [roundi(value)]


## What a player plays, for tests: its slot, and its pitch before the
## jitter (the jitter can swap two pitches less than 14% apart).
static func _mark(player: Node, slot: String, pitch: float) -> void:
	player.set_meta("slot", slot)
	player.set_meta("pitch", pitch)


## One sound of [param slot], not from anywhere (UI, a bed).
func play_flat(slot: String, pitch := 1.0, volume_db := 0.0) -> void:
	var stream := _pick(slot)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = _bus_of(slot)
	player.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	_mark(player, slot, pitch)
	player.volume_db = _volume(slot, volume_db)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	played.append([slot, stream.resource_path, player.bus])


static func _bus_of(slot: String) -> String:
	return str(BUSES.get(SoundKit.bus(slot), BUS))


static func _volume(slot: String, volume_db: float) -> float:
	return SoundKit.volume_db(slot) + volume_db + randf_range(-VOLUME_JITTER_DB, VOLUME_JITTER_DB * 0.5)


## One of [param slot]'s takes, not the one played last; null for none.
func _pick(slot: String) -> AudioStream:
	var streams := _streams(slot)
	if streams.is_empty():
		return null
	var index := randi() % streams.size()
	if streams.size() > 1 and index == _last.get(slot, -1):
		index = (index + 1) % streams.size()
	if next_take.has(slot):
		index = next_take[slot] % streams.size()
		next_take.erase(slot)
	_last[slot] = index
	return streams[index]


## [param slot]'s takes, or its placeholder alone (none for a bed's).
func _streams(slot: String) -> Array:
	if _loaded.has(slot):
		return _loaded[slot]
	var streams: Array = []
	for path: String in SoundKit.files(slot):
		streams.append(load(path))
	if streams.is_empty() and SoundKit.placeholder(SoundKit.bus(slot)) != null:
		streams.append(SoundKit.placeholder(SoundKit.bus(slot)))
	_loaded[slot] = streams
	return streams
