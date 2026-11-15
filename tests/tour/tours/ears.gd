extends RefCounted
## Umbrage by ear (sound): sh tools/tour.sh ears
## The town walked as a player walks it, with the 3D view on the headless
## client so its sound runs: every quarter second each sound player the view
## holds is logged (stream, slot, bus, volume, position), and every one-shot
## played, to ears.jsonl beside the report: the joined log a sound bullet is
## read on (the coordinator, 11-14). The Music bus is muted: the town's
## sounds, not its music. Master is recorded too (ears.wav) where the audio
## driver mixes. It writes nothing under user:// (tools/tour.sh runs it under
## its own APPDATA, build/tours/ears/appdata).
##
## The legs: noon's walk; the work leg (the town's store given wood by the
## console, so its carpenter takes up its first build, economy's word, 11-14:
## stood beside the first worker sawing, hammering, chopping or hoeing, two
## cells off, six, and twenty for far work); a dropped link and the
## reconnect, still by day in the town (the arrival not played again); away
## out of every town's reach for the arrival's 180 s and back once 600 s
## have passed since the last (a second arrival, 578 amended (4)); the
## night's walk.
##
## Each snapshot line: t, cell, zone, rtt (Net.rtt_ms), frame_ms (the
## longest frame since the last line), players [{id, path, slot, bus, db,
## on, pos, pitch, len, at}], folk [[name, x, y, activity, trade]] (within 16
## cells, or 45 for one at a work with a sound). A one-shot line: t, cell,
## played [slot, file, bus]. A mark line: t, cell, mark.

const DAY := 12
const NIGHT := 23
## The square by its fire, the town's east, the temple's side, the west huts, the east, the south, the store,
## and the square again: its first stand falls in the arrival's first 22 s, when the chatter is held
## (Ambience TOWN_DAY "chatter_after_s"). The town's east is the street at (210, 203): (212, 205), its
## spot until 754 amended (9), lies inside a hut (rect (210, 204) 3x3), and the walk went in by its door.
const SPOTS := [Vector2i(194, 211), Vector2i(210, 203), Vector2i(219, 195), Vector2i(196, 190), Vector2i(228, 214),
	Vector2i(204, 216), Vector2i(212, 218), Vector2i(194, 211)]
const NIGHT_SPOTS := [Vector2i(194, 211), Vector2i(210, 203)]
const SQUARE := Vector2i(194, 211)
const STAND := 20.0
## Away: how far out to look for a cell out of every town's reach, the
## margin past it, and the stand there (the arrival's 180 s and a little).
const AWAY_LOOK := 70
const AWAY_MARGIN := 4
const AWAY_STAND := 190.0
const SNAP := 0.25
## The works with a stroke of their own (Client3D.STROKE_SLOTS, 804 amended (22)).
const WORK_WORDS: Array[String] = ["chop", "saw", "hammer", "hoe"]
## The work leg: how long to wait for a worker, and the stands' distances.
const WORK_WAIT := 240.0
const WORK_STANDS: Array[int] = [2, 6, 20]
## The town leg (EARS_ONLY=town, 939: the woods past the houses, the town
## through a roof): by the console's move, noon and 23:00, stood TOWN_STAND
## seconds each at the square, the east street, the temple's side, the west
## huts, a cell on the town's edge (its weight near a half), one well
## outside every town's reach, inside a hut (rect (210, 204)), inside a
## house (building.house, rect (214, 194)) and in the Mughouse's common
## room; first a wait out of the arrival. At noon, last, a walk from the
## square out past the last buildings to that cell outside, logged as it
## goes (the forest rising as the town falls behind). For about a second
## after each console move the Ambience bus's muffled twin can show (both
## before and after 939): the move's, not the place's; a walk meets none.
const TOWN_CELLS: Array[Vector2i] = [Vector2i(194, 211), Vector2i(210, 203), Vector2i(219, 195), Vector2i(196, 190)]
const IN_HUT := Vector2i(212, 205)
const IN_HOUSE := Vector2i(215, 196)
const IN_MUGHOUSE := Vector2i(6, 8)
const TOWN_STAND := 20.0
const ARRIVAL_WAIT := 40.0
## The Mughouse's floor (920): beside the fire, a hearth sit's cell, the
## room's middle, a far table's seat, the counter's guest side.
const HEARTH_STANDS: Array[Vector2i] = [Vector2i(1, 6), Vector2i(2, 8), Vector2i(6, 8), Vector2i(10, 11), Vector2i(9, 4)]
## In the street before the Mughouse's door (its links at (173, 213), (174, 213)).
const OUTSIDE_MUGHOUSE := Vector2i(174, 215)
const FOLK_NEAR := 16
const FOLK_WORKING := 45

