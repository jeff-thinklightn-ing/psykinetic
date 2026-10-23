extends Node
## The living-world soak (the coordinator's ask, 2026-10-19; npc's): the
## wilds town run locally for days as the box runs it (the lawspeaker off,
## Snagfin seated, the thief, the bard, strays, the scoundrel), with a few
## test players who stand in the inn of an evening and at the counter by
## day, taking what the town's people offer. It prints what happened as
## "SOAK ..." lines (counts, the ledger's moves, every resident's stints
## seen and standing with each player) for npc to read beside the stdout
## log, the transcripts and the mind log it writes under --out. Local only:
## a scratch world, never the box's. Headless, through the gate as a soak (394 amended (8)):
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
## The visible work seen (566 amended): activity -> {"name tile facing": samples}, sampled every WORK_EVERY steps.
var _work := {}
const WORK_EVERY := 20
## The server's step cost (release's ask, 521 amended): World.step timed, in microseconds.
var _tick_total := 0
var _tick_worst := 0
var _tick_n := 0
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
## --retrain=NAME:TRADE:DAY: the resident named NAME turns to TRADE at the
## start of that day (npc's Production.retrain, as Pip turns acolyte),
## leaving their bench for economy's 552 newcomer.
var _retrain := {}
## --rescue-after=DAYS: newcomers are sought (613): each is placed at a
## stand-in refuge and brought home DAYS days after the word went out, a
## player's rescue stood in for, so the measure still grows trades.
var _rescue_after := -1.0
const QUESTIONS := ["Who are you?", "What is new in the town?", "What do you need?", "What do you think of %s?", "Is it true that %s"]
var _prev := {}  # Main's own context callbacks, put back before the quit.
## Hails (554), the mood (555) and the road's knowledge (551 phase 2), the
## coordinator's soak of 2026-10-21. The counted soak records every hail the
## resident mind is asked (SoakMind, which echoes the cue), seats a resting
## companion "Wren" whose mood turns sullen on day 3, apart on day 10 and
## fond on day 20, counts the town's "is unhappy with" lines a day, and
## feeds the road's news to a scratch companion card through RoadKnowledge.
## --hail-day: one day over the real mind (the box's Ollama through the
## tunnel): at four hours each player stands by each resident with the
## day's mark cleared, so every cue kind is asked in turn, at most
## --hail-calls=N asks; the lines go to --review=<file> (hails.md) for Jeff.
var _hail_day := false
var _hail_calls := 60
var _review := "C:/dev/review/npc/hails.md"
var _hails: Array = []  # {day, hour, resident, player, kind, cue, others}
var _hail_visits: Array = []  # hail day: {day, hour, resident, player, kind}
var _road_card := {}
var _road_news: Array = []
var _road_areas: Array = []
var _road_days: Array = []
var _mood_days := {}  # day -> {entry id: true} of "is unhappy with" lines first said that day
const WREN := "companion:Wren"


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
		elif arg == "--hail-day":
			_hail_day = true
		elif arg.begins_with("--hail-calls="):
			_hail_calls = maxi(int(arg.trim_prefix("--hail-calls=")), 1)
		elif arg.begins_with("--review="):
			_review = arg.trim_prefix("--review=")
		elif arg.begins_with("--give="):
			_give = maxi(int(arg.trim_prefix("--give=")), 0)
		elif arg.begins_with("--woodlot="):
			var parts := arg.trim_prefix("--woodlot=").split(",")
			_woodlot = Vector2i(int(parts[0]), int(parts[1]) if parts.size() > 1 else 0)
		elif arg.begins_with("--retrain="):
			var parts := arg.trim_prefix("--retrain=").split(":")
			if parts.size() == 3:
				_retrain = {"name": parts[0], "trade": parts[1], "day": int(parts[2])}
		elif arg.begins_with("--rescue-after="):
			_rescue_after = maxf(float(arg.trim_prefix("--rescue-after=")), 0.0)
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
	if _ask or _hail_day:
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
	if not _ask and not _hail_day:
		var mind := SoakMind.new()
		mind.soak = self
		_main._resident_mind = mind  # Every hail asked is recorded; the answer echoes the cue (554).
	var prev_road: Callable = _main.road_heard
	_main.road_heard = func(town: String, news: Dictionary) -> void:
		_road_news.append("day %d: %s %s camp %s areas %s" % [news.get("day", -1), news.get("kind", ""), news.get("route", ""), news.get("camp", ""), news.get("areas", [])])
		for area: Variant in news.get("areas", []):
			if str(area) not in _road_areas:
				_road_areas.append(str(area))
		var entry := RoadKnowledge.heard(_road_card, news, World.holdings, Guide.rules())
		if not entry.is_empty():
			_count("road_heard")
		if prev_road.is_valid():
			prev_road.call(town, news)
	# A companion resting in town, a worker among them with no body of her own (555): her mood turns on days 3, 10 and 20.
	World.production.add_worker(WREN, "Wren", ["cook"], TOWN, WREN)
	World.production.set_origin(WREN, "companion:" + _players[0].player_id)
	World.production.set_away(WREN, false)
	if _hail_day:
		_seed_hail_day()
	if _rescue_after >= 0.0:
		World.towns.place_sought = func(_town: String, _trade: String, _kinds: Array, _id: String) -> Dictionary:
			return {"place": "soak_refuge", "where": "wilds"}
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
		var t0 := Time.get_ticks_usec()
		World.step()  # Main syncs the bodies and ticks the town on World.ticked.
		var dt := Time.get_ticks_usec() - t0
		_tick_total += dt
		_tick_worst = maxi(_tick_worst, dt)
		_tick_n += 1
		if s % WORK_EVERY == 0:
			_sample_work()
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


