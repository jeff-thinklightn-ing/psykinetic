extends Node
## Seamless crossings (decision 822, P1), on a host at held with its 3D view:
## the plane links and offsets; the server's "near" answer (the zone's
## state, then "near"), refused far from the link, for another zone, or
## again within NEAR_EVERY_MS; off by default; switched on, the zone past a
## near link built beside the live view where it lies on the world plane,
## none under the memory floor; crossing into it swaps the rooms (no card,
## no build, the zone left held, the view the same frame), and back again;
## switched off, a crossing lets it go behind the card. Prints PASS/FAIL
## per assertion and quits with exit code 1 if any assertion failed, 0
## otherwise.

const LINK := Vector2i(52, 0)  # held's link to the wilds.

var _failures := 0
var _main: Node
var _heard: Array[String] = []


func _ready() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17896)
	Net.companions = false
	Net.map_name = "held"
	Net.state_path = ""
	Level.overlay_dir = ports.scratch("overlay/")
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	if _main._client3d == null:
		_main._show_3d()
	await _frames(30)
	Net.message_received.connect(func(kind: String, _data: Dictionary) -> void: _heard.append(kind))
	_test_plane()
	_test_near()
	await _test_preload()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _player() -> Player:
	return _main._local_player()


## The host's player [param cells] south of held's link to the wilds (on the
## nearest walkable cell there).
func _stand(cells: int) -> void:
	var player := _player()
	var at := LINK + Vector2i(0, cells)
	for r in 12:
		for dx in range(-r, r + 1):
			var cell := at + Vector2i(dx, r)
			if World.is_walkable(cell) and World.get_entity_at(cell) == null:
				World._relocate(player, cell)
				return
	World._relocate(player, at)


func _test_plane() -> void:
	print("\n== the plane's links and offsets (822) ==")
	var held: Array = _main.plane_links("held")
	_check(held.size() == 1 and held[0]["tile"] == LINK and held[0]["to"] == "wilds", "held's one plane link: the wilds at %s (%s)" % [LINK, held])
	var wilds: Array = _main.plane_links("wilds").map(func(link: Dictionary) -> String: return link["to"])
	wilds.sort()
	_check(wilds == ["foothills", "forest", "held", "hills"], "the wilds' plane links, not its barrow (%s)" % [wilds])
	_check(_main.near_link("held", LINK + Vector2i(10, 80), 80) == "wilds" and _main.near_link("held", LINK + Vector2i(0, 81), 80) == "",
			"near within 80 cells on both axes, not at 81")
	var offset: Vector3 = _main.plane_offset("held", "wilds")
	_check(offset.is_equal_approx(Vector3(-78, 2.73, -256)), "the wilds lie at %s from held" % offset)


func _test_near() -> void:
	print("\n== the server's \"near\": the zone's state then \"near\"; refused far, for another zone, or again soon ==")
	var player := _player()
	_stand(40)
	_heard.clear()
	_main._near(player, "wilds")
	_check(not _heard.is_empty() and _heard.back() == "near" and "roofs" in _heard and not "map" in _heard,
			"near the link: the wilds' state, then \"near\", no map (%s)" % [_heard])
	_heard.clear()
	_main._near(player, "wilds")
	_check(_heard.is_empty(), "again within %d ms: nothing" % _main.NEAR_EVERY_MS)
	_main._near_told.clear()
	_main._near(player, "forest")
	_check(_heard.is_empty(), "a zone with no link near: nothing")
	_stand(_main.NEAR_REACH + 10)
	_main._near(player, "wilds")
	_check(_heard.is_empty(), "%d cells off: nothing" % (_main.NEAR_REACH + 10))
	_check(World.zones.has("held") and not World.zones.has("wilds"), "the wilds never opened for it")


