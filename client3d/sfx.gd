class_name Sfx
extends Node3D
## Spatial sound effects for the 3D view. Every sound is a slot of
## SoundKit (art/audio/slots.json: sfx.door_wood_open, sfx.hit_flesh, ...);
## play() picks one of the slot's takes (never the same one twice running),
## varies its pitch and volume a little so repeats do not machine-gun, and
## plays it once from a point in the world on the SFX bus. A slot with no
## takes plays its fallback's or a placeholder blip. Nothing here decides
## when a sound plays: the view calls play() on events the server sent (see
## Client3D).
##
## Volumes come from settings.cfg: master_volume= (the Master bus) and
## sfx_volume= (the SFX bus), each 0..1.

const BUS := "SFX"
## Each play: pitch times 1 ± this, volume from -VOLUME_JITTER_DB to half
## that above.
const PITCH_JITTER := 0.07
const VOLUME_JITTER_DB := 2.0
## How far a sound carries (units; a tile is one).
const UNIT_SIZE := 5.0
const MAX_DISTANCE := 30.0

## Slot -> its streams, loaded on first use.
var _loaded: Dictionary[String, Array] = {}
## Slot -> the index played last.
var _last: Dictionary[String, int] = {}
## Plays made, for tests: [slot, file ("" for the placeholder)] each.
var played: Array[Array] = []


func _ready() -> void:
	apply_volumes()


## The Master and SFX buses at Net.master_volume and Net.sfx_volume; the
## SFX bus is made here if the project has none.
static func apply_volumes() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
	_set_bus_volume(0, Net.master_volume)
	_set_bus_volume(AudioServer.get_bus_index(BUS), Net.sfx_volume)


static func _set_bus_volume(index: int, linear: float) -> void:
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


## One sound of [param slot] at [param at], [param pitch] times its own
## (before the jitter), [param volume_db] on top of the slot's volume.
func play(slot: String, at: Vector3, pitch := 1.0, volume_db := 0.0) -> void:
	if not SoundKit.has(slot):
		push_warning("[sfx] no sound slot %s" % slot)
		return
	var streams := _streams(slot)
	if streams.is_empty():
		return
	var index := randi() % streams.size()
	if streams.size() > 1 and index == _last.get(slot, -1):
		index = (index + 1) % streams.size()
	_last[slot] = index
	var player := AudioStreamPlayer3D.new()
	player.stream = streams[index]
	player.bus = BUS
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	player.volume_db = SoundKit.volume_db(slot) + volume_db + randf_range(-VOLUME_JITTER_DB, VOLUME_JITTER_DB * 0.5)
	player.position = at
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	played.append([slot, (streams[index] as AudioStream).resource_path])


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