## Each body's activity where it shows it (566 amended): a chop should stand
## beside the woodlot's block facing it, a carried log end beside the pile.
func _sample_work() -> void:
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or body.activity.is_empty():
			continue
		var seen: Dictionary = _work.get_or_add(body.activity, {})
		var where := "%s %s %s" % [body.person, body.tile, body.facing]
		seen[where] = int(seen.get(where, 0)) + 1


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
	if _rescue_after >= 0.0:
		for entry: Dictionary in World.towns.sought(TOWN):
			if World.steps - int(entry["since"]) >= int(_rescue_after * DayNight.day_steps) and not str(entry["place"]).is_empty():
				World.towns.free_sought(str(entry["id"]), "soak")
				World.towns.sought_home(str(entry["id"]))
				_count("sought_home")
				print("SOAK day %d: %s the %s is found and brought home" % [day, entry["name"], entry["trade"]])
	if hour == 0 and not _retrain.is_empty() and day == int(_retrain["day"]):
		for who in World.towns.residents(TOWN):
			if str(World.production.worker(who).get("name", "")) == _retrain["name"]:
				var was: Array = World.production.worker(who)["trades"]
				World.production.retrain(who, _retrain["trade"])
				print("SOAK day %d: %s the %s turns %s" % [day, _retrain["name"], ", ".join(was), _retrain["trade"]])
	if hour == 0:
		if day == 3:
			World.production.set_mood(WREN, "sullen", "they struck her")
		elif day == 10:
			World.production.set_mood(WREN, "apart", "they left her behind")
		elif day == 20:
			World.production.set_mood(WREN, "fond", "")
		var mood := Townsfolk.mood_of(World.production, WREN)
		if mood == "apart" and Townsfolk.whereabouts("cook", 10.0, Season.name_at(World.steps), "", WREN, day, mood) != "temple":
			_count("mood_apart_not_seated")
		if not _road_areas.is_empty():
			var weighed := RoadKnowledge.weigh(_road_card, _road_areas, day, World.holdings, Guide.rules())
			_road_days.append("day %d: weight %.1f, dangers %d, worst %s" % [day, weighed["weight"], RoadKnowledge.dangers_of(_road_card).size(),
				weighed["worst"].get("why", "")])
	if hour == 23:
		var log: Variant = Offers._call(Offers.ctx, "memory", [TOWN])
		if log is Array:
			for entry: Variant in log:
				if entry is Dictionary and " is unhappy with " in str(entry.get("text", "")):
					_mood_days.get_or_add(Townsfolk.day_of(int(entry.get("first_said", 0))), {})[str(entry.get("id", ""))] = true
	if _hail_day and (_hours_seen - 1) % 24 in [9, 11, 13, 15]:  # By the soak's own hourly count: the clock's hour lands on an integer only by chance.
		await _hail_round(day, (_hours_seen - 1) % 24)
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
	print("SOAK tick avg %.0f us, worst %d us, over %d steps" % [float(_tick_total) / maxi(_tick_n, 1), _tick_worst, _tick_n])
	var kinds: Array = _work.keys()
	kinds.sort()
	for kind: String in kinds:
		var places: Array = _work[kind].keys()
		places.sort_custom(func(a: String, b: String) -> bool: return int(_work[kind][a]) > int(_work[kind][b]))
		print("SOAK work %s: %d samples at %s" % [kind, _work[kind].values().reduce(func(acc: int, n: int) -> int: return acc + n, 0), places.slice(0, 6).map(func(p: String) -> String: return "%s x%d" % [p, _work[kind][p]])])
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
	_report_hails()
	print("SOAK DONE")