var _bot: Node
var _file: FileAccess
var _t0 := 0
var _since := 0.0
var _played_at := 0
var _record: AudioEffectRecord
## The longest frame since the last snapshot, and the longest before the walk with when it ended (ms since boot).
var _frame_ms := 0.0
var _worst_ms := 0.0
var _worst_at := 0
var _view_ms := -1


## As the client boots (tour.gd): the 3D view a real client makes at boot,
## so the join's own rebuild builds the zone's room (Main._load_level emits
## room_built and so _on_room_built), as a player's client does.
func before_join(bot: Node) -> void:
	var main: Node = bot.main
	main.get_tree().process_frame.connect(_watch)
	if main._client3d == null:
		var began := Time.get_ticks_msec()
		main._show_3d()
		_view_ms = Time.get_ticks_msec() - began


func _watch() -> void:
	var ms: float = _bot_main_delta() * 1000.0
	_frame_ms = maxf(_frame_ms, ms)
	if _t0 == 0 and ms > _worst_ms:
		_worst_ms = ms
		_worst_at = Time.get_ticks_msec()


func _bot_main_delta() -> float:
	return Engine.get_main_loop().root.get_process_delta_time()


func run(bot: Node) -> void:
	_bot = bot
	var main: Node = bot.main
	bot.log_line("view made at boot in %d ms; the longest frame before the walk %.0f ms, ending %.1f s after boot"
			% [_view_ms, _worst_ms, _worst_at / 1000.0])
	if main._client3d == null:
		var began := Time.get_ticks_msec()
		main._show_3d()
		main._client3d.rebuild(main._terrain, main.level_centre)
		bot.log_line("no view at boot: made after joining, in %d ms" % (Time.get_ticks_msec() - began))
	var music := AudioServer.get_bus_index("Music")
	if music >= 0:
		AudioServer.set_bus_mute(music, true)
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, _record)
	_record.set_recording_active(true)
	_file = FileAccess.open(bot.out_dir.path_join("ears.jsonl"), FileAccess.WRITE)
	_t0 = Time.get_ticks_msec()
	_frame_ms = 0.0
	main.get_tree().process_frame.connect(_snap)
	if OS.get_environment("EARS_ONLY") == "hearth":
		await _hearth_leg()
		_end()
		return
	if OS.get_environment("EARS_ONLY") == "town":
		await _town_leg()
		_end()
		return
	await bot.admin("stock wilds/store wood 30")
	await bot.admin("hour %d" % DAY)
	_mark("hour %d" % DAY)
	await _walk(SPOTS)
	await _work_leg()
	await _relink()
	await _away_and_back()
	await bot.admin("hour %d" % NIGHT)
	_mark("hour %d" % NIGHT)
	await _walk(NIGHT_SPOTS)
	_end()


## The recording and the log closed, the walk's check made.
func _end() -> void:
	var main: Node = _bot.main
	main.get_tree().process_frame.disconnect(_snap)
	main.get_tree().process_frame.disconnect(_watch)
	_record.set_recording_active(false)
	var got := _record.get_recording()
	if got != null:
		got.save_to_wav(_bot.out_dir.path_join("ears.wav"))
		_bot.log_line("recorded %.1f s of Master" % got.get_length())
	else:
		_bot.log_line("no recording of Master (the driver mixed nothing)")
	_file.close()
	_bot.expect(true, "the walk logged", _bot.out_dir.path_join("ears.jsonl"))


