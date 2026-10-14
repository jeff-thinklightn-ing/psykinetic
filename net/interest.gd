class_name Interest
extends RefCounted
## Server: which entities and doors each client is sent, by nearness to its
## player (decision 217). A peer sees what is in the 8x8-cell chunks round
## its player's: a chunk comes in within ENTER chunks of it (about 36 cells)
## and goes out only beyond LEAVE (about 44), so nothing flickers at the
## edge. Its own player and companion it always sees. The view reaches 24
## to 28 cells at its widest and sounds carry 30 (Sfx.MAX_DISTANCE), so
## nothing comes or goes where it could be seen or heard.
##
## The synchronizers' visibility filters (GridEntity._visible_to, Door's)
## ask sees(); a change of what a peer sees asks the synchronizers of only
## what is in the chunks that came or went (update_visibility), and the
## spawner spawns or despawns them on that client. Entities and doors are
## kept in an index by chunk, kept up from World's entity_moved and
## entity_despawned, so a player crossing into a new chunk looks at those
## chunks, not the zone.

const CHUNK := 8
## A chunk comes into view within this many chunks of the player's.
const ENTER := 4
## A chunk seen leaves view only beyond this many.
const LEAVE := 5
## A recompute slower than this is logged.
const SLOW_MSEC := 10.0

## False (--no-interest): every client is sent everything in its zone, as
## before decision 217 (for comparing, or if this ever goes wrong).
var enabled := true
## How many synchronizers were asked again (update_visibility), for the
## bench and the "net" command.
var asked := 0

## Zone -> chunk -> {node: true}: every entity and door, by where it is.
var _index: Dictionary[String, Dictionary] = {}
## Node instance id -> [zone, chunk]: where it is in the index.
var _where: Dictionary[int, Array] = {}
## Peer -> [zone, its player's chunk].
var _centre: Dictionary[int, Array] = {}
## Peer -> {chunk: true}: what it sees.
var _seen: Dictionary[int, Dictionary] = {}


## Forgets every zone and peer (a server starting, a test's new Main).
func reset() -> void:
	_index.clear()
	_where.clear()
	_centre.clear()
	_seen.clear()
	asked = 0


## The chunk [param cell] is in.
static func chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))


## Where [param node] (a GridEntity or a Door) stands: a door, at the cell
## west or north of its edge.
static func cell_of(node: Object) -> Vector2i:
	if node is Door:
		return Vector2i(node.key.x, node.key.y)
	return node.tile


## Whether [param peer] is sent [param node] (its zone is the caller's to
## check): its own player and companion always; the rest if it stands in a
## chunk the peer sees. A peer with no player yet sees nothing else.
func sees(peer: int, node: Object) -> bool:
	if not enabled:
		return true
	if node is GridEntity and (node.owner_peer == peer or node.keeper_peer == peer):
		return true
	var seen: Dictionary = _seen.get(peer, {})
	return not seen.is_empty() and seen.has(chunk_of(cell_of(node)))


## [param node] spawned: into the index.
func add(node: Object) -> void:
	_put(node, str(node.zone), chunk_of(cell_of(node)))


## [param node] gone: out of the index.
func remove(node: Object) -> void:
	var id := node.get_instance_id()
	var was: Array = _where.get(id, [])
	if was.is_empty():
		return
	_where.erase(id)
	var chunks: Dictionary = _index.get(was[0], {})
	var there: Dictionary = chunks.get(was[1], {})
	there.erase(node)
	if there.is_empty():
		chunks.erase(was[1])


## Zone [param zone_name]'s entities and doors were all freed (a rebuild):
## its index starts again.
func clear_zone(zone_name: String) -> void:
	var chunks: Dictionary = _index.get(zone_name, {})
	for chunk: Vector2i in chunks:
		for node: Variant in chunks[chunk]:
			if is_instance_valid(node):
				_where.erase(node.get_instance_id())
	_index.erase(zone_name)


