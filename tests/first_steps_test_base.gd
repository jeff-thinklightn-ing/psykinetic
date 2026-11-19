extends Node
## first_steps_test and first_steps_walk_test's shared part (the coordinator, 11-18:
## first_steps_test ran about 229 s alone and met saturn's 300 s cap inside a landing, over
## land.sh's 220 s slow-scene line, so it is two scenes, as level_test). The checks, the setup
## and end both halves share (_setup, _finish), and every helper both halves reach; each half
## sets its own port, calls _setup() with its own scratch files, its tests, then _finish().
## Not a scene.

var _failures := 0
var _main: Node
var _said: Array[String] = []


## The host on the wilds, her player new to her, the package forced on; its state and
## overlay in the half's own scratch files.
func _setup(state_path: String, overlay_dir: String) -> void:
	World.set_process(false)
	Net.companions = true
	Net.map_name = "wilds"
	Net.state_path = state_path
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	Level.overlay_dir = overlay_dir
	Companion.tends_unasked = false
	FirstSteps.forced = 1
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 5:
		await get_tree().process_frame
	for i in 3:
		World.step()
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)  # Nobody to be busy with (Main._keeper_busy).
	DayNight.set_hour(12.0)
	var pet := _companion()
	if pet != null:
		pet.said.connect(func(line: String) -> void: _said.append(line))
	if _player() != null:
		_a_rod(_player())  # The rows before 945 amended (4) play a player with a rod; its rows take it off.


## The result line and the exit code.
func _finish() -> void:
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _companion() -> Companion:
	for entity in World.get_entities():
		if entity is Companion and entity.spawned:
			return entity
	return null


func _put(entity: GridEntity, tile: Vector2i) -> void:
	if entity != null and entity.tile != tile:
		World._relocate(entity, tile)


## Her player by the square, she beside them, and a lull: nobody spoke, no
## line of hers, no fight, no walk, the next second's tick due.
func _lull(pet: Companion, player: Player, at := Vector2i(196, 214)) -> void:
	_put(player, _main._nearest_free(at))
	_put(pet, _main._nearest_free(player.tile + Vector2i(1, 0)))
	pet._keeper_spoke_tick = -100000
	pet._last_unasked_tick = -100000
	pet._last_speech_tick = -100000
	pet._fight_ended_tick = -100000
	pet._held_line = {}
	pet.first_steps.fought = -100000
	pet.guide = null
	_main._guides.erase(pet.keeper_id)
	player.led_by = ""  # As Main._guide_done leaves it (a walk dropped here, not ended).
	_main._chat_tick.clear()
	_main._first_steps_at = -100000
	player.hp = player.max_hp
	pet.first_steps.hp = -1
	pet.first_steps.hurt_since = -1


func _tick() -> void:
	_main._first_steps_at = -100000
	_main._first_steps_tick()


## Why no line came (a failing row's): each clause of Main._first_lull, and her chain's door.
func _why(pet: Companion, player: Player) -> String:
	var now := World.tick
	var fs := pet.first_steps
	return "quiet %s downed %s/%s idle_ok %s floor %s spoke %s fought %s zone %s dist %d hostile %s busy %s heard %s guide %s; door %s; next %s; offer %s; first_words %s at %d; lull %s" % [
		pet.quiet(), World.is_downed(pet), World.is_downed(player), pet._idle_ok(), now - pet._last_unasked_tick >= Companion.FLOOR_TICKS,
		now - pet._keeper_spoke_tick, now - fs.fought, pet.zone == player.zone, World.distance(pet.tile, player.tile),
		pet._hostile_within(Companion.SIGHT_RANGE), _main._keeper_busy(pet), pet.heard_by_anyone(), pet.guide != null and pet.guide.going(),
		_main._first_door(player.zone), fs.next_step(), fs.offer, pet.first_words, fs.first_words_tick, _main._first_lull(pet, player)]