## 920's hearth in the Mughouse's common room (umbrage_tavern, its hearth
## (0, 6) heard from (1, 6)), by day and by night: standing in town first for
## the day bed's level beside it, then at the fire, a hearth sit, the room's
## middle, a far table and the counter, then out of the door in the street.
func _hearth_leg() -> void:
	await _bot.admin("hour %d" % DAY)
	_mark("hour %d" % DAY)
	await _walk([SQUARE])
	for hour: int in [DAY, NIGHT]:
		await _bot.admin("hour %d" % hour)
		_mark("hour %d" % hour)
		await _bot.admin("zone move Tourbot umbrage_tavern")
		var inside: bool = await _bot.until(func() -> bool: return _bot.zone() == "umbrage_tavern", 30.0)
		_mark("in umbrage_tavern: %s" % inside)
		await _bot.seconds(4.0)
		for spot: Vector2i in HEARTH_STANDS:
			await _bot.admin("move Tourbot %d %d umbrage_tavern" % [spot.x, spot.y])
			await _bot.seconds(1.0)
			_mark("stand %s (%d from the hearth's floor cell)" % [_bot.cell(), maxi(absi(_bot.cell().x - 1), absi(_bot.cell().y - 6))])
			await _bot.seconds(STAND)
		await _bot.admin("zone move Tourbot wilds")
		await _bot.until(func() -> bool: return _bot.zone() == "wilds", 30.0)
		await _bot.admin("move Tourbot %d %d wilds" % [OUTSIDE_MUGHOUSE.x, OUTSIDE_MUGHOUSE.y])
		await _bot.seconds(1.0)
		_mark("outside the Mughouse %s" % [_bot.cell()])
		await _bot.seconds(STAND)


## 939's read: each stand marked with its cell, its town weight and its sky.
func _town_leg() -> void:
	var ambience: Ambience = _bot.main._client3d.ambience
	await _bot.admin("hour %d" % DAY)
	_mark("waiting out the arrival %d s" % ARRIVAL_WAIT)
	await _bot.seconds(ARRIVAL_WAIT)
	var edge := Vector2i(-1, -1)
	var away := Vector2i(-1, -1)
	for r in range(1, AWAY_LOOK):
		for cell: Vector2i in _ring(SQUARE, r):
			if not World.is_walkable(cell) or not World.fields.under_sky(cell):
				continue
			if edge.x < 0 and absf(ambience._town_nearness(cell) - 0.5) <= 0.05:
				edge = cell
			if away.x < 0 and r > int(Ambience.TOWN_FAR) and _clear_of_towns(ambience, cell):
				away = cell
		if away.x >= 0:
			break
	var stands: Array[Vector2i] = TOWN_CELLS.duplicate()
	stands.append_array([edge, away, IN_HUT, IN_HOUSE])
	for hour: int in [DAY, NIGHT]:
		await _bot.admin("hour %d" % hour)
		_mark("hour %d" % hour)
		for spot: Vector2i in stands:
			if spot.x < 0:
				_mark("no cell found for a stand")
				continue
			await _bot.admin("move Tourbot %d %d wilds" % [spot.x, spot.y])
			await _bot.seconds(1.0)
			_mark("stand %s at %s, town %.2f, under the sky %s" % [spot, _bot.cell(), ambience._town_nearness(_bot.cell()),
					World.fields.under_sky(_bot.cell())])
			await _bot.seconds(TOWN_STAND)
		await _bot.admin("zone move Tourbot umbrage_tavern")
		await _bot.until(func() -> bool: return _bot.zone() == "umbrage_tavern", 30.0)
		await _bot.admin("move Tourbot %d %d umbrage_tavern" % [IN_MUGHOUSE.x, IN_MUGHOUSE.y])
		await _bot.seconds(4.0)
		_mark("stand in the Mughouse at %s" % [_bot.cell()])
		await _bot.seconds(TOWN_STAND)
		await _bot.admin("zone move Tourbot wilds")
		await _bot.until(func() -> bool: return _bot.zone() == "wilds", 30.0)
		if hour == DAY and away.x >= 0:
			await _bot.admin("move Tourbot %d %d wilds" % [SQUARE.x, SQUARE.y])
			await _bot.seconds(4.0)
			_mark("walk out from %s to %s" % [_bot.cell(), away])
			await _bot.walk_to(away, 1, 120.0)
			_mark("walked out to %s, town %.2f" % [_bot.cell(), ambience._town_nearness(_bot.cell())])
			await _bot.seconds(5.0)


