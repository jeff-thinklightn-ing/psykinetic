extends Node
## The perception A/B eval: how well her voice answers questions about
## what is around her with each --perception mode (list, grid, both),
## asked of a real model. Not part of tests/run: it needs the model, and it
## measures rather than passes. Run it with tools/perception_eval.ps1, or:
##
##   godot --headless --path . --scene tests/perception_eval.tscn -- \
##       --llm-url=http://127.0.0.1:11434/api/chat --llm-model=qwen3:14b \
##       [--eval-runs=5] [--eval-modes=list,grid,both] [--eval-scenes=a,b] \
##       [--eval-out=build/perception_eval] [--eval-preview]
##
## Eight fixed scenes, on the test room and the sample level: Wren, Jeff,
## monsters, doors open or shut. In each, four questions are asked as Jeff
## ("What's next to you?", "Where's the fire?", "Is the door open?", "Is
## anything near me?"), each with the voice's real ask (voice_messages,
## Jeff having just spoken) and the real request body (OllamaMind), every
## scene x mode x question --eval-runs times. The answers are scored by
## keyword against the truth, worked out from the sim, not written by hand
## (truth_of): what she can see, by the same line of sight her prompt uses.
## Prompt tokens are counted once per scene and mode, for the voice's ask
## and the stance's, with a nonce in front so no cached prefix hides any.
##
## --eval-preview prints each scene's grid, list and truth, and asks
## nothing. Results go to <out>.jsonl (every answer) and <out>.md (the
## report), and the report to stdout.

const QUESTIONS := {
	"next_to_you": "What's next to you?",
	"fire": "Where's the fire?",
	"door": "Is the door open?",
	"near_me": "Is anything near me?",
}
const MODES: Array[String] = ["list", "grid", "both"]
## Generous: the eval measures latency, it does not enforce the game's.
const TIMEOUT_SECONDS := 60.0
## The game's own voice timeout, to count answers that would have been lost.
const GAME_TIMEOUT_MS := 5000

## Each scene: map, Wren's tile and facing, Jeff's tile, monsters
## ([kind, tile]), doors to set ([one side, other side, open]).
const SCENES: Array[Dictionary] = [
	{"id": "fire_imp", "map": "test_room", "wren": Vector2i(7, 7), "facing": Vector2i(0, -1), "jeff": Vector2i(9, 7),
		"monsters": [["imp", Vector2i(8, 6)]], "doors": []},
	{"id": "crates", "map": "test_room", "wren": Vector2i(7, 3), "facing": Vector2i(1, 0), "jeff": Vector2i(10, 4),
		"monsters": [["imp", Vector2i(11, 5)]], "doors": []},
	{"id": "door_shut", "map": "test_room", "wren": Vector2i(4, 11), "facing": Vector2i(0, 1), "jeff": Vector2i(6, 12),
		"monsters": [["imp", Vector2i(5, 11)], ["brute", Vector2i(4, 14)]], "doors": [[Vector2i(4, 12), Vector2i(4, 13), false]]},
	{"id": "door_open", "map": "test_room", "wren": Vector2i(3, 11), "facing": Vector2i(1, 0), "jeff": Vector2i(4, 12),
		"monsters": [["brute", Vector2i(4, 14)]], "doors": [[Vector2i(4, 12), Vector2i(4, 13), true]]},
	{"id": "ledge_sneak", "map": "sample", "wren": Vector2i(10, 9), "facing": Vector2i(-1, 0), "jeff": Vector2i(5, 7),
		"monsters": [["sneak", Vector2i(6, 6)], ["brute", Vector2i(12, 9)]], "doors": [[Vector2i(11, 4), Vector2i(11, 5), false]]},
	{"id": "door_north", "map": "sample", "wren": Vector2i(10, 6), "facing": Vector2i(0, -1), "jeff": Vector2i(11, 5),
		"monsters": [["imp", Vector2i(12, 6)]], "doors": [[Vector2i(11, 4), Vector2i(11, 5), false]]},
	{"id": "past_the_door", "map": "sample", "wren": Vector2i(10, 3), "facing": Vector2i(0, -1), "jeff": Vector2i(9, 3),
		"monsters": [["imp", Vector2i(11, 6)]], "doors": [[Vector2i(11, 4), Vector2i(11, 5), true]]},
	{"id": "water_cart", "map": "sample", "wren": Vector2i(4, 5), "facing": Vector2i(0, 1), "jeff": Vector2i(2, 4),
		"monsters": [["brute", Vector2i(1, 6)], ["imp", Vector2i(6, 9)]], "doors": []},
]

