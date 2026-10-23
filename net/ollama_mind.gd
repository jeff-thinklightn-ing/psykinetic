class_name OllamaMind
extends CompanionMind
## A mind that asks Ollama's native chat endpoint (/api/chat): JSON-only
## output, reasoning off, the model kept loaded. A URL ending in
## /chat/completions is treated as an OpenAI-compatible endpoint instead,
## with that request and reply shape. Asynchronous: stance() and voice()
## start a request on their own channel and answer {} at once; the reply
## comes back through take_results(). One request in flight per channel,
## so a voice line being written never holds up a stance. Any error,
## timeout or parse failure comes back as a result with no answer: her
## stance stands. The tick is never blocked. Each result carries the
## prompt as sent, the raw reply and the latency, for the mind log. The
## prompts themselves are the companion's (Companion.STANCE_SYSTEM,
## stance_prompt, VOICE_SYSTEM, voice_prompt).

## A stance must come quickly (aim: under 300 ms) and is short; a line may
## take longer, in the background.
## Her card (CompanionCard) is written once, in the background: it may take long.
## What has become true of her (CompanionFacts) is read off a stretch of talk, in the background too.
const TIMEOUT_SECONDS := {"stance": 2.0, "voice": 5.0, "check": 2.0, "card": 60.0, "facts": 30.0}
const MAX_TOKENS := {"stance": 24, "voice": 90, "check": 12, "card": 320, "facts": 240}
## A stance wants the likeliest answer, the check the surest; a line wants
## some life.
const TEMPERATURE := {"stance": 0.2, "voice": 0.8, "check": 0.0, "card": 0.9, "facts": 0.2}
## More with --mind-why, for the reason after the answer.
const WHY_TOKENS := 40
## Loading a model cold takes the box half a minute; a warm-up may.
const WARM_TIMEOUT := 120.0

var url := ""
var model := ""
## True when the URL is an OpenAI-compatible endpoint (.../chat/completions)
## rather than Ollama's native /api/chat.
var openai_shaped := false
## Each channel's endpoint, model and shape: the voice's may be its own
## (--voice-url, --voice-model), the stance's and the check's are url, model.
var _urls: Dictionary[String, String] = {}
var _models: Dictionary[String, String] = {}
var _openai: Dictionary[String, bool] = {}
## What went wrong last time, for the console. "" when the last reply was fine.
var last_error := ""

## "stance" / "voice" -> its HTTPRequest, and the ask in flight on it ({} for none).
var _http: Dictionary[String, HTTPRequest] = {}
var _sent: Dictionary[String, Dictionary] = {}
var _stubbed_body := ""
## Requests come back, answered or not, not yet taken.
var _results: Array[Dictionary] = []
## The node the HTTPRequests hang under.
var _host: Node
## The warm-up asked of each endpoint and model, "url model" -> its
## HTTPRequest, while it is out.
var _warming: Dictionary[String, HTTPRequest] = {}
## Test hook: warm() only notes the bodies it would send.
var warm_sent: Array[Dictionary] = []
var stub_warm := false


## [param host] is a node to hang the HTTPRequests under.
## [param voice_endpoint], [param voice_model_name]: the voice's own ("" for
## the same).
func _init(endpoint: String, model_name: String, host: Node, voice_endpoint := "", voice_model_name := "") -> void:
	kind = "ollama"
	url = endpoint
	model = model_name
	openai_shaped = endpoint.trim_suffix("/").ends_with("/chat/completions")
	_host = host
	for what: String in ["stance", "voice", "check", "card", "facts"]:
		var own := what in ["voice", "card", "facts"]
		_urls[what] = voice_endpoint if own and not voice_endpoint.is_empty() else endpoint
		_models[what] = voice_model_name if own and not voice_model_name.is_empty() else model_name
		_openai[what] = _urls[what].trim_suffix("/").ends_with("/chat/completions")
	for what: String in ["stance", "voice", "check", "card", "facts"]:
		var http := HTTPRequest.new()
		http.timeout = TIMEOUT_SECONDS[what]
		http.request_completed.connect(_on_request_completed.bind(what))
		host.add_child(http)
		_http[what] = http
		_sent[what] = {}


func stance(ask: Dictionary) -> Dictionary:
	_send("stance", ask)
	return {}


func voice(ask: Dictionary) -> Dictionary:
	_send("voice", ask)
	return {}


func check(ask: Dictionary) -> Dictionary:
	_send("check", ask)
	return {}


func card(ask: Dictionary) -> Dictionary:
	_send("card", ask)
	return {}


func facts(ask: Dictionary) -> Dictionary:
	_send("facts", ask)
	return {}