## Her line reaches her player's client as a speech message, and the player presses Y (the key's own path,
## Main._unhandled_input): what a first-steps offer heard and taken by the key does (945 amended (3)).
func _press_y(pet: Companion, line: String) -> void:
	_main._chat_sent_at = -100000
	_main._chat_tick.clear()
	_main.standing_title = ""
	_main._lead_offer_msec = -1
	_main._on_message("speech", {"entity": str(pet.get_path()), "speaker": Companion._name_of(pet), "text": line})
	var me: Player = _main._local_player()
	_check(_main.lead_offer_stands(), "her offer heard: Y armed for it (%s; offer_said %s, msec %d, me %s, led_by %s, dist %s)" % [line,
		FirstSteps.offer_said(line), _main._lead_offer_msec, me != null, me.led_by if me != null else "", World.distance(pet.tile, me.tile) if me != null else -1])
	var ev := InputEventKey.new()
	ev.keycode = int(Keys.bound.get("yes", Keys.DEFAULTS.get("yes", KEY_Y)))
	ev.pressed = true
	_main._unhandled_input(ev)


## 945 amended (3), the coordinator's row: every offer of the deck (offer.*, the unasked go.*, hurt, bed
## and sit, and an asked or asked_one line joined from every choice.* clause), as her player's client hears
## it, arms Y; an arrive, no, stray, chain_end or risen line does not. On dd11ad637 none armed it.
func _says(line: String) -> void:
	_main._chat_tick.clear()
	_main._player_said(_player(), line)


func _in_deck(line: String, key: String, pet: Companion) -> bool:
	for each: Variant in FirstSteps.lines(key, str(pet.traits.get("temperament", ""))):
		var words := str(each)
		if words == line or "%s" in words and RegEx.create_from_string("^" + _escaped(words).replace("%s", ".+") + "$").search(line) != null:
			return true
	return false


static func _escaped(text: String) -> String:
	var out := ""
	for c in text:
		out += "\\" + c if c in ".?*+()[]{}|^$\\" else c
	return out


## 945 amended (3): the package switched on by its JSON (levels/companion_traits.json "first_steps" "on"),
## read with nothing forced.
func _play(seconds: float, until := Callable(), walk := false) -> bool:
	for i in roundi(seconds * World.TICK_RATE):
		World.step()
		if walk and i % World.TICK_RATE == 0:
			var player := _player()
			if player != null:
				_put(player, _main._nearest_free(Vector2i(196 + 2 * (int(i / float(World.TICK_RATE)) % 2), 214)))
		if until.is_valid() and until.call():
			return true
	return not until.is_valid()


## Her walk to [param kind] after a yes on [param path]'s offer, as play has it: the server steps (World.step,
## her guide's own step and stop), her player on her heels (the cell she left), till the walk ends. The row
## (the coordinator's, 945 amended (3)): it ends on arrival, her arrive.<kind> line said and the
## "[firststeps] arrived" line logged, and the place reached today.
func _led(path: String, kind: String) -> void:
	var pet := _companion()
	var player := _player()
	var walk: Guide = pet.guide if pet != null else null
	var going := walk != null and walk.going() and str(walk.goal.get("first", "")) == kind
	_main.set("first_logged", "")  # (Main.first_logged; absent before 945 amended (3)'s arrival decks: the old-code check.)
	var from := _said.size()
	if going:
		for i in 150 * World.TICK_RATE:
			var was := pet.tile
			World.step()
			if pet.guide == null:
				break
			if pet.tile != was and player.tile != was:
				_put(player, _main._nearest_free(was))
	# A short walk ends inside her speech floor after her offer (Companion.FLOOR_TICKS): her line is held, said
	# as it clears (917), as in play.
	var heard := func() -> bool: return _said.slice(from).any(func(each: String) -> bool: return _in_deck(each, "arrive." + kind, pet))
	if going and not heard.call():
		_play(float(Companion.FLOOR_TICKS + Companion.HELD_GRACE_TICKS) / World.TICK_RATE + 1.0, heard)
	var lines := _said.slice(from)
	var said: bool = heard.call()
	var logged := str(_main.get("first_logged")).begins_with("arrived ")
	var seen := kind in ["catch", "rod"] or pet.first_steps.reached_today(kind, Townsfolk.day_of(World.steps))
	var view := _in_view(walk.goal if walk != null else {}, player.tile, pet.tile)
	_check(going and said and logged and seen and view.begins_with("in view"), "%s, %s: a yes ends in her arrive line and the [firststeps] arrived line, the place in their view (walk %s, stopped %s; said %s; logged \"%s\"; reached %s; at %s, goal %s; %s)" % [
		path, kind, going, walk.stopped if walk != null else "none", lines, _main.get("first_logged"), seen, pet.tile,
		walk.goal.get("cell") if walk != null else null, view])