func _walk(spots: Array) -> void:
	for spot: Vector2i in spots:
		_mark("walk %s" % spot)
		await _bot.walk_to(spot, 2, 60.0)
		_mark("stand %s at %s, under the sky %s" % [spot, _bot.cell(), World.fields != null and World.fields.under_sky(_bot.cell())])
		await _bot.seconds(STAND)


## The first resident seen at a work with a stroke, else null.
func _worker() -> Resident:
	for entity: GridEntity in _bot.seen(""):
		if entity is Resident and str(entity.get("activity")) in WORK_WORDS:
			return entity
	return null


## Stood beside a worker at each of WORK_STANDS cells off, STAND seconds each.
func _work_leg() -> void:
	_mark("work: waiting for a worker")
	var found: Resident = null
	var end := Time.get_ticks_msec() + int(WORK_WAIT * 1000.0)
	var next_note := 0
	while Time.get_ticks_msec() < end:
		found = _worker()
		if found != null:
			break
		if Time.get_ticks_msec() >= next_note:
			next_note = Time.get_ticks_msec() + 30000
			_bot.log_line("work: nobody at %s yet" % ", ".join(WORK_WORDS))
		await _bot.seconds(1.0)
	if found == null:
		_mark("work: no worker in %d s" % int(WORK_WAIT))
		return
	for off: int in WORK_STANDS:
		if not is_instance_valid(found) or not str(found.get("activity")) in WORK_WORDS:
			found = _worker()
			if found == null:
				_mark("work: the worker stopped")
				return
		var spot := _off_by(found.tile, off)
		_mark("work walk %d off %s %s at %s" % [off, found.name, found.get("activity"), found.tile])
		await _bot.walk_to(spot, 1, 60.0)
		_mark("work stand %d off %s %s at %s" % [off, found.name, found.get("activity"), found.tile])
		await _bot.seconds(STAND)


## A walkable cell [param off] cells (Chebyshev) from [param at], trying
## the eight ways in turn; [param at] itself if none.
func _off_by(at: Vector2i, off: int) -> Vector2i:
	for way: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var cell := at + way * off
		if World.is_walkable(cell):
			return cell
	return at


## The link dropped and taken up again as a lost server's is
## (Main._reconnect), still by day in the town: the arrival must not play
## again (the coordinator, 11-14).
func _relink() -> void:
	var main: Node = _bot.main
	_mark("relink: dropping the link")
	Net.shutdown()
	main._reconnect()
	var back: bool = await _bot.joined(60.0)
	await _bot.settled()
	_mark("relink: %s" % ("back in" if back else "not back in 60 s"))
	await _bot.seconds(30.0)
	_mark("relink: stood 30 s")