## Asks each native endpoint to load its model and keep it (a chat with no
## messages, which Ollama answers once the model is in memory), on its own
## request with a long timeout, its reply unused: her first stance or line
## then finds the model loaded instead of timing out while it loads. An
## OpenAI-shaped endpoint has no such ask; nor is one sent while one to the
## same endpoint and model is still out.
func warm() -> void:
	for what: String in ["stance", "voice"]:
		if _openai[what]:
			continue
		var key := "%s %s" % [_urls[what], _models[what]]
		if _warming.has(key):
			continue
		var body := JSON.stringify({"model": _models[what], "messages": [], "keep_alive": -1})
		if stub_warm:
			warm_sent.append({"url": _urls[what], "body": JSON.parse_string(body)})
			_warming[key] = null
			continue
		var http := HTTPRequest.new()
		http.timeout = WARM_TIMEOUT
		_host.add_child(http)
		_warming[key] = http
		var at := Time.get_ticks_msec()
		http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			print("[mind] ollama: %s %s in %d ms" % [_models[what],
					"loaded" if result == HTTPRequest.RESULT_SUCCESS and code == 200 else "did not load (%d, HTTP %d)" % [result, code],
					Time.get_ticks_msec() - at])
			_warming.erase(key)
			http.queue_free())
		if http.request(_urls[what], PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body) != OK:
			_warming.erase(key)
			http.queue_free()


func busy(what: String) -> bool:
	return not _sent.get(what, {}).is_empty()


func _send(what: String, ask: Dictionary) -> void:
	if busy(what):
		return
	_sent[what] = {"ask": ask, "at": Time.get_ticks_msec()}
	if not _stubbed_body.is_empty():
		# Test hook: pretend the endpoint answered with this body at once.
		var body := _stubbed_body
		_stubbed_body = ""
		_on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body.to_utf8_buffer(), what)
		return
	var messages: Array = ask.get("messages", [
		{"role": "system", "content": str(ask.get("system", ""))},
		{"role": "user", "content": str(ask.get("user", ""))},
	])
	var error := _http[what].request(_urls[what], PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, request_messages(messages, what))
	if error != OK:
		_fail(what, "request not sent: %s" % error_string(error))


## The JSON body for the two messages. Reasoning is turned off ("think":
## false): there is no room for it. The native endpoint is also asked for
## JSON output, a short answer and to keep the model loaded.
func request_body(system: String, user: String, what := "stance") -> String:
	return request_messages([
		{"role": "system", "content": system},
		{"role": "user", "content": user},
	], what)


## The JSON body for [param messages]. A stance is asked for as JSON; the
## voice answers in plain words, so it is not.
func request_messages(messages: Array, what := "stance") -> String:
	var channel_model: String = _models.get(what, model)
	if _openai.get(what, openai_shaped):
		return JSON.stringify({
			"model": channel_model, "think": false, "stream": false, "temperature": TEMPERATURE.get(what, 0.5),
			"max_tokens": max_tokens(what), "messages": messages,
		})
	var body := {
		"model": channel_model, "think": false, "stream": false, "keep_alive": -1,
		"options": {"num_predict": max_tokens(what), "temperature": TEMPERATURE.get(what, 0.5)}, "messages": messages,
	}
	if what in ["stance", "check", "card", "facts"]:
		body["format"] = "json"
	return JSON.stringify(body)


static func max_tokens(what: String) -> int:
	return int(MAX_TOKENS.get(what, 64)) + (WHY_TOKENS if Net.mind_why and what == "stance" else 0)


## Her plain-words reply as {say, stance}, and do when it has one: an
## optional [STANCE: X] line and [DO: n] line (what she was offered to do)
## taken out, quotes and her own name off the front, "..." as silence.
static func parse_voice(content: String, speaker := "") -> Dictionary:
	var text := content
	var stance := ""
	# Brackets or not: the model drops them now and then.
	var tag := RegEx.create_from_string("(?i)\\[?\\s*\\bSTANCE\\s*:\\s*([A-Z_]+)\\s*\\]?")
	var found := tag.search(text)
	if found != null:
		stance = found.get_string(1).to_upper()
		text = tag.sub(text, "", true)
	var do_tag := RegEx.create_from_string("(?i)\\[?\\s*\\bDO\\s*:\\s*(\\d+)\\s*\\]?")
	var act := ""
	found = do_tag.search(text)
	if found != null:
		act = found.get_string(1)
		text = do_tag.sub(text, "", true)
	# Her player's words felt (decision 621): [HURT] or [SORRY].
	var felt := ""
	var felt_tag := RegEx.create_from_string("(?i)\\[\\s*(HURT|SORRY)\\s*\\]")
	found = felt_tag.search(text)
	if found != null:
		felt = found.get_string(1).to_lower()
		text = felt_tag.sub(text, "", true)
	text = text.strip_edges()
	if not speaker.is_empty() and text.begins_with(speaker + ":"):
		text = text.substr(speaker.length() + 1).strip_edges()
	if text.length() >= 2 and text.begins_with("\"") and text.ends_with("\""):
		text = text.substr(1, text.length() - 2).strip_edges()
	if text.replace(".", "").replace("…", "").strip_edges().is_empty():
		text = ""
	var out := {"say": text, "stance": stance}
	if not act.is_empty():
		out["do"] = act
	if not felt.is_empty():
		out["felt"] = felt
	return out


