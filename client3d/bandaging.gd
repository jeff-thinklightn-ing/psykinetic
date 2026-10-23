extends Node
## Bandaging heard (Jeff on v0.1.169: "Bandages should have a ruffling
## sound"): sfx.bandage, a cloth ruffle looped from the bandager while the
## bandaging runs, a player's or a companion's alike. It ends softly
## (FADE_DONE) when the patient goes on to mend, short (FADE_CUT) when it was
## broken off. Client only: it reads what is replicated each frame.
##
## Who bandages: GridEntity.tending (626, pc-character's kneel: the
## patient's node name while the entity bandages, its own for itself, ""
## otherwise), the ruffle at the bandager. Done or broken off: the patient's
## mending is 2 then (or still 1, the news a frame behind), and 0 when
## broken off; a patient gone or a bandager downed is broken off too.

## Seconds the ruffle fades over: done, and broken off.
const FADE_DONE := 0.4
const FADE_CUT := 0.06

## The view (Client3D): its roster and puppets are read each frame.
var view: Node = null
## Bandaging heard: the bandager's name -> its held ruffle.
var ruffles: Dictionary[String, AudioStreamPlayer3D] = {}
## The bandager's name -> whom it last tended: tending is "" once it ends,
## and the patient's mending then says how.
var patients: Dictionary[String, String] = {}
## How each ended, for tests: [key, "done" or "cut"] each.
var ended: Array[Array] = []


func _process(_delta: float) -> void:
	if view == null:
		return
	var active: Dictionary[String, Vector3] = {}
	var done: Dictionary[String, bool] = {}
	read(World.sought(), active, done)
	update(active, done)


## Fills [param active] (key -> where it is heard from) and [param done]
## (key -> whether its patient mends: an ending is soft) from
## [param roster] (players and companions).
func read(roster: Array[GridEntity], active: Dictionary[String, Vector3], done: Dictionary[String, bool]) -> void:
	var by_name: Dictionary[String, GridEntity] = {}
	for entity in roster:
		by_name[String(entity.name)] = entity
	for entity in roster:
		var key := String(entity.name)
		if not entity.tending.is_empty():
			active[key] = _at(entity)
			patients[key] = entity.tending
		var patient: GridEntity = by_name.get(patients.get(key, ""))
		# A patient gone, or a bandager downed (626 amended sets the patient's
		# mending 0 then too; this reads it at once): broken off.
		done[key] = patient != null and patient.mending != 0 and not World.is_downed(entity)


## Ruffles started for the newly [param active], moved with the rest, and
## ended (by [param done]) for those gone from it.
func update(active: Dictionary[String, Vector3], done: Dictionary[String, bool]) -> void:
	for key: String in ruffles.keys():
		if active.has(key):
			view.sfx.steer(ruffles[key], active[key])
			continue
		var soft := bool(done.get(key, true))
		ended.append([key, "done" if soft else "cut"])
		_fade(ruffles[key], FADE_DONE if soft else FADE_CUT)
		ruffles.erase(key)
	for key: String in active:
		if not ruffles.has(key):
			var ruffle: AudioStreamPlayer3D = view.sfx.hold("sfx.bandage", active[key])
			if ruffle != null:
				ruffles[key] = ruffle


## [param entity]'s drawn place, else its tile's.
func _at(entity: GridEntity) -> Vector3:
	var puppet: Node3D = view._puppets.get(entity.get_instance_id())
	return puppet.position if puppet != null else view._tile_position(entity.tile)


## [param player] faded out over [param seconds], then gone.
func _fade(player: AudioStreamPlayer3D, seconds: float) -> void:
	if not is_instance_valid(player):
		return
	if not player.is_inside_tree():
		player.queue_free()
		return
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", -60.0, seconds)
	tween.tween_callback(player.queue_free)


## Every ruffle stopped as this goes.
func _exit_tree() -> void:
	for key: String in ruffles:
		if is_instance_valid(ruffles[key]):
			ruffles[key].stop()
	ruffles.clear()