# --- Hails, the mood and the road (the coordinator's soak, 2026-10-21) ---------------

## The recording mind's answer to [param ask]: a hail is recorded with the
## day, the hour, who to whom, the cue's kind and text, and how many other
## asks stood in the queue at that moment (none should); the answer echoes
## the cue, so the spoken path runs. Any other ask gets a word.
func _soak_voice(ask: Dictionary) -> Dictionary:
	var kind := str(ask.get("hail", ""))
	if kind.is_empty():
		return {"say": "Aye, so it is."}
	var user := str(ask.get("user", ""))
	var player := user.substr(0, maxi(user.find(" comes within speaking distance"), 0))
	var cue := _cue_of(user)
	_hails.append({"day": Townsfolk.day_of(World.steps), "hour": int(DayNight.hour(DayNight.now())), "resident": str(ask.get("speaker", "")),
		"player": player, "kind": kind, "cue": cue, "others": _main._resident_asks.size() + _main._resident_out.size() - 1})
	_count("hail")
	_count("hail_" + kind)
	return {"say": cue}


## The cue text out of a hail's user turn.
static func _cue_of(user: String) -> String:
	var head := "One thing is on your mind: "
	var a := user.find(head)
	var b := user.find(" Say one line to them about it")
	return user.substr(a + head.length(), b - a - head.length()) if a >= 0 and b > a else ""


## The hail day's ground: a thing the town noted today, a memory the
## lawspeaker ruled today (he is off in the soak), and a loan on the
## smith, so the plea, the news and the ruling can be asked beside the sky
## and the greeting.
func _seed_hail_day() -> void:
	var log: Variant = Offers._call(Offers.ctx, "memory", [TOWN])
	if log is Array:
		var news := TownMemory.note(log, "a wagon was struck on the road to the market", "soak", "", World.steps)
		if not news.is_empty():
			news["tier"] = TownMemory.CANDIDATE
			news["event"] = true  # The town's own line, as Townsfolk._remember marks it.
		var ruled := TownMemory.note(log, "the well was fouled by goblins in the night", "soak", "", World.steps)
		if not ruled.is_empty():
			ruled["tier"] = TownMemory.MEMORY
			ruled["ruling"] = {"ruling": "accept", "because": "the guard saw them", "step": World.steps}
		Offers._call(Offers.ctx, "set_memory", [TOWN, log])
	World.production.set_loan("smith_1", 12.0)


## The hail day's round at [param hour] of [param day]: each of the first
## two players stands by each resident in turn with the day's mark and the
## minute cleared, Main's hail tick runs, and when a hail was queued the
## loop waits for the mind's answer (one request, no retries), at most
## _hail_calls in all.
func _hail_round(day: int, hour: int) -> void:
	var bodies: Array = World.townsfolk().duplicate()
	bodies.sort_custom(func(a: Resident, b: Resident) -> bool: return a.worker_id < b.worker_id)
	for body: Resident in bodies:
		for i in mini(_players.size(), 2):
			if _hail_visits.size() >= _hail_calls:
				return
			var player: Player = _players[i]
			if not is_instance_valid(body) or not body.spawned or not is_instance_valid(player) or not player.spawned:
				continue
			# The world stands still between visits, so the mind's last result is taken here; an ask still out blocks a hail (the lowest ask), so wait for it.
			var cleared := 0.0
			_main._resident_voices()
			while not _main._resident_out.is_empty() and cleared < ANSWER_WAIT:
				await get_tree().create_timer(0.5).timeout
				cleared += 0.5
				_main._resident_voices()
			if not _main._resident_out.is_empty():
				print("SOAK hail day: an ask stayed out %.0f s; cleared for the soak" % cleared)
				_main._resident_out.clear()
			var card := Townsfolk.card_of(World.production, body.worker_id)
			if card.get("hails", {}).get("to", {}).has(player.player_id):
				card["hails"]["to"].erase(player.player_id)
				World.production.set_card(body.worker_id, card)
			_main._hail_tried.clear()
			_main._hail_at.clear()
			_main._mind_last_ticks = 0
			World._relocate(player, _main._nearest_free(body.tile + Vector2i(1, 0)))
			var before_asks: int = _main._resident_asks.size()
			_main._hails_tick()
			if _main._resident_asks.size() <= before_asks:
				var why := "blocked" if _main._hail_blocked(player, Time.get_ticks_msec(), Townsfolk.rules().get("hail", {})) else (
					"out %d asks %d slow %d" % [_main._resident_out.size(), _main._resident_asks.size(), _main._mind_last_ticks]
					if not _main._resident_out.is_empty() or _main._mind_last_ticks > 50 else "no cue")
				print("SOAK hail day %d %02d:00: %s to %s: nothing (%s)" % [day, hour, body.person, _main._display_name(player), why])
				continue
			var kind := str(_main._resident_asks.back()["ask"].get("hail", ""))
			_hail_visits.append({"day": day, "hour": hour, "resident": body.person, "player": _main._display_name(player), "kind": kind})
			print("SOAK hail day %d %02d:00: %s to %s (%s)" % [day, hour, body.person, _main._display_name(player), kind])
			var before := Transcript.written
			var waited := 0.0
			while Transcript.written < before + 1 and waited < ANSWER_WAIT:
				await get_tree().create_timer(0.5).timeout
				waited += 0.5
				_main._resident_voices()
			if Transcript.written < before + 1:
				print("SOAK hail unanswered after %.0f s: %s" % [waited, body.person])