## Requests that came back since last asked (see CompanionMind).
func take_results() -> Array[Dictionary]:
	var results := _results
	_results = []
	return results


func _result(what: String, raw: String, answer: Dictionary, error: String) -> void:
	var sent: Dictionary = _sent.get(what, {})
	var ask: Dictionary = sent.get("ask", {})
	_sent[what] = {}
	_results.append({"kind": what, "serial": ask.get("serial", 0), "trigger": ask.get("trigger", ""),
		"prompt": Companion.render(ask["messages"]) if ask.has("messages") else "%s\n\n%s" % [ask.get("system", ""), ask.get("user", "")],
		"raw": raw, "answer": answer,
		"error": error, "latency_ms": Time.get_ticks_msec() - int(sent.get("at", Time.get_ticks_msec())),
		"spoken_to": ask.get("spoken_to", false), "asked": ask.get("asked", false), "always": ask.get("always", false),
		"heard": ask.get("heard", "")})


## Test hook: the next ask gets this as the endpoint's response body.
func stub_next_reply(body: String) -> void:
	_stubbed_body = body


func _on_request_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, what: String) -> void:
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(what, "timed out" if result == HTTPRequest.RESULT_TIMEOUT else "request failed (%d)" % result, text)
		return
	if code != 200:
		_fail(what, "HTTP %d" % code, text)
		return
	var response: Variant = _parse(text)
	var content := _openai_content_of(response) if _openai.get(what, openai_shaped) else _native_content_of(response)
	if content.is_empty():
		_fail(what, "no message content in the response", text)
		return
	if what == "voice":
		last_error = ""
		_result(what, content, parse_voice(strip_think(content), str(_sent[what].get("ask", {}).get("speaker", ""))), "")
		return
	var answer: Variant = _parse(_strip_fences(strip_think(content)))
	if answer == null and what == "stance":
		# Cut off after the stance (in the reason, say): the stance stands.
		var found := RegEx.create_from_string("\"stance\"\\s*:\\s*\"([A-Z_]+)\"").search(content)
		if found != null:
			answer = {"stance": found.get_string(1)}
	var needs: String = {"stance": "stance", "check": "asked", "card": "card", "facts": "facts"}.get(what, "say")
	if answer is not Dictionary or not answer.has(needs):
		_fail(what, "reply is not a JSON object with a %s: %s" % [needs, content.left(80)], content)
		return
	last_error = ""
	_result(what, content, answer, "")


## message.content of an Ollama /api/chat response, or "".
static func _native_content_of(response: Variant) -> String:
	if response is not Dictionary:
		return ""
	var message: Variant = response.get("message", {})
	if message is not Dictionary:
		return ""
	return str(message.get("content", ""))


## choices[0].message.content of an OpenAI-style response, or "".
static func _openai_content_of(response: Variant) -> String:
	if response is not Dictionary:
		return ""
	var choices: Variant = response.get("choices", [])
	if choices is not Array or choices.is_empty() or choices[0] is not Dictionary:
		return ""
	var message: Variant = choices[0].get("message", {})
	if message is not Dictionary:
		return ""
	return str(message.get("content", ""))


## JSON text as a Variant, or null; unlike JSON.parse_string it does not
## print an engine error for bad input, which is expected here.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## [param text] without any reasoning a model left in despite "think": false.
## Whole <think>...</think> blocks go; so does everything up to a stray
## closing tag (some models emit only that) and everything from an opening
## tag that never closes.
static func strip_think(text: String) -> String:
	var blocks := RegEx.create_from_string("(?is)<think>.*?</think>")
	var stripped := blocks.sub(text, "", true)
	var closing := stripped.rfindn("</think>")
	if closing != -1:
		stripped = stripped.substr(closing + "</think>".length())
	var opening := stripped.findn("<think>")
	if opening != -1:
		stripped = stripped.substr(0, opening)
	return stripped.strip_edges()


static func _strip_fences(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.begins_with("```"):
		trimmed = trimmed.trim_prefix("```json").trim_prefix("```").trim_suffix("```").strip_edges()
	return trimmed


func _fail(what: String, why: String, raw := "") -> void:
	last_error = why
	print("[mind] ollama (%s): %s" % [what, why])
	_result(what, raw, {}, why)