const NUMBER_WORDS: Array[String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
	"ten", "eleven", "twelve"]
const SYNONYMS := {
	"imp": ["imp"], "brute": ["brute"], "sneak": ["sneak"], "monster": ["monster"],
	"crate": ["crate", "box"], "boulder": ["boulder"], "cart": ["cart"],
	"fire": ["fire", "flame", "burn"], "water": ["water", "pool", "lake"], "door": ["door"],
}
const NOTHING := "\\b(nothing|no ?one|nobody|none|not a thing|all clear|clear|just (you|us)|only (you|us)|empty)\\b|^\\W*no\\b"
const UNSEEN := "\\b(don'?t|can'?t|cannot|do not|not) (see|spot|know)|\\bno (sign of|fire|door)|\\bnone\\b|\\bwhich door|\\bwhat door|\\bnot (here|near|close)"
## What "next to you" may wrongly claim: any of these not next to her.
const THINGS: Array[String] = ["imp", "brute", "sneak", "crate", "boulder", "cart", "fire", "water"]
const NEGATED := "\\b(no|not|nothing|never|without)\\b|n'?t\\b"
const CLOSED := "\\b(closed|shut|not open|isn'?t open|locked|barred)\\b"

var _main: Node
var _mind: OllamaMind
var _http: HTTPRequest
var _runs := 5
var _modes: Array[String] = MODES.duplicate()
var _only: Array[String] = []
var _out := "build/perception_eval"
var _preview := false
var _nonce := 0


func _ready() -> void:
	World.set_process(false)
	Net.port = 17789
	Net.player_name = "Jeff"
	Net.transcripts_dir = ""
	Net.mind_log_path = ""
	_read_args()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	add_child(_http)
	if not _preview and Net.llm_model.is_empty():
		print("perception_eval: name the model with --llm-model= (and --llm-url=), or use --eval-preview")
		get_tree().quit(2)
		return
	_mind = OllamaMind.new(Net.llm_url, Net.llm_model, self)
	await _run()
	get_tree().quit(0)


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		var parts := arg.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--eval-runs":
				_runs = maxi(value.to_int(), 1)
			"--eval-modes":
				_modes.clear()
				for mode in value.split(","):
					if mode in MODES:
						_modes.append(mode)
			"--eval-scenes":
				_only.assign(value.split(","))
			"--eval-out":
				_out = value
			"--eval-preview":
				_preview = true


func _run() -> void:
	var records: Array[Dictionary] = []
	var tokens: Array[Dictionary] = []
	var log_file: FileAccess = null
	if not _preview:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out.get_base_dir()))
		log_file = FileAccess.open(_path(_out + ".jsonl"), FileAccess.WRITE)
		print("perception_eval: %s at %s, modes %s, %d run(s) each" % [Net.llm_model, Net.llm_url, _modes, _runs])
	for scene in SCENES:
		if not _only.is_empty() and scene["id"] not in _only:
			continue
		await _set_up(scene)
		var pet := _companion()
		var truth := truth_of(pet)
		if _preview:
			_print_preview(scene, pet, truth)
			continue
		for mode in _modes:
			Net.perception = mode
			# Sized as asked: the list tells what Jeff asked about.
			pet._exchange.clear()
			pet._add_turn("user", QUESTIONS["next_to_you"])
			tokens.append({"scene": scene["id"], "mode": mode,
				"voice": await _count_tokens(pet.voice_messages(true)),
				"stance": await _count_tokens([
					{"role": "system", "content": Companion.STANCE_SYSTEM % ""},
					{"role": "user", "content": pet.stance_prompt()}])})
			for run in _runs:
				for question: String in QUESTIONS:
					pet._exchange.clear()
					pet._add_turn("user", QUESTIONS[question])
					var reply := await _ask(pet.voice_messages(true))
					var say := str(OllamaMind.parse_voice(OllamaMind.strip_think(reply["content"]), "Wren")["say"])
					var verdict := score(question, say, truth[question])
					var record := {"scene": scene["id"], "mode": mode, "run": run + 1, "question": question,
						"say": say, "raw": reply["content"], "pass": verdict["pass"], "why": verdict["why"], "latency_ms": reply["latency_ms"],
						"prompt_eval_count": reply["prompt_eval_count"], "error": reply["error"]}
					records.append(record)
					log_file.store_line(JSON.stringify(record))
					print("  %-13s %-4s %d %-11s %s  %s" % [scene["id"], mode, run + 1, question,
						"PASS" if verdict["pass"] else "FAIL", say.replace("\n", " ").left(110)])
	Net.perception = "list"
	if _preview:
		return
	log_file.close()
	var report := _report(records, tokens)
	print("\n" + report)
	var file := FileAccess.open(_path(_out + ".md"), FileAccess.WRITE)
	file.store_string(report)
	file.close()