## Whether the place her walk [param goal] showed is in view of her player at [param at] (the coordinator, from
## ui-design's runs: the hut at the screen's edge): at the camera's resting yaw (Client3D._camera_offset_at(0),
## the camera south-east of the player, looking north-west) the place's building (its "seen", else the building
## nearest its cell) lies up the screen from them, no farther to the side than ahead plus two cells, within 12
## cells. The pond: they stand within FIRST_NEAR of her on its bank. The place's cell is its "seen" where she
## stops off it (Main._first_sight), else her goal's own.
func _in_view(goal: Dictionary, at: Vector2i, pet_at: Vector2i) -> String:
	if goal.is_empty():
		return "no walk"
	if str(goal.get("first", "")) == "rod":
		var counter: Vector2i = goal.get("seen", goal["cell"])
		return ("in view: at Rolf's counter, %d off it" if World.distance(at, counter) <= 3 else "out of view: %d from Rolf's counter") % World.distance(at, counter)
	if goal.get("bank", false) or str(goal.get("first", "")) == "pond":
		return ("in view: on the bank beside her (%s)" if World.distance(at, pet_at) <= _main.FIRST_NEAR else "out of view: %s from her on the bank") % World.distance(at, pet_at)
	var rect := _building_near(str(goal["area"]), goal.get("seen", goal["cell"]))  # Its own reading, not Main's.
	if rect.size == Vector2i.ZERO:
		return "no building near %s" % goal["cell"]
	var middle := Vector2i(rect.get_center())
	var off: Vector2i = middle - at
	var ahead := -(off.x + off.y)  # Up the screen (north-west), in half-diagonal steps.
	var aside := off.x - off.y
	var ok := ahead > 0 and absi(aside) <= ahead + 4 and World.distance(at, middle) <= 12
	return "%s: its building at %s, %d ahead and %d aside of them at %s" % ["in view" if ok else "out of view", middle, ahead, aside, at]


## The building in [param area] nearest [param cell] within Level.PLACE_RADIUS; Rect2i() for none.
func _building_near(area: String, cell: Vector2i) -> Rect2i:
	var best := Rect2i()
	var best_far := Level.PLACE_RADIUS + 1
	for building: Dictionary in Level.load_level(area).get("buildings", []):
		var laid: Variant = Level.building_rect(building)
		if laid is Rect2i:
			var rect: Rect2i = laid
			var far := World.distance(cell, Vector2i(clampi(cell.x, rect.position.x, rect.end.x - 1), clampi(cell.y, rect.position.y, rect.end.y - 1)))
			if far < best_far:
				best_far = far
				best = rect
	return best


## A companion after a travel (a new body): her lines heard.
func _a_rod(player: Player) -> void:
	if World.rod_slot(player) < 0:
		World.put_item(player, player, World.free_slot_for(player, "fishing_rod"), World.items.mint("fishing_rod", "built"))


## Noon, and the server's ticks till Rolf keeps his stall (Main._first_stall: his body made and walked to it).
func _rolf_keeps() -> bool:
	DayNight.set_hour(12.0)
	return _play(120, func() -> bool: return _main._first_stall("wilds").get("kept", false) == true)


## A fresh card, her chain at its rod step: the Mughouse done, its player back out of it, no rod on them.
func _fresh_card(record: PlayerRecord) -> FirstSteps:
	var fresh := FirstSteps.new()
	record.companion["first_steps"] = {"done": FirstSteps.CHAIN.duplicate(), "told": true}
	fresh.card = record.companion["first_steps"]
	_main._first_steps_live[record.player_id] = fresh
	var pet := _companion()
	pet.first_steps = fresh
	pet.guide = null
	_main._guides.erase(pet.keeper_id)
	_main._guide_offers.erase(pet.keeper_id)
	return fresh


func _restore_run_a(keep: FirstSteps, record: PlayerRecord, lists: Array, lists_was: Array) -> void:
	var pet := _companion()
	for i in lists.size():
		(lists[i] as Array).assign(lists_was[i])
	record.companion["first_steps"] = keep.card
	_main._first_steps_live[record.player_id] = keep
	if pet != null:
		pet.first_steps = keep
		pet.guide = null
		_main._guides.erase(pet.keeper_id)
		_main._guide_offers.erase(pet.keeper_id)
	keep.offer = {}
