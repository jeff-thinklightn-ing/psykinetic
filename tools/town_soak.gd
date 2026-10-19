extends Node
## The living-world soak (the coordinator's ask, 2026-10-19; npc's): the
## wilds town run locally for days as the box runs it (the lawspeaker off,
## Snagfin seated, the thief, the bard, strays, the scoundrel), with a few
## test players who stand in the inn of an evening and at the counter by
## day, taking what the town's people offer. It prints what happened as
## "SOAK ..." lines (counts, the ledger's moves, every resident's stints
## seen and standing with each player) for npc to read beside the stdout
## log, the transcripts and the mind log it writes under --out. Local only:
## a scratch world, never the box's. Headless, through the bench gate:
##   godot --headless --path <repo> --scene res://tools/town_soak.tscn -- --days=30 --players=3 --out=<folder>

const TOWN := "wilds/store"
const DAY := 54000
const HOUR := DAY / 24
## The town's people as the box's grew (the balance tool's nine and a
## guard), their hidden types set outright so every side-doing is in play.
const FOLK := [["smith_1", "Odo", "smith"], ["cook_1", "Mags", "cook"], ["carp_1", "Pell", "carpenter"],
	["hunt_1", "Hob", "hunter"], ["tan_1", "Hew", "tanner"], ["farm_1", "Tam", "farmer"],
	["hand_1", "Ash", "hauler"], ["hand_2", "Bea", "hauler"], ["guard_1", "Gar", "guard"], ["hand_3", "Nix", "hauler"]]
const TYPES := {"hand_1": "thief", "hand_2": "bard", "hand_3": "scoundrel", "carp_1": "scholar"}
const PLAYER_NAMES := ["Ann", "Bo", "Cy"]