func _test_preload() -> void:
	print("\n== switched on: the wilds built beside held near its link, on the plane; none under the floor; the swap and back; off, let go at a crossing ==")
	_check(not _main.seamless_crossings, "off unless switched on")
	_main.seamless_crossings = true
	_main.neighbour_free_floor = 1 << 62
	_stand(30)
	await _frames(_main.NEIGHBOUR_LOOK_FRAMES * 2)
	_check(_main._neighbour == null and _main._floor_said, "under the memory floor: no neighbour, said once")
	_main.neighbour_free_floor = 0
	_stand(_main.PRELOAD_CELLS + 20)
	await _frames(_main.NEIGHBOUR_LOOK_FRAMES * 2)
	_check(_main._neighbour == null, "%d cells from the link: none" % (_main.PRELOAD_CELLS + 20))
	_stand(30)
	var frames := 0
	while (_main._neighbour == null or not _main._neighbour.room_whole()) and frames < 3000:
		await get_tree().process_frame
		frames += 1
	var view: Client3D = _main._neighbour
	_check(view != null and view.room_whole() and _main._neighbour_zone == "wilds" and view._neighbour and not view.is_processing(),
			"30 cells from it: the wilds built over %d frames" % frames)
	if view == null:
		return
	_check(view.get_parent() == _main._client3d.get_parent() and view.position.is_equal_approx(_main._client3d.position + _main.plane_offset("held", "wilds")),
			"beside the live view, where the wilds lie on the plane (%s)" % view.position)
	_check(view.get_children() == [view._room] and _main._client3d._room != view._room, "its own room alone")
	_stand(_main.PRELOAD_CELLS + 20)
	await _frames(_main.NEIGHBOUR_LOOK_FRAMES * 2)
	_check(_main._neighbour == view, "walking off: kept (one neighbour, let go only for another)")
	await _test_swap(view)
	# Off before it crosses: the card and a build, the held one let go.
	view = _main._neighbour
	_main.seamless_crossings = false
	_check(_main.travel(Net.local_id, "wilds", "from_held"), "switched off, the host crosses to the wilds")
	await _frames(2)
	_check(_main._neighbour == null and (not is_instance_valid(view) or view.is_queued_for_deletion())
			and _main._client3d.building_room and _main.arrival_card != null and _main.arrival_card.showing,
			"the crossing lets it go and builds behind the card, as ever")


## Step 4: the host crosses into the held wilds and back. Each time the
## live view takes the held room (no card, no build), the zone left is held
## where it lies, the live view stays at its place, the glimpse of the held
## zone is hidden and plane_origin is the live room's place.
func _test_swap(view: Client3D) -> void:
	var live: Client3D = _main._client3d
	var held_room: Node3D = live._room
	var wilds_room: Node3D = view._room
	var live_at := live.position
	var pairs: Array = [["wilds", "from_held", wilds_room, held_room, "held"], ["held", "from_wilds", held_room, wilds_room, "wilds"]]
	for pair: Array in pairs:
		_check(_main.travel(Net.local_id, pair[0], pair[1]), "the host crosses to %s" % pair[0])
		await _frames(2)
		_check(live._room == pair[2] and _main._neighbour == view and view._room == pair[3] and _main._neighbour_zone == pair[4]
				and _main._shown_zone == pair[0] and live._terrain == _main._terrain,
				"swapped: %s's room live, %s's held, no other" % [pair[0], pair[4]])
		_check(not live.building_room and (_main.arrival_card == null or not _main.arrival_card._building) and not _main._arriving(),
				"no build and no card")
		_check(live.position.is_equal_approx(live_at) and view.position.is_equal_approx(live_at + _main.plane_offset(pair[0], pair[4])),
				"the live view kept its place, the held one where %s lies from it (%s)" % [pair[4], view.position])
		_check(Client3D.plane_given.is_equal_approx(live._plane_at)
				and view._plane_at.is_equal_approx(live._plane_at + _main.plane_offset(pair[0], pair[4])),
				"plane_origin the live room's place (%s), the held one's beside it" % Client3D.plane_given)
		var shown := live._glimpses.filter(func(g: Client3D) -> bool: return is_instance_valid(g) and g.visible and str(g.get_meta("to", "")) == pair[4])
		_check(shown.is_empty(), "no glimpse of %s over its own room" % pair[4])
		await _frames(_main.NEIGHBOUR_LOOK_FRAMES * 2)
		_check(_main._neighbour == view, "at %s's side of the link: %s still held" % [pair[0], pair[4]])