## The hails' tallies: the limits (one a resident a player a day, none
## with another ask waiting), repeats of a cue by one resident, the kinds,
## the mood's gossip a day, the road's news and its weight, the names in
## the cues and the lines, and any id in a done or lapse line. The hail
## day writes its lines to the review file.
func _report_hails() -> void:
	print("SOAK hails %d" % _hails.size())
	var per_pair := {}  # resident|player|day -> n
	var per_player_day := {}
	var per_cue := {}  # resident|cue -> [days]
	var kinds := {}
	var with_others := 0
	for hail: Dictionary in _hails:
		var key := "%s|%s|%d" % [hail["resident"], hail["player"], hail["day"]]
		per_pair[key] = int(per_pair.get(key, 0)) + 1
		var pkey := "%s|%d" % [hail["player"], hail["day"]]
		per_player_day[pkey] = int(per_player_day.get(pkey, 0)) + 1
		per_cue.get_or_add("%s|%s" % [hail["resident"], hail["cue"]], []).append(int(hail["day"]))
		kinds[hail["kind"]] = int(kinds.get(hail["kind"], 0)) + 1
		if int(hail["others"]) > 0:
			with_others += 1
	var pair_max := 0
	for key: String in per_pair:
		pair_max = maxi(pair_max, per_pair[key])
	var player_max := 0
	var player_sum := 0
	for key: String in per_player_day:
		player_max = maxi(player_max, per_player_day[key])
		player_sum += per_player_day[key]
	print("SOAK hail kinds %s" % [kinds])
	print("SOAK hail limit: most by one resident to one player in a day %d (1 is the rule); most in a player's hearing in a day %d, mean %.1f over %d player-days" % [
		pair_max, player_max, float(player_sum) / maxf(per_player_day.size(), 1.0), per_player_day.size()])
	print("SOAK hail with another ask waiting or out: %d (0 is the rule)" % with_others)
	var repeats := 0
	var repeat_lines: Array = []
	for key: String in per_cue:
		var days: Array = per_cue[key]
		if days.size() > 1:
			repeats += 1
			repeat_lines.append("%s x%d days %s" % [key.left(60), days.size(), days])
	print("SOAK hail repeats (one resident, one cue text, more than once): %d" % repeats)
	for line: String in repeat_lines.slice(0, 12):
		print("SOAK hail repeat " + line)
	for hail: Dictionary in _hails.slice(0, 12):
		print("SOAK hail sample day %d %02d:00 %s to %s [%s]: %s" % [hail["day"], hail["hour"], hail["resident"], hail["player"], hail["kind"], hail["cue"]])
	var mood_max := 0
	var mood_days: Array = _mood_days.keys()
	mood_days.sort()
	for day: int in mood_days:
		mood_max = maxi(mood_max, _mood_days[day].size())
	print("SOAK mood gossip: %d lines over days %s, most in a day %d (1 is the rule); apart not seated %d" % [
		mood_days.reduce(func(n: int, d: int) -> int: return n + _mood_days[d].size(), 0), mood_days, mood_max, int(_counts.get("mood_apart_not_seated", 0))])
	print("SOAK road news %d (heard as dangers %d), areas %s" % [_road_news.size(), int(_counts.get("road_heard", 0)), _road_areas])
	for line: String in _road_news.slice(0, 10):
		print("SOAK road " + line)
	for line: String in _road_days:
		print("SOAK road " + line)
	_name_check()
	var ids := RegEx.create_from_string("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}")
	var leaked := 0
	for line: String in _done_lines:
		if ids.search(line) != null:
			leaked += 1
			print("SOAK id in a done or lapse line: " + line)
	print("SOAK ids in done or lapse lines: %d (0 is the rule)" % leaked)
	if _hail_day:
		_write_review()