var _main: Node
var _players: Array = []
var _counts := {}
var _offered := {}
var _done_lines: Array = []
var _songs: Array = []
var _stints := {}  # worker id -> {doing: true}
var _hours_seen := 0
var _out := ""
## --ask: the words soak. Each day one player asks each resident one of the
## usual things, in rotation, and the loop waits for the answer (the
## resident mind on the box's Ollama over a tunnel) before stepping on, one
## request per ask and no retries, so the box is never tied up.
var _ask := false
var _asks_made := 0
var _asks_answered := 0
## --give=N: at the counter each day, each player gives up to N gold toward
## the town's next build (economy's 499, Economy.contribute), for the
## contributions soak.
var _give := 0
## --woodlot=DX,DY: the town gets a woodlot that far from its store (economy's
## 521, a work site the woodcutter walks to), held by the town;
## --woodlot-taken=DAY: goblins take it at the start of that day.
var _woodlot := Vector2i(-99999, -99999)
var _woodlot_taken := -1
const WOODLOT := "wilds/soak_woodlot"
const QUESTIONS := ["Who are you?", "What is new in the town?", "What do you need?", "What do you think of %s?", "Is it true that %s"]
var _prev := {}  # Main's own context callbacks, put back before the quit.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var days := 30
	var players := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = maxi(int(arg.trim_prefix("--days=")), 1)
		elif arg.begins_with("--players="):
			players = clampi(int(arg.trim_prefix("--players=")), 1, 3)
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--ask":
			_ask = true
		elif arg.begins_with("--give="):
			_give = maxi(int(arg.trim_prefix("--give=")), 0)
		elif arg.begins_with("--woodlot="):
			var parts := arg.trim_prefix("--woodlot=").split(",")
			_woodlot = Vector2i(int(parts[0]), int(parts[1]) if parts.size() > 1 else 0)
		elif arg.begins_with("--woodlot-taken="):
			_woodlot_taken = int(arg.trim_prefix("--woodlot-taken="))
	if _out.is_empty() or _out.begins_with("/var/lib/psykinetic") or _out.begins_with("user://"):
		push_error("town_soak: --out=<a local folder> is needed, never the box's or user://")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17880)
	Net.companions = false
	Net.map_name = "wilds"
	Net.lawspeaker = "off"
	Net.state_path = ports.scratch_path("town_soak_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	Net.transcripts_dir = _out.path_join("transcripts")
	Net.mind_log_path = _out.path_join("mind.log")
	if FileAccess.file_exists(Net.mind_log_path):
		DirAccess.remove_absolute(Net.mind_log_path)
	MindLog.enabled = true
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	if _ask:
		_main.mind_kind = "ollama"  # The real resident mind (Net.llm_url and llm_model from the flags), never the stub for words.
	print("######## soak: %d days, %d players, the wilds, lawspeaker %s, mind %s %s ########" % [days, players, Net.lawspeaker, _main.mind_kind, Net.llm_model if _ask else ""])
	# The town's people.
	for each: Array in FOLK:
		World.towns.note_rescue(TOWN, each[0], each[1], each[2])
		if TYPES.has(each[0]):
			World.production._workers[each[0]]["type"] = TYPES[each[0]]
	# The players: the host's and far peers of their own.
	for i in players - 1:
		_main._admit(1000 + i, "11111111-0000-4000-8000-%012d" % (1000 + i), PLAYER_NAMES[i + 1])
	await get_tree().process_frame
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			_players.append(entity)
	for player: Player in _players:
		World.economy.add_gold(player.player_id, 60, "soak")
	if _woodlot != Vector2i(-99999, -99999):
		# A place the level doesn't have, for the measure only: put straight into Holdings.
		var store: Dictionary = World.holdings.place(TOWN)
		World.holdings._places[WOODLOT] = {"id": WOODLOT, "area": store["area"], "key": "soak_woodlot", "cell": store["cell"] + _woodlot,
			"name": "the soak's woodlot", "kind": "woodlot", "radius": 2, "worth": 1, "start": "town", "town": TOWN}
		World.holdings._holder[WOODLOT] = "town"
		World.holdings._strength[WOODLOT] = 1
		World.holdings._since[WOODLOT] = World.steps
		print("SOAK woodlot at %s, %s from the store" % [store["cell"] + _woodlot, _woodlot])
	print("SOAK players %s" % [_players.map(func(p: Player) -> String: return "%s@%s" % [p.player_id.left(8), p.tile])])
	# What the town's people offer and do, counted as it happens.
	for key: String in ["done", "asked", "say"]:
		_prev[key] = Offers.ctx.get(key, Callable())
	var prev_done: Callable = _prev["done"]
	Offers.ctx["done"] = func(player_id: String, ask: Dictionary, line: String, paid: int) -> void:
		_count("done")
		_count("paid_gold", paid)
		_count("done_" + str(ask.get("kind", "")))
		_done_lines.append("day %d: %s" % [Townsfolk.day_of(World.steps), line])
		if prev_done.is_valid():
			prev_done.call(player_id, ask, line, paid)
	var prev_asked: Callable = _prev["asked"]
	Offers.ctx["asked"] = func(player_id: String, ask: Dictionary) -> void:
		_count("taken")
		if prev_asked.is_valid():
			prev_asked.call(player_id, ask)
	var prev_say: Callable = _prev["say"]
	Offers.ctx["say"] = func(town: String, song: Dictionary) -> void:
		_songs.append("day %d: %s%s (to %s)" % [Townsfolk.day_of(World.steps), song.get("line", ""), " " + str(song.get("second", "")) if not str(song.get("second", "")).is_empty() else "", song.get("listeners", [])])
		if prev_say.is_valid():
			prev_say.call(town, song)
	var steps := days * DAY
	var next_hour := 0
	for s in steps:
		World.step()  # Main syncs the bodies and ticks the town on World.ticked.
		if s >= next_hour:
			next_hour += HOUR
			await get_tree().process_frame
			await _hourly()
	_report(days)
	# Main's callbacks back, so no closure into this node outlives it (a static Callable into a freed node crashes the quit).
	for key: String in _prev:
		Offers.ctx[key] = _prev[key]
	_players.clear()
	Net.state_path = ""
	get_tree().quit(0)


func _count(key: String, by := 1) -> void:
	_counts[key] = int(_counts.get(key, 0)) + by


## Every hour of the day: where the players stand (the inn of an evening,
## the counter by day, the square else), what they take at the counter,
## and which stint each resident's body is in.
func _hourly() -> void:
	var hour := int(DayNight.hour(DayNight.now()))
	var day := Townsfolk.day_of(World.steps)
	_hours_seen += 1
	for entity in World.townsfolk():
		var body := entity as Resident
		_stints.get_or_add(body.worker_id, {})[body.doing] = true
	var store := World.holdings.place(TOWN)
	var store_cell: Vector2i = store.get("cell", Vector2i.ZERO)
	var inn: Rect2i = _main._inn_rect(TOWN)
	var target := store_cell + Vector2i(0, 3)
	var at := "square"
	if hour >= 19 and hour <= 22 and inn.size != Vector2i.ZERO:
		target = inn.get_center()
		at = "inn"
	var beside: Array[Vector2i] = []
	var counter: GridEntity = null
	if hour in [10, 11, 15, 16]:
		counter = _counter()
		if counter != null:
			# The walkable cells in reach of the counter (World.can_melee, as Main._counter_near
			# asks through World.reaches), free or one of ours standing there already; each
			# player gets a cell of their own, so three players never share one and fall
			# back to a cell out of reach (the 30-day soak's 360 refused buys, 2026-10-19).
			for side: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var cell := counter.tile + side
				if World.is_walkable(cell) and World.can_melee(cell, counter.tile) and (World.is_free(cell) or _ours_at(cell)):
					beside.append(cell)
			if not beside.is_empty():
				at = "counter"
	var taken: Array[Vector2i] = []
	for i in _players.size():
		var player: Player = _players[i]
		if not is_instance_valid(player) or not player.spawned:
			continue
		var cell: Vector2i
		if at == "counter":
			cell = player.tile if beside.has(player.tile) and not taken.has(player.tile) else Vector2i(-99999, -99999)
			if cell == Vector2i(-99999, -99999):
				for spot: Vector2i in beside:
					if not taken.has(spot) and (World.is_free(spot) or spot == player.tile):
						cell = spot
						break
			if cell == Vector2i(-99999, -99999):
				cell = _main._nearest_free(counter.tile)  # More players than cells in reach: the rest stand off.
			taken.append(cell)
		else:
			cell = _main._nearest_free(target + Vector2i(i, 0))
		if player.tile != cell:
			World._relocate(player, cell)
	if at == "counter":
		_at_the_counter(day)
		if hour == 10 and day % 3 == 0 and not _ask:
			_speak(day)
		if hour == 11 and _give > 0:
			for player: Player in _players:
				if is_instance_valid(player):
					var given := World.economy.contribute(TOWN, player.player_id, _give)
					if given > 0:
						_count("given_gold", given)
	if _ask and hour == 9:
		await _ask_round(day)
	if hour == 0 and day == _woodlot_taken and World.holdings.place(WOODLOT).size() > 0:
		World.holdings.take(WOODLOT, "goblins")
		print("SOAK day %d: goblins take the woodlot" % day)
	if hour == 0:
		print("SOAK day %d: treasury %d, residents %d, bodies %d, inn %s" % [day, World.stockpile.count(TOWN, "gold"), World.towns.residents(TOWN).size(),
			World.townsfolk().size(), "standing" if inn.size != Vector2i.ZERO else "none"])


## Whether one of the soak's players stands on [param cell].
func _ours_at(cell: Vector2i) -> bool:
	for player: Player in _players:
		if is_instance_valid(player) and player.spawned and player.tile == cell:
			return true
	return false


## The town's shop counter in this zone, or null.
func _counter() -> GridEntity:
	for entity: GridEntity in World._entities:
		if entity is Chest and (entity as Chest).shop and entity.spawned and World.shop_place(entity) == TOWN:
			return entity
	return null


## At the counter: each player hears what the bodies within reach offer and
## takes the first thing that is not a sale (a commission, a plea, a page),
## and buys the first sale they can afford.
func _at_the_counter(day: int) -> void:
	for player: Player in _players:
		if not is_instance_valid(player):
			continue
		for entity in World.townsfolk():
			var body := entity as Resident
			if World.distance(body.tile, player.tile) > 4:
				continue
			var offers := Offers.of(body.worker_id, player.player_id)
			for offer: Dictionary in offers:
				if bool(offer.get("open", false)):
					continue
				_count("offered")
				_offered["%s" % offer.get("kind", "")] = int(_offered.get("%s" % offer.get("kind", ""), 0)) + 1
			var taken := false
			for offer: Dictionary in offers:
				if bool(offer.get("open", false)):
					continue
				var accept := str(offer.get("accept", ""))
				if accept == Offers.BUY:
					if World.economy.gold(player.player_id) >= int(offer.get("cost", 0)):
						var before := World.economy.gold(player.player_id)
						_main._accept_offer(player, str(offer["id"]), 0)
						if World.economy.gold(player.player_id) < before:
							_count("bought")
							_count("spent_gold", before - World.economy.gold(player.player_id))
						else:
							_count("buy_failed")
				elif not taken and accept in [Offers.TAKE, Offers.CARRY, "read"]:
					_main._accept_offer(player, str(offer["id"]), 0)
					_count("accepted_" + accept)
					taken = true


## Now and then a player speaks to the nearest body: the ask is made (the
## standing entry, the errands met by speaking); whether anyone answers
## depends on a resident mind being configured, which the log will say.
func _speak(day: int) -> void:
	for player: Player in _players:
		if not is_instance_valid(player):
			continue
		var nearest: Resident = null
		var best := 99
		for entity in World.townsfolk():
			var d := World.distance(entity.tile, player.tile)
			if d < best:
				best = d
				nearest = entity
		if nearest != null and best <= 6:
			_main._ask_resident(nearest, _main._display_name(player), "How goes it, %s?" % nearest.person, player)
			_count("spoke")


## The words soak's round for [param day]: every resident with a body is
## asked one of QUESTIONS by one player (the kinds rotate by day and
## resident), the player put beside them first; the answer is waited for
## (the mind's one request), at most ANSWER_WAIT seconds, before the next.
const ANSWER_WAIT := 60.0


func _ask_round(day: int) -> void:
	var bodies: Array = World.townsfolk().duplicate()
	bodies.sort_custom(func(a: Resident, b: Resident) -> bool: return a.worker_id < b.worker_id)
	var names: Array = bodies.map(func(b: Resident) -> String: return b.person)
	var lore: Variant = Offers._call(Offers.ctx, "lore", [TOWN])
	var facts: Array = lore if lore is Array else []
	var i := 0
	for body: Resident in bodies:
		if not is_instance_valid(body) or not body.spawned:
			continue
		var player: Player = _players[i % _players.size()]
		var kind := (day + i) % QUESTIONS.size()
		var question: String = QUESTIONS[kind]
		if kind == 3:
			var others: Array = names.filter(func(n: String) -> bool: return n != body.person)
			question = question % (others[(day + i) % others.size()] if not others.is_empty() else "the town")
		elif kind == 4:
			var fact := str(facts[(day + i) % facts.size()]).trim_suffix(".") if not facts.is_empty() else "the mine is old"
			question = question % (fact.left(1).to_lower() + fact.substr(1) + "?")
		var beside: Vector2i = _main._nearest_free(body.tile + Vector2i(1, 0))
		if is_instance_valid(player) and player.spawned:
			World._relocate(player, beside)
			var before := Transcript.written  # The question is one record; the answer, when it comes, another.
			_main._ask_resident(body, _main._display_name(player), question, player)
			_asks_made += 1
			print("SOAK ask day %d: %s -> %s [%d]: %s" % [day, _main._display_name(player), body.person, kind, question])
			var waited := 0.0
			while Transcript.written < before + 2 and waited < ANSWER_WAIT:
				await get_tree().create_timer(0.5).timeout
				waited += 0.5
				_main._resident_voices()  # Main sends asks and takes answers on the world tick, which stands still while we wait.
			if Transcript.written >= before + 2:
				_asks_answered += 1
			else:
				print("SOAK ask unanswered after %.0f s: %s" % [waited, body.person])
		i += 1


## Every resident's card, beliefs and standing, and lore's facts, as JSON
## under --out, so every word said can be checked against what is true.
func _dump_cards() -> void:
	var out := {"lore": Offers._call(Offers.ctx, "lore", [TOWN]), "residents": {}}
	for id: String in World.production.worker_ids(TOWN):
		var who := World.production.worker(id)
		out["residents"][id] = {"name": who.get("name", id), "trades": who.get("trades", []), "type": who.get("type", ""), "purse": who.get("purse", 0),
			"loan": who.get("loan", 0.0), "card": Townsfolk.card_of(World.production, id), "heard": who.get("heard", [])}
	var file := FileAccess.open(_out.path_join("cards.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(out, "	"))
		file.close()


func _report(days: int) -> void:
	_dump_cards()
	if _ask:
		print("SOAK asks made %d, answered %d" % [_asks_made, _asks_answered])
	print("")
	print("######## SOAK REPORT: %d days ########" % days)
	var keys: Array = _counts.keys()
	keys.sort()
	for key: String in keys:
		print("SOAK count %s %d" % [key, _counts[key]])
	print("SOAK offered by kind %s" % [_offered])
	var ledger := World.stockpile.ledger(TOWN).map(func(line: Dictionary) -> String: return "%s %s" % [line.get("by", ""), line.get("from", "")])
	print("SOAK tally %s" % [Townsfolk.tally])  # The side-doings' own count: the store's ledger keeps only its last lines.
	print("SOAK ledger (its last %d lines only): loans %d, repaid %d" % [ledger.size(),
		ledger.filter(func(l: String) -> bool: return l.begins_with("loan:")).size(),
		ledger.filter(func(l: String) -> bool: return l.begins_with("repay:")).size()])
	print("SOAK songs %d" % _songs.size())
	for song: String in _songs:
		print("SOAK song " + song)
	print("SOAK done lines %d" % _done_lines.size())
	for line: String in _done_lines:
		print("SOAK done " + line)
	for id: String in World.production.worker_ids(TOWN):
		var who := World.production.worker(id)
		var card := Townsfolk.card_of(World.production, id)
		var standing := {}
		for player: Player in _players:
			if is_instance_valid(player) and card.get("standing", {}).has(player.player_id):
				standing[_main._display_name(player)] = Standing.score(card, player.player_id)
		var doings: Array = _stints.get(id, {}).keys()
		doings.sort()
		print("SOAK resident %s %s (%s): purse %d, loan %.0f, away %s, facts %d, asks %d, stints %s, standing %s%s" % [who.get("name", id), who.get("trades", []), who.get("type", ""),
			who.get("purse", 0), float(who.get("loan", 0.0)), who.get("away", false), card.get("facts", []).size(), card.get("asks", []).size(), doings, standing,
			", strayed" if card.has("strayed") else ""])
	for player: Player in _players:
		if is_instance_valid(player):
			print("SOAK player %s: gold %d, commissions open %d" % [_main._display_name(player), World.economy.gold(player.player_id),
				(_main._records.get(player.player_id).commissions.size() if _main._records.has(player.player_id) else -1)])
	print("SOAK hours seen %d; party log last lines:" % _hours_seen)
	for line: String in _main.party_log.last(40):
		print("SOAK party " + line)
	print("SOAK DONE")
