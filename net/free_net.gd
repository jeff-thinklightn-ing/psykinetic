extends RefCounted
## Free movement on the wire (decision 689; physics' free body, 688): a
## free body's input commands from its client, the server's packed state of
## it, the own body's view by replay and a mirror's by interpolation.
## Preloaded (no class_name): Player, World and Main use it.
##
## A command is {seq, intent, ticks}: the way held (quantised to int8s, as
## sent) for that long. The owning client closes one every SEND_SECONDS and
## sends the newest SEND_REPEAT each time, so a lost packet costs nothing;
## the server takes each seq once (World.request_free).
##
## The packed state (Player.free_state, replicated): the centre, the last command
## fully applied and how much of the next one, and the server tick, in
## STATE_BYTES. Empty: the body walks the grid.

## How often the owning client closes and sends a command, in seconds.
const SEND_SECONDS := 1.0 / 30.0
## How many of the newest commands each send carries.
const SEND_REPEAT := 4
## One command on the wire: seq (u16), intent x and y (s8), ms (u8).
const COMMAND_BYTES := 5
## The most a command lasts on the wire, in ms (u8).
const COMMAND_MS_MAX := 255
## The packed state: x, y (s32, 1/POS_SCALE cells), acked seq (u16), the
## head command's ticks used (u8, 1/USED_SCALE), the server tick (u16), the
## cell it holds (s16 x, s16 y; the replay's starting cell, 688 amended (3)).
const STATE_BYTES := 17
const POS_SCALE := 1024.0
const USED_SCALE := 80.0
## A correction of the own body under this many cells is blended out over
## BLEND_SECONDS; a bigger one (a push, a link) is shown at once.
const BLEND_MAX := 0.75
## Held by the server (a push): its centre blended in however far, up to this.
const HELD_BLEND_MAX := 3.0
const BLEND_SECONDS := 0.1
## The most commands the own view keeps unacknowledged (a server gone
## quiet): past it the oldest go.
const PENDING_MAX := 90


## The way [param intent] goes on the wire: each axis in 1/127ths.
static func quantise(intent: Vector2) -> Vector2:
	return Own.quantise(intent)


## [param seq] after [param other], seqs wrapping at 65536.
static func seq_after(seq: int, other: int) -> bool:
	return Own.seq_after(seq, other)