static func _path(relative: String) -> String:
	return relative if relative.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(relative)


# --- Scenes -------------------------------------------------------------------

func _set_up(scene: Dictionary) -> void:
	if _main.map_name != _level_name(scene["map"]):
		_main.load_map(scene["map"])
		await get_tree().process_frame
		await get_tree().process_frame
	for entity in World.get_entities():
		if entity is Monster:
			World.despawn(entity)
			entity.queue_free()
	await get_tree().process_frame
	var jeff := _player()
	var pet := _companion()
	jeff.label = "Jeff"
	pet.name = "Wren"
	pet.label = ""
	pet.card = Main.companion_card("Wren")
	pet.hp = pet.max_hp
	jeff.hp = jeff.max_hp
	pet.stance = Companion.Stance.GUARD
	pet.current_intent = Companion.Intent.FOLLOW
	pet.intent_target = null
	pet._instruction = ""
	_place(pet, scene["wren"])
	_place(jeff, scene["jeff"])
	pet.facing = scene["facing"]
	for monster: Array in scene["monsters"]:
		var spawned: GridEntity = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "kind": monster[0],
			"name": "%s_%d_%d" % [str(monster[0]).capitalize(), monster[1].x, monster[1].y], "tile": monster[1]})
		if spawned == null:
			push_error("%s: no room for a %s at %s" % [scene["id"], monster[0], monster[1]])
	for door_spec: Array in scene["doors"]:
		var a: Vector2i = door_spec[0]
		var door := World.door_across(a, door_spec[1] - a)
		if door == null:
			push_error("%s: no door between %s and %s" % [scene["id"], a, door_spec[1]])
			continue
		World._set_door(door, door_spec[2], jeff)
	if pet.tile != scene["wren"] or jeff.tile != scene["jeff"]:
		push_error("%s: Wren at %s, Jeff at %s" % [scene["id"], pet.tile, jeff.tile])


func _level_name(map: String) -> String:
	return str(Level.load_level(map)["name"])


func _place(entity: GridEntity, tile: Vector2i) -> void:
	if entity.tile == tile:
		return
	var occupant := World.get_entity_at(tile)
	if occupant != null:
		World._relocate(occupant, _main._nearest_free(tile + Vector2i(0, 3)))
	World._relocate(entity, tile)
	if entity is Player:
		entity.queued_steps.clear()
		entity.has_move_order = false


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


# --- Truth and scoring --------------------------------------------------------

## What is so in [param pet]'s scene, for each question, from what she can
## see (Companion._sees, the prompt's own line of sight), within
## PERCEPTION_RANGE:
##   next_to_you  {kinds}: the THINGS next to her (Jeff, walls, ledges,
##                stairs and doors may be said or not)
##   fire         {seen, paces, words}: the nearest fire, and the words that
##                place it (paces, compass, her bearing, its relations)
##   door         {seen, open}: the nearest door
##   near_me      {kinds, hazards}: monsters within 2 paces of Jeff, and
##                fire within 2 (what counts when there is no monster)
static func truth_of(pet: Companion) -> Dictionary:
	var next_to: Array[String] = []
	var near_jeff: Array[String] = []
	var hazards: Array[String] = []
	var fire := {"seen": false}
	for cell in pet._cells_within(Companion.PERCEPTION_RANGE):
		if not pet._sees(cell):
			continue
		var adjacent := cell != pet.tile and World.distance(pet.tile, cell) == 1
		if World.is_fire(cell) and not fire["seen"]:
			fire = {"seen": true, "paces": World.distance(pet.tile, cell), "words": _placing(pet, cell)}
		var kinds: Array[String] = []
		if World.is_fire(cell):
			kinds.append("fire")
			if World.distance(pet.keeper.tile, cell) <= 2 and "fire" not in hazards:
				hazards.append("fire")
		if World.is_water(cell):
			kinds.append("water")
		var entity := World.get_entity_at(cell)
		if entity is Monster and entity.spawned:
			kinds.append(Companion.kind_of(entity))
			if World.distance(pet.keeper.tile, cell) <= 2:
				near_jeff.append(Companion.kind_of(entity))
		elif entity != null and entity.pushable:
			kinds.append(Companion.object_word(entity))
		if adjacent:
			for kind in kinds:
				if kind not in next_to:
					next_to.append(kind)
	var door := {"seen": false}
	var nearest := 1000
	for one: Door in World.get_doors():
		var sides := Terrain.edge_cells(one.key)
		var paces := mini(World.distance(pet.tile, sides[0]), World.distance(pet.tile, sides[1]))
		if paces <= Companion.PERCEPTION_RANGE and paces < nearest and (pet._sees(sides[0]) or pet._sees(sides[1])):
			nearest = paces
			door = {"seen": true, "open": one.is_open()}
	return {"next_to_you": {"kinds": next_to}, "fire": fire, "door": door,
		"near_me": {"kinds": near_jeff, "hazards": hazards}}