## Out of every town's reach (Ambience._town_nearness 0, AWAY_MARGIN cells
## past it) for AWAY_STAND seconds, then back to the square once the last
## arrival is "arrive_again_s" old: a second arrival, its take not the first's.
func _away_and_back() -> void:
	var ambience: Ambience = _bot.main._client3d.ambience
	var away := Vector2i(-1, -1)
	for r in range(int(Ambience.TOWN_FAR) + AWAY_MARGIN, AWAY_LOOK):
		for cell: Vector2i in _ring(SQUARE, r):
			if World.is_walkable(cell) and _clear_of_towns(ambience, cell):
				away = cell
				break
		if away.x >= 0:
			break
	if away.x < 0:
		_mark("away: no cell out of every town's reach within %d" % AWAY_LOOK)
		return
	_mark("away walk %s" % away)
	await _bot.walk_to(away, 1, 120.0)
	_mark("away stand %s" % away)
	await _bot.seconds(AWAY_STAND)
	var again := float(Ambience.TOWN_DAY["arrive_again_s"])
	await _bot.until(func() -> bool: return float(ambience.arrival["since_cue"]) >= again + 5.0, again)
	_mark("back walk %s" % SQUARE)
	await _bot.walk_to(SQUARE, 2, 120.0)
	_mark("back stand %s" % SQUARE)
	await _bot.seconds(40.0)


## Whether every cell within AWAY_MARGIN of [param cell] is out of every town's reach.
func _clear_of_towns(ambience: Ambience, cell: Vector2i) -> bool:
	for dy in range(-AWAY_MARGIN, AWAY_MARGIN + 1, AWAY_MARGIN):
		for dx in range(-AWAY_MARGIN, AWAY_MARGIN + 1, AWAY_MARGIN):
			if ambience._town_nearness(cell + Vector2i(dx, dy)) > 0.0:
				return false
	return true


## The cells [param r] (Chebyshev) from [param at], south first.
func _ring(at: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-r, r + 1):
		out.append(at + Vector2i(x, r))
		out.append(at + Vector2i(x, -r))
	for y in range(-r + 1, r):
		out.append(at + Vector2i(r, y))
		out.append(at + Vector2i(-r, y))
	return out


func _mark(text: String) -> void:
	_bot.log_line(text)
	_file.store_line(JSON.stringify({"t": _now(), "mark": text, "cell": _cell()}))


func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _cell() -> Array:
	var at: Vector2i = _bot.cell()
	return [at.x, at.y]


func _snap() -> void:
	var view: Node = _bot.main._client3d
	if view == null:
		return
	var sfx: Node = view.sfx
	if sfx != null and sfx.played.size() > _played_at:
		for entry: Array in sfx.played.slice(_played_at):
			_file.store_line(JSON.stringify({"t": _now(), "played": entry, "cell": _cell()}))
		_played_at = sfx.played.size()
	_since += view.get_process_delta_time()
	if _since < SNAP:
		return
	_since = 0.0
	var players := []
	for node: Node in _bot.main.find_children("*", "AudioStreamPlayer3D", true, false) \
			+ _bot.main.find_children("*", "AudioStreamPlayer", true, false):
		var stream: AudioStream = node.stream
		if stream == null:
			continue
		players.append({"id": node.get_instance_id(), "path": stream.resource_path,
			"slot": str(node.get_meta("slot", "")), "bus": node.bus, "db": node.volume_db,
			"on": node.playing, "pos": node.get_playback_position() if node.playing else -1.0,
			"pitch": node.pitch_scale, "len": stream.get_length(),
			"at": [node.position.x, node.position.z] if node is Node3D else []})
	var folk := []
	var me: Vector2i = _bot.cell()
	for entity: GridEntity in _bot.seen(""):
		if not entity is Resident:
			continue
		var d := World.distance(entity.tile, me)
		var word := str(entity.get("activity"))
		if d <= FOLK_NEAR or word in WORK_WORDS and d <= FOLK_WORKING:
			folk.append([str(entity.name), entity.tile.x, entity.tile.y, word, str(entity.get("trade"))])
	_file.store_line(JSON.stringify({"t": _now(), "cell": _cell(), "zone": _bot.zone(), "rtt": roundi(Net.rtt_ms()),
		"frame_ms": roundi(_frame_ms), "players": players, "folk": folk}))
	_frame_ms = 0.0