static func pack_commands(commands: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(commands.size() * COMMAND_BYTES)
	for i in commands.size():
		var command: Dictionary = commands[i]
		var at := i * COMMAND_BYTES
		var intent: Vector2 = command["intent"]
		bytes.encode_u16(at, int(command["seq"]) & 0xFFFF)
		bytes.encode_s8(at + 2, clampi(roundi(intent.x * 127.0), -127, 127))
		bytes.encode_s8(at + 3, clampi(roundi(intent.y * 127.0), -127, 127))
		bytes.encode_u8(at + 4, clampi(roundi(float(command["ticks"]) * World.TICK_DT * 1000.0), 0, COMMAND_MS_MAX))
	return bytes


## The commands in [param bytes] ([] for a packet the wrong size or with
## more than SEND_REPEAT), each intent at most a unit long.
static func unpack_commands(bytes: PackedByteArray) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if bytes.is_empty() or bytes.size() % COMMAND_BYTES != 0 or bytes.size() > SEND_REPEAT * COMMAND_BYTES:
		return commands
	for at in range(0, bytes.size(), COMMAND_BYTES):
		var intent := Vector2(bytes.decode_s8(at + 2), bytes.decode_s8(at + 3)) / 127.0
		commands.append({"seq": bytes.decode_u16(at), "intent": intent.limit_length(1.0),
			"ticks": bytes.decode_u8(at + 4) / 1000.0 * World.TICK_RATE})
	return commands


static func pack_state(pos: Vector2, acked: int, used: float, tick: int, held: Vector2i) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(STATE_BYTES)
	bytes.encode_s32(0, roundi(pos.x * POS_SCALE))
	bytes.encode_s32(4, roundi(pos.y * POS_SCALE))
	bytes.encode_u16(8, acked & 0xFFFF)
	bytes.encode_u8(10, clampi(roundi(used * USED_SCALE), 0, 255))
	bytes.encode_u16(11, tick & 0xFFFF)
	bytes.encode_s16(13, clampi(held.x, -32768, 32767))
	bytes.encode_s16(15, clampi(held.y, -32768, 32767))
	return bytes


## {pos, acked, used, tick} from [param bytes]; {} for none (the grid) or
## the wrong size. The tick is the one nearest [param near] with those low bits.
static func unpack_state(bytes: PackedByteArray, near: int) -> Dictionary:
	if bytes.size() != STATE_BYTES:
		return {}
	var low := bytes.decode_u16(11)
	var tick := near - ((near - low) & 0xFFFF)
	if near - tick > 0x8000:
		tick += 0x10000
	return {"pos": Vector2(bytes.decode_s32(0), bytes.decode_s32(4)) / POS_SCALE,
		"acked": bytes.decode_u16(8), "used": bytes.decode_u8(10) / USED_SCALE, "tick": tick,
		"held": Vector2i(bytes.decode_s16(13), bytes.decode_s16(15))}


## The own body's view (a client's or a host's own player): its commands
## since the last the server applied, replayed from the server's centre
## through World.free_glide, the code the server moves it by.
class Own:
	extends RefCounted
	var next_seq := 1
	## Closed commands the server has not yet applied whole: {seq, intent, ticks}.
	var pending: Array[Dictionary] = []
	## The open command: the way held now and for how long so far.
	var open_intent := Vector2.ZERO
	var open_seconds := 0.0
	## The centre after the server's state and the closed commands.
	var base := Vector2.INF
	## The cell held at base (688 amended (3)): the server's, from its state on.
	var held := World.NO_CELL
	## The way the last glide went, cells a tick.
	var way := Vector2.ZERO
	## What the view is off by and blends out (a small correction).
	var error := Vector2.ZERO
	## The server state replayed from last: {pos, acked, used}.
	var server := {}
	## Commands closed since the last send, the newest SEND_REPEAT sent.
	var sent: Array[Dictionary] = []
	var corrections := 0
	## The tick till which the server moves the body itself and drops its
	## commands (688 amended (2)): a push's slide, from the body's `pushed`
	## (pushed()), and after it the body's _reel_until, down_until and
	## downed_until, each as the server sends them. Till then nothing is
	## replayed on its centre, which is drawn as it comes, blended.
	var hold_until := -1.0

	## (FreeNet.quantise; here, where Own's own code reaches it.)
	static func quantise(intent: Vector2) -> Vector2:
		var unit := intent.limit_length(1.0)
		return Vector2(roundf(unit.x * 127.0), roundf(unit.y * 127.0)) / 127.0

	## (FreeNet.seq_after.)
	static func seq_after(seq: int, other: int) -> bool:
		var gap := (seq - other) & 0xFFFF
		return gap != 0 and gap < 0x8000

	## A frame of [param delta] seconds holding [param intent]: the commands
	## to send now ([] between sends). Standing still makes none: the walk's
	## last command goes as it stops, and is sent again twice more.
	func hold(entity: GridEntity, intent: Vector2, delta: float) -> Array[Dictionary]:
		error = error.move_toward(Vector2.ZERO, error.length() * minf(delta / BLEND_SECONDS, 1.0) + 0.0001)
		if base == Vector2.INF:
			base = entity.free_pos
			held = entity.tile
		var now := quantise(intent)
		if now == Vector2.ZERO:
			var out: Array[Dictionary] = []
			if open_intent != Vector2.ZERO and open_seconds > 0.0:
				out = _close(entity)  # The walk up to this frame.
			open_intent = Vector2.ZERO
			open_seconds = 0.0
			if out.is_empty() and _resends > 0:
				_idle += delta
				if _idle >= SEND_SECONDS:
					_idle = 0.0
					_resends -= 1
					out = sent.duplicate()
			return out
		open_intent = now
		open_seconds += delta
		if open_seconds < SEND_SECONDS:
			return []
		return _close(entity)

	var _resends := 0
	var _idle := 0.0

	## The open command closed: kept till the server applies it, the view's
	## base moved by it, and the newest SEND_REPEAT to send.
	func _close(entity: GridEntity) -> Array[Dictionary]:
		var ms := mini(roundi(open_seconds * 1000.0), COMMAND_MS_MAX)
		var command := {"seq": next_seq, "intent": open_intent, "ticks": ms / 1000.0 * World.TICK_RATE}
		next_seq = (next_seq + 1) & 0xFFFF
		open_seconds = 0.0
		pending.append(command)
		if pending.size() > PENDING_MAX:
			pending.pop_front()
		if not held_by_server(entity):
			_glide(entity, command)  # Held, the server drops it: the view stays on its centre.
		sent.append(command)
		while sent.size() > SEND_REPEAT:
			sent.pop_front()
		_resends = 2
		_idle = 0.0
		return sent.duplicate()

	## The server's state of the body: the commands it has applied dropped,
	## the rest replayed from its centre. A small difference from the view
	## is blended out, a big one shown at once.
	func confirm(entity: GridEntity, state: Dictionary) -> void:
		var acked: int = state["acked"]
		if not server.is_empty() and acked != int(server["acked"]) and not seq_after(acked, int(server["acked"])):
			pending.clear()  # The count started again (a spawn, the switch): what was sent before is gone.
		var overruled := held_by_server(entity)
		server = state
		while not pending.is_empty() and not seq_after(int(pending[0]["seq"]), acked):
			pending.pop_front()
		var was := base
		base = state["pos"]
		held = state["held"]
		way = Vector2.ZERO
		for i in (0 if overruled else pending.size()):
			var command: Dictionary = pending[i]
			if i == 0 and int(command["seq"]) == (acked + 1) & 0xFFFF and float(state["used"]) > 0.0:
				var rest := command.duplicate()
				rest["ticks"] = maxf(float(command["ticks"]) - float(state["used"]), 0.0)
				_glide(entity, rest)
			else:
				_glide(entity, command)
		if was != Vector2.INF:
			var fresh := was - base  # This state's own correction (error: those still blending).
			if fresh.length() > 0.02:
				corrections += 1
				if Net.test_latency > 0:
					print("[latency] free correction %.3f cells at %s, %d pending" % [fresh.length(), base, pending.size()])
			var off := error + fresh
			# Overruled, the server's moves are drawn as they come: blended
			# however far (a slide's first tick goes most of a cell).
			error = off if off.length() < (HELD_BLEND_MAX if overruled else BLEND_MAX) else Vector2.ZERO

	## Where to draw the body this frame, in cells.
	func shown(entity: GridEntity) -> Vector2:
		if base == Vector2.INF:
			return entity.free_pos
		var at := base
		if open_intent != Vector2.ZERO and open_seconds > 0.0 and not held_by_server(entity):
			at = World.free_glide(entity, base, open_intent, open_seconds * World.TICK_RATE, held)[0]
		return at + error

	## The way it is going now, cells a tick.
	func going() -> Vector2:
		return way if open_intent == Vector2.ZERO else open_intent * maxf(way.length(), 0.0001) / maxf(open_intent.length(), 0.0001)

	## Its body pushed [param tiles] cells (the body's `pushed`, 688 amended
	## (2)): the server slides it and drops what was sent, so that is dropped
	## here too, and nothing is replayed till the slide is over (a push of
	## under a cell: a tick).
	func pushed(tiles: int) -> void:
		hold_until = maxf(hold_until, World.tick + maxi(World.push_slide_ticks(tiles), 1))
		pending.clear()
		open_seconds = 0.0

	## Whether the server is moving [param entity] itself now, dropping its
	## commands: a push's slide, a stun, down or downed.
	func held_by_server(entity: GridEntity) -> bool:
		return World.tick < maxf(maxf(hold_until, entity._reel_until), maxf(entity.down_until, entity.downed_until))

	func _glide(entity: GridEntity, command: Dictionary) -> void:
		var glided: Array = World.free_glide(entity, base, command["intent"], float(command["ticks"]), held)
		base = glided[0]
		way = glided[1]
		held = glided[2]


## Another's free body (a mirror): the server's states as they came, drawn
## World.display_delay_ticks in the past between the two around it.
class Mirror:
	extends RefCounted
	## [[tick, pos]], oldest first.
	var samples: Array[Array] = []

	func add(state: Dictionary) -> void:
		var tick: int = state["tick"]
		while not samples.is_empty() and int(samples.back()[0]) >= tick:
			samples.pop_back()  # A late or repeated state: the newer stands.
		if not samples.is_empty() and tick - int(samples.back()[0]) > 1:
			# It stood still meanwhile (a standing body sends nothing): it set
			# off a tick ago, not glided all that while.
			samples.append([tick - 1, samples.back()[1]])
		samples.append([tick, state["pos"]])
		while samples.size() > 16:
			samples.pop_front()

	## The centre at [param at] (ticks, fractional) and the way it was going, cells a tick.
	func at(when: float) -> Array:
		if samples.is_empty():
			return [Vector2.INF, Vector2.ZERO]
		if when <= float(samples[0][0]):
			return [samples[0][1], Vector2.ZERO]
		for i in range(1, samples.size()):
			var a: Array = samples[i - 1]
			var b: Array = samples[i]
			if when <= float(b[0]):
				var span := float(b[0]) - float(a[0])
				var t := (when - float(a[0])) / span if span > 0.0 else 1.0
				var way: Vector2 = (b[1] - a[1]) / span if span > 0.0 else Vector2.ZERO
				return [(a[1] as Vector2).lerp(b[1], t), way]
		return [samples.back()[1], Vector2.ZERO]