## Each way of placing [param cell] that is right, as a regex: its compass
## direction from her, her bearing as she faces, its relations to her and
## Jeff.
static func _placing(pet: Companion, cell: Vector2i) -> Array[String]:
	var words: Array[String] = []
	var offset := cell - pet.tile
	if offset == Vector2i.ZERO:
		return ["\\b(under|beneath|where (i|you) stand|standing in|in it|in the fire|i'?m in|on fire|burning me)"]
	# Its compass point; for a diagonal, both halves together, or the half
	# that is most of it alone ("north" for two north and one east).
	var vertical := "north" if offset.y < 0 else "south" if offset.y > 0 else ""
	var across := "east" if offset.x > 0 else "west" if offset.x < 0 else ""
	if vertical.is_empty() or across.is_empty():
		words.append("\\b" + vertical + across)
	else:
		words.append("\\b%s[- ]?%s" % [vertical, across])
		if absi(offset.y) > absi(offset.x):
			words.append("\\b%s\\b(?![- ]?(east|west))" % vertical)
		elif absi(offset.x) > absi(offset.y):
			words.append("(?<!north|south)(?<!north-|south-)\\b%s" % across)
	var bearing := pet._direction(Vector2(cell))
	var parts: Array[String] = []
	for key: String in ["ahead", "behind", "left", "right"]:
		if key in bearing:
			parts.append({"ahead": "(ahead|in front|before)", "behind": "(behind|back)", "left": "left", "right": "right"}[key])
	words.append("(?s)" + "".join(parts.map(func(p: String) -> String: return "(?=.*\\b%s)" % p)))
	for relation in pet.relations_of(cell, Vector2(cell)):
		match relation.get_slice(" ", 0):
			"adjacent":
				words.append("\\b(next to|beside|by) (me|you)\\b|\\bright here\\b")
			"between":
				words.append("\\bbetween\\b")
			"behind":
				words.append("\\bbehind (you|jeff)\\b")
			"next":
				words.append("\\b(next to|beside|near|by) (you|jeff)\\b")
			"on":
				words.append("\\b(above|up on|higher)\\b")
			"below":
				words.append("\\b(below|down)\\b")
	return words


## Whether [param say] answers [param question] right, by keyword:
## {pass, why}.
static func score(question: String, say: String, truth: Dictionary) -> Dictionary:
	var text := say.to_lower()
	if text.is_empty():
		return {"pass": false, "why": "silence"}
	match question:
		"next_to_you":
			var kinds: Array = truth["kinds"]
			var missing: Array[String] = []
			var wrong: Array[String] = []
			for kind: String in THINGS:
				if kind in kinds and not _mentions(text, kind):
					missing.append(kind)
				elif kind not in kinds and _claims(text, kind):
					wrong.append(kind)
			return {"pass": missing.is_empty() and wrong.is_empty(),
				"why": "wanted %s; missing %s; not next to her %s" % [kinds, missing, wrong]}
		"near_me":
			var kinds: Array = truth["kinds"] if not truth["kinds"].is_empty() else truth["hazards"]
			if kinds.is_empty():
				return {"pass": _has(text, NOTHING), "why": "wanted: nothing"}
			var missing: Array[String] = []
			for kind: String in kinds:
				if not _mentions(text, kind):
					missing.append(kind)
			return {"pass": missing.is_empty(), "why": "wanted %s; missing %s" % [kinds, missing]}
		"fire":
			if not truth["seen"]:
				return {"pass": _has(text, UNSEEN), "why": "wanted: none seen"}
			if _has(text, UNSEEN):
				return {"pass": false, "why": "said she cannot see it"}
			var placed := _number_near(text, int(truth["paces"]))
			for words: String in truth["words"]:
				placed = placed or _has(text, words)
			return {"pass": placed, "why": "wanted %d paces or one of %s" % [truth["paces"], truth["words"]]}
		"door":
			if not truth["seen"]:
				return {"pass": _has(text, UNSEEN), "why": "wanted: none seen"}
			# A bare "Yes." or "No." answers the question as asked.
			var closed := _has(text, CLOSED) or _has(text, "^\\W*no\\b")
			if truth["open"]:
				return {"pass": (_has(text, "\\bopen\\b") or _has(text, "^\\W*yes\\b")) and not closed, "why": "wanted: open"}
			return {"pass": closed, "why": "wanted: closed"}
	return {"pass": false, "why": "unknown question"}