## Every capitalised word in the cues that is not a resident's or a player's
## name, the town's word, or a sentence's first word: for npc to read.
func _name_check() -> void:
	var known := {}
	for each: Array in FOLK:
		known[each[1]] = true
	for name: String in PLAYER_NAMES:
		known[name] = true
	for word: String in ["Wren", "I", "The", "It", "You", "Because", "Nothing", "Aye", "Jeff"]:
		known[word] = true
	for part: String in str(_main._world_map.areas.get(World.zone.name, {}).get("display_name", "")).split(" "):
		known[part] = true
	var caps := RegEx.create_from_string("(?<=[a-z,;:] )[A-Z][a-z]+")
	var unknown := {}
	for hail: Dictionary in _hails:
		for hit: RegExMatch in caps.search_all(str(hail["cue"])):
			if not known.has(hit.get_string()):
				unknown[hit.get_string()] = int(unknown.get(hit.get_string(), 0)) + 1
	print("SOAK hail names not a resident's, a player's or the town's: %s" % [unknown])


## The hail day's lines, from the mind log Main wrote (each hail's prompt,
## the words said and the aside, in the order the visits queued them), to
## the review file as a table.
func _write_review() -> void:
	var rows: Array = []
	if FileAccess.file_exists(Net.mind_log_path):
		var file := FileAccess.open(Net.mind_log_path, FileAccess.READ)
		while not file.eof_reached():
			var line := file.get_line()
			if line.is_empty():
				continue
			var row: Variant = JSON.parse_string(line)
			if row is Dictionary and str(row.get("trigger", "")).begins_with("hail: "):
				rows.append(row)
	var out := "# Hails: a day's worth over the box's mind\n\n"
	out += "The town soak's hail day (decision 554, %s): each player stood by each resident with the day's mark cleared, so the resident's next thing to say was asked of the real resident mind (the box's qwen3:14b through the tunnel). Cue: what the sim put on the resident's mind, from the card, the news and the memory only. Said: the words that went out as speech. Aside: the one clause of how (336 amended). Echo marks a line that repeats the cue near enough word for word.\n\n" % Time.get_date_string_from_system()
	out += "| # | Hour | Resident | To | Cue kind | Cue | Said | Aside | Echo |\n|---|---|---|---|---|---|---|---|---|\n"
	var n := 0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var visit: Dictionary = _hail_visits[i] if i < _hail_visits.size() else {}
		var prompt := str(row.get("prompt", ""))
		var cue := _cue_of(prompt.substr(maxi(prompt.rfind("\n\n"), 0)))
		var said := str(row.get("say", ""))
		var echo := said.strip_edges().trim_suffix(".").to_lower() == cue.strip_edges().trim_suffix(".").to_lower()
		n += 1
		out += "| %d | %02d:00 | %s | %s | %s | %s | %s | %s | %s |\n" % [n, int(visit.get("hour", 0)), str(row.get("companion", "")), str(visit.get("player", "")),
			str(row.get("trigger", "")).trim_prefix("hail: ").get_slice(",", 0), cue.replace("|", "/"), said.replace("|", "/"), str(row.get("aside", "")).replace("|", "/"),
			"echo" if echo else ("" if str(row.get("outcome", "")) == "said" else str(row.get("outcome", "")))]
	out += "\n%d hails asked, %d answered.\n" % [_hail_visits.size(), rows.size()]

	DirAccess.make_dir_recursive_absolute(_review.get_base_dir())
	var file := FileAccess.open(_review, FileAccess.WRITE)
	if file != null:
		file.store_string(out)
		print("SOAK review written: %s (%d rows)" % [_review, n])
	else:
		print("SOAK review could not be written: %s" % _review)


## The counted soak's resident mind: every ask comes here.
class SoakMind:
	extends CompanionMind
	var soak: Node
	func voice(ask: Dictionary) -> Dictionary:
		return soak._soak_voice(ask)
