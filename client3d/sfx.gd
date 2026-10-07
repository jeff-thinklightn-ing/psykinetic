class_name Sfx
extends Node3D
## Spatial sound effects for the 3D view. Every sound is a named set of
## files from Kenney's CC0 packs under art/audio/; play() picks one of the
## set (never the same one twice running), varies its pitch and volume a
## little so repeats do not machine-gun, and plays it once from a point in
## the world on the SFX bus. Nothing here decides when a sound plays: the
## view calls play() on events the server sent (see Client3D).
##
## Volumes come from settings.cfg: master_volume= (the Master bus) and
## sfx_volume= (the SFX bus), each 0..1.

const PACK := "res://art/audio/"
const BUS := "SFX"
## Set name -> [volume in dB, files under PACK].
var sets := {
	"swing": [-8.0, ["kenney_rpg-audio/Audio/cloth1.ogg", "kenney_rpg-audio/Audio/cloth2.ogg",
		"kenney_rpg-audio/Audio/cloth3.ogg", "kenney_rpg-audio/Audio/cloth4.ogg"]],
	"hit": [-2.0, _numbered("kenney_impact-sounds/Audio/impactPunch_medium_%03d.ogg")],
	"impact_stone": [-2.0, _numbered("kenney_impact-sounds/Audio/impactMining_%03d.ogg")],
	"impact_wood": [-2.0, _numbered("kenney_impact-sounds/Audio/impactWood_heavy_%03d.ogg")],
	"impact_body": [-2.0, _numbered("kenney_impact-sounds/Audio/impactPunch_heavy_%03d.ogg")],
	"impact_body_soft": [-6.0, _numbered("kenney_impact-sounds/Audio/impactSoft_heavy_%03d.ogg")],
	"break": [0.0, _numbered("kenney_impact-sounds/Audio/impactPlank_medium_%03d.ogg")],
	"death_monster": [0.0, _numbered("kenney_impact-sounds/Audio/impactSoft_medium_%03d.ogg")],
	"death_player": [0.0, _numbered("kenney_impact-sounds/Audio/impactSoft_heavy_%03d.ogg")],
	"death_companion": [-2.0, ["kenney_rpg-audio/Audio/dropLeather.ogg"]],
	"door_open": [-4.0, ["kenney_rpg-audio/Audio/doorOpen_1.ogg", "kenney_rpg-audio/Audio/doorOpen_2.ogg"]],
	"door_close": [-4.0, ["kenney_rpg-audio/Audio/doorClose_1.ogg", "kenney_rpg-audio/Audio/doorClose_2.ogg",
		"kenney_rpg-audio/Audio/doorClose_3.ogg", "kenney_rpg-audio/Audio/doorClose_4.ogg"]],
	"footstep": [-16.0, _numbered("kenney_impact-sounds/Audio/footstep_concrete_%03d.ogg")],
}
## Each play: pitch times 1 ± this, volume from -VOLUME_JITTER_DB to half
## that above.
const PITCH_JITTER := 0.07
const VOLUME_JITTER_DB := 2.0
## How far a sound carries (units; a tile is one).
const UNIT_SIZE := 5.0
const MAX_DISTANCE := 30.0

## Set name -> its streams, loaded on first use; files that are missing
## are left out (warned once).
var _loaded: Dictionary[String, Array] = {}
## Set name -> the index played last.
var _last: Dictionary[String, int] = {}
## Plays made, for tests: [set name, file] each.
var played: Array[Array] = []


static func _numbered(pattern: String) -> Array[String]:
	var files: Array[String] = []
	for i in 5:
		files.append(pattern % i)
	return files


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


## One sound from [param set_name] at [param at], [param pitch] times the
## set's own (before the jitter), [param volume_db] on top of its volume.
func play(set_name: String, at: Vector3, pitch := 1.0, volume_db := 0.0) -> void:
	var streams := _streams(set_name)
	if streams.is_empty():
		return
	var index := randi() % streams.size()
	if streams.size() > 1 and index == _last.get(set_name, -1):
		index = (index + 1) % streams.size()
	_last[set_name] = index
	var player := AudioStreamPlayer3D.new()
	player.stream = streams[index]
	player.bus = BUS
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	player.volume_db = sets[set_name][0] + volume_db + randf_range(-VOLUME_JITTER_DB, VOLUME_JITTER_DB * 0.5)
	player.position = at
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	played.append([set_name, (streams[index] as AudioStream).resource_path])


func _streams(set_name: String) -> Array:
	if _loaded.has(set_name):
		return _loaded[set_name]
	var streams: Array = []
	if sets.has(set_name):
		for file: String in sets[set_name][1]:
			var path := PACK + file
			if ResourceLoader.exists(path):
				streams.append(load(path))
			else:
				push_warning("[sfx] %s: %s is missing" % [set_name, path])
	_loaded[set_name] = streams
	return streams