static func _mentions(text: String, kind: String) -> bool:
	for word: String in SYNONYMS.get(kind, [kind]):
		if _has(text, "\\b%s" % word):
			return true
	return false


## Whether [param text] says [param kind] is there: mentioned, and not
## after a "no" or "not" earlier in the same sentence.
static func _claims(text: String, kind: String) -> bool:
	for word: String in SYNONYMS.get(kind, [kind]):
		for found in RegEx.create_from_string("\\b%s" % word).search_all(text):
			var before := text.left(found.get_start())
			before = before.substr(maxi(maxi(before.rfind("."), before.rfind("!")), before.rfind("?")) + 1)
			if not _has(before, NEGATED):
				return true
	return false


static func _has(text: String, pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null


## Whether [param text] gives a number of paces within one of [param paces].
static func _number_near(text: String, paces: int) -> bool:
	for found in RegEx.create_from_string("\\b(\\d+|%s)\\b" % "|".join(NUMBER_WORDS)).search_all(text):
		var word := found.get_string(1)
		var number := word.to_int() if word.is_valid_int() else NUMBER_WORDS.find(word)
		if absi(number - paces) <= 1:
			return true
	return false


# --- The model ----------------------------------------------------------------

## The voice's request, as the game sends it: {content, latency_ms,
## prompt_eval_count, error}.
func _ask(messages: Array) -> Dictionary:
	var started := Time.get_ticks_msec()
	var body := _mind.request_messages(messages, "voice")
	var error := _http.request(_mind.url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if error != OK:
		return {"content": "", "latency_ms": 0, "prompt_eval_count": 0, "error": error_string(error)}
	var result: Array = await _http.request_completed
	var latency := Time.get_ticks_msec() - started
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	var response: Variant = JSON.parse_string(text) if result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200 else null
	if response is not Dictionary:
		return {"content": "", "latency_ms": latency, "prompt_eval_count": 0,
			"error": "result %d, HTTP %d: %s" % [result[0], result[1], text.left(120)]}
	var content := OllamaMind._openai_content_of(response) if _mind.openai_shaped else OllamaMind._native_content_of(response)
	var counted := int(response.get("prompt_eval_count", response.get("usage", {}).get("prompt_tokens", 0)))
	return {"content": content, "latency_ms": latency, "prompt_eval_count": counted, "error": ""}


## The prompt's size in tokens, chat template included: asked with a
## nonce first so nothing of it is cached, and one token wanted back. The
## nonce's own tokens are taken off (counted with an empty ask the same way).
func _count_tokens(messages: Array) -> int:
	var whole := await _counted(messages)
	var empty := await _counted([{"role": "system", "content": ""}, {"role": "user", "content": ""}])
	return whole - empty


func _counted(messages: Array) -> int:
	_nonce += 1
	var sent: Array = messages.duplicate(true)
	sent[0]["content"] = "%07d\n%s" % [Time.get_ticks_usec() % 10000000, sent[0]["content"]]
	var body: Dictionary = JSON.parse_string(_mind.request_messages(sent, "voice"))
	if body.has("options"):
		body["options"]["num_predict"] = 1
	else:
		body["max_tokens"] = 1
	_http.request(_mind.url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	var result: Array = await _http.request_completed
	var response: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if response is not Dictionary:
		return 0
	return int(response.get("prompt_eval_count", response.get("usage", {}).get("prompt_tokens", 0)))


# --- Report -------------------------------------------------------------------

func _report(records: Array[Dictionary], tokens: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	lines.append("# Perception eval: %s" % Net.llm_model)
	lines.append("")
	lines.append("%s; %d scene(s), %d run(s) of each question per scene and mode; %d answers." % [
		Time.get_datetime_string_from_system(false, true), tokens.size() / maxi(_modes.size(), 1), _runs, records.size()])
	lines.append("")
	var header := "| | " + " | ".join(_modes) + " |"
	var rule := "|---|" + "---|".repeat(_modes.size())
	lines.append("## Accuracy")
	lines.append("")
	lines.append(header)
	lines.append(rule)
	var rows: Array = [["all", ""]]
	for question: String in QUESTIONS:
		rows.append([QUESTIONS[question], question])
	for row: Array in rows:
		var cells: Array[String] = []
		for mode in _modes:
			var hits := 0
			var total := 0
			for record in records:
				if record["mode"] == mode and (row[1] == "" or record["question"] == row[1]):
					total += 1
					hits += 1 if record["pass"] else 0
			cells.append("%d%% (%d/%d)" % [roundi(100.0 * hits / maxi(total, 1)), hits, total])
		lines.append("| %s | %s |" % [row[0], " | ".join(cells)])
	lines.append("")
	lines.append("## Latency and size")
	lines.append("")
	lines.append(header)
	lines.append(rule)
	var latency: Array[String] = []
	var slow: Array[String] = []
	var voice_tokens: Array[String] = []
	var stance_tokens: Array[String] = []
	var errors: Array[String] = []
	for mode in _modes:
		var sum := 0
		var count := 0
		var over := 0
		var failed := 0
		for record in records:
			if record["mode"] == mode:
				if not str(record["error"]).is_empty():
					failed += 1
					continue
				sum += int(record["latency_ms"])
				count += 1
				over += 1 if int(record["latency_ms"]) > GAME_TIMEOUT_MS else 0
		latency.append("%d ms" % roundi(float(sum) / maxi(count, 1)))
		slow.append("%d" % over)
		errors.append("%d" % failed)
		var voice := 0
		var stance := 0
		var scenes := 0
		for entry in tokens:
			if entry["mode"] == mode:
				voice += int(entry["voice"])
				stance += int(entry["stance"])
				scenes += 1
		voice_tokens.append("%d" % roundi(float(voice) / maxi(scenes, 1)))
		stance_tokens.append("%d" % roundi(float(stance) / maxi(scenes, 1)))
	lines.append("| average latency (voice) | %s |" % " | ".join(latency))
	lines.append("| over the game's %d s voice timeout | %s |" % [GAME_TIMEOUT_MS / 1000, " | ".join(slow)])
	lines.append("| errors | %s |" % " | ".join(errors))
	lines.append("| prompt tokens, voice (mean of scenes) | %s |" % " | ".join(voice_tokens))
	lines.append("| prompt tokens, stance (mean of scenes) | %s |" % " | ".join(stance_tokens))
	lines.append("")
	lines.append("## By scene")
	lines.append("")
	lines.append(header)
	lines.append(rule)
	for scene in SCENES:
		var cells: Array[String] = []
		for mode in _modes:
			var hits := 0
			var total := 0
			for record in records:
				if record["scene"] == scene["id"] and record["mode"] == mode:
					total += 1
					hits += 1 if record["pass"] else 0
			cells.append("%d/%d" % [hits, total])
		if cells.any(func(c: String) -> bool: return not c.ends_with("/0")):
			lines.append("| %s | %s |" % [scene["id"], " | ".join(cells)])
	return "\n".join(lines) + "\n"


func _print_preview(scene: Dictionary, pet: Companion, truth: Dictionary) -> void:
	print("\n=== %s (%s): Wren %s facing %s, Jeff %s" % [scene["id"], scene["map"], pet.tile, pet.facing, pet.keeper.tile])
	print(pet.perception_grid())
	print(pet.perception_list())
	var heights: Array[String] = []
	for y in range(pet.tile.y - 3, pet.tile.y + 4):
		var row := ""
		for x in range(pet.tile.x - 6, pet.tile.x + 7):
			row += str(World.height_at(Vector2i(x, y))) if World.is_walkable(Vector2i(x, y)) else " "
		heights.append(row)
	print("heights (rows %d..%d):
%s" % [pet.tile.y - 3, pet.tile.y + 3, "
".join(heights)])
	print("truth: %s" % JSON.stringify(truth))