## World's entity_moved: [param entity] stepped from [param from] to
## [param to]. Crossing into another chunk, it is sent to or taken from the
## peers that see one of the two and not the other; a player crossing
## changes what its own peer sees.
func moved(entity: GridEntity, from: Vector2i, to: Vector2i) -> void:
	var old_chunk := chunk_of(from)
	var new_chunk := chunk_of(to)
	if old_chunk == new_chunk and _where.has(entity.get_instance_id()):
		return
	_put(entity, entity.zone, new_chunk)
	if entity.sync != null:
		var connected := _connected()
		for peer: int in _seen:
			if peer not in connected:
				continue
			if _centre[peer][0] != entity.zone:
				continue
			var seen: Dictionary = _seen[peer]
			if seen.has(old_chunk) != seen.has(new_chunk):
				entity.sync.update_visibility(peer)
				asked += 1
	if entity is Player and entity.owner_peer != 0:
		centre(entity.owner_peer, entity.zone, to)


## [param peer]'s player is at [param cell] of [param zone_name] (joined,
## respawned, travelled, or stepped into another chunk): what it sees is
## worked out again, and the synchronizers of what is in the chunks that
## came or went are asked again.
func centre(peer: int, zone_name: String, cell: Vector2i) -> void:
	var chunk := chunk_of(cell)
	var was: Array = _centre.get(peer, [])
	if not was.is_empty() and was[0] == zone_name and was[1] == chunk:
		return
	var old_seen: Dictionary = _seen.get(peer, {}) if not was.is_empty() and was[0] == zone_name else {}
	var new_seen := {}
	for seen: Vector2i in old_seen:
		if _apart(seen, chunk) <= LEAVE:
			new_seen[seen] = true
	for dy in range(-ENTER, ENTER + 1):
		for dx in range(-ENTER, ENTER + 1):
			new_seen[chunk + Vector2i(dx, dy)] = true
	_centre[peer] = [zone_name, chunk]
	_seen[peer] = new_seen
	if peer not in _connected():
		return  # A peer with no connection (the host's own, a bench's) is asked nothing.
	var started := Time.get_ticks_usec()
	var asked_before := asked
	var chunks: Dictionary = _index.get(zone_name, {})
	for each: Vector2i in _changed(old_seen, new_seen):
		var there: Dictionary = chunks.get(each, {})
		for node: Variant in there.keys():
			if not is_instance_valid(node):
				there.erase(node)
				continue
			if node.sync != null:
				node.sync.update_visibility(peer)
				asked += 1
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	if ms > SLOW_MSEC:
		print("[interest] tick %d: peer %d moved into chunk %s of %s: %d things asked again in %.1f ms" % [
			World.tick, peer, chunk, zone_name, asked - asked_before, ms])


## [param peer] left its zone or the game: it sees nothing until centre()
## is told where its player is again.
func forget(peer: int) -> void:
	_centre.erase(peer)
	_seen.erase(peer)


## How many chunks [param peer] sees (0 with no player yet).
func chunks_seen(peer: int) -> int:
	return _seen.get(peer, {}).size()


## How many nodes [param peer] is sent now, of those indexed in
## [param zone_name] (its own player and companion left out).
func count_seen(peer: int, zone_name: String) -> int:
	var count := 0
	var chunks: Dictionary = _index.get(zone_name, {})
	for chunk: Vector2i in _seen.get(peer, {}):
		count += (chunks.get(chunk, {}) as Dictionary).size()
	return count


func _put(node: Object, zone_name: String, chunk: Vector2i) -> void:
	remove(node)
	if not _index.has(zone_name):
		_index[zone_name] = {}
	var chunks: Dictionary = _index[zone_name]
	if not chunks.has(chunk):
		chunks[chunk] = {}
	chunks[chunk][node] = true
	_where[node.get_instance_id()] = [zone_name, chunk]


## The peers connected now: only they have synchronizers to ask.
static func _connected() -> PackedInt32Array:
	return Net.multiplayer.get_peers() if Net.multiplayer.has_multiplayer_peer() else PackedInt32Array()


static func _apart(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The chunks in one of [param a] and [param b] and not the other.
static func _changed(a: Dictionary, b: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for chunk: Vector2i in a:
		if not b.has(chunk):
			out.append(chunk)
	for chunk: Vector2i in b:
		if not a.has(chunk):
			out.append(chunk)
	return out
