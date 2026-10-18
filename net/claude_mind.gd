class_name ClaudeMind
extends CompanionMind
## A companion's voice on the Claude API (decision 363, an experiment):
## wraps her own mind ([member inner], the box's model or the scripted one)
## and sends only her voice asks to Anthropic's Messages API, the same
## prompt, length and parse (OllamaMind.parse_voice); her stance, checks,
## card and facts stay with [member inner], so a comparison is of the voice
## alone. Off by default and per companion: the server console's `mind
## claude` wraps one, for this session only (never saved, never
## replicated). The key comes from ANTHROPIC_API_KEY in the environment of
## the process that runs the companions, is held here alone and goes out
## only as a request header: never printed, logged or saved.
##
## Any failure falls back to [member inner] with the same ask (logged as
## "fallback" with why): no key, a timeout, HTTP 401/403 (and she is
## switched off for the session, so a bad key is not tried again), 429 or
## 5xx (overloaded), an empty reply, or the session's budget spent
## (CALL_BUDGET calls or COST_BUDGET dollars, whichever comes first).

const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
const MODELS := {"haiku": "claude-haiku-5-5", "sonnet": "claude-sonnet-5-5"}
## Dollars per million tokens, [input, output]: Anthropic's prices
## (platform.claude.com/docs/en/about-claude/pricing, 2026-10-17; Haiku's
## for prompts under 100K tokens, which hers are).
const PRICES := {"claude-haiku-5-5": [0.10, 0.50], "claude-sonnet-5-5": [2.0, 10.0]}
## The session's budget across every companion on Claude: past either,
## every voice ask goes to her own mind.
const CALL_BUDGET := 200
const COST_BUDGET := 1.0

## What the whole session has spent on Claude (the console's `mind claude`).
static var calls := 0
static var tokens_in := 0
static var tokens_out := 0
static var cost := 0.0

## Her own mind: everything but the voice, and the voice when this fails.
var inner: CompanionMind
## The model id (MODELS' values).
var model := ""
## Switched off for the session by a 401/403: every ask goes to [member inner].
var off := false
var last_error := ""
var _key := ""
var _http: HTTPRequest
## The voice ask out ({} for none): {ask, at}.
var _sent: Dictionary = {}
var _results: Array[Dictionary] = []
## Serials sent to [member inner] instead -> why, noted on their results.
var _fallen: Dictionary[int, String] = {}
## Test hook: replies given in turn instead of a request, each
## {result (HTTPRequest's), code, body}.
var stubbed: Array[Dictionary] = []


## [param wrapped] her own mind; [param model_id] one of MODELS' values;
## [param host] a node to hang the request under; [param key] the API key
## (ANTHROPIC_API_KEY's when not given: tests give a fake one).
func _init(wrapped: CompanionMind, model_id: String, host: Node, key: Variant = null) -> void:
	inner = wrapped
	model = model_id
	kind = "claude:" + model_id.trim_prefix("claude-") + "+" + (wrapped.kind if wrapped != null else "none")
	_key = OS.get_environment("ANTHROPIC_API_KEY") if key == null else str(key)
	if host != null:
		_http = HTTPRequest.new()
		_http.timeout = OllamaMind.TIMEOUT_SECONDS["voice"]
		_http.request_completed.connect(_on_request_completed)
		host.add_child(_http)


## Whether a key is set in this process's environment (without reading it out).
static func has_key() -> bool:
	return not OS.get_environment("ANTHROPIC_API_KEY").is_empty()


## Whether the session's budget is spent.
static func spent() -> bool:
	return calls >= CALL_BUDGET or cost >= COST_BUDGET


## The session's spend, in words, for the console.
static func spend_words() -> String:
	return "%d calls, %d tokens in, %d out, about $%.4f (budget %d calls or $%.2f)" % [calls, tokens_in, tokens_out, cost, CALL_BUDGET, COST_BUDGET]


## What [param input] and [param output] tokens of [param model_id] cost, in dollars.
static func cost_of(model_id: String, input: int, output: int) -> float:
	var price: Array = PRICES.get(model_id, [0.0, 0.0])
	return (input * float(price[0]) + output * float(price[1])) / 1000000.0


## One call's spend added to the session's (calls, tokens, cost): this
## mind's and anything else sent on the same key (npc's lawspeaker rulings
## through ClaudeClient), so one budget caps them all; spent() is checked
## before sending. That call's cost, in dollars.
static func note_spend(model_id: String, input: int, output: int) -> float:
	var spent_now := cost_of(model_id, input, output)
	calls += 1
	tokens_in += input
	tokens_out += output
	cost += spent_now
	return spent_now


## Unwrapped: its request node goes.
func close() -> void:
	if _http != null:
		_http.queue_free()
		_http = null


func stance(ask: Dictionary) -> Dictionary:
	return inner.stance(ask)


func check(ask: Dictionary) -> Dictionary:
	return inner.check(ask)


func card(ask: Dictionary) -> Dictionary:
	return inner.card(ask)


func facts(ask: Dictionary) -> Dictionary:
	return inner.facts(ask)


func warm() -> void:
	inner.warm()


func busy(what: String) -> bool:
	if what == "voice":
		return not _sent.is_empty() or inner.busy("voice")
	return inner.busy(what)


func voice(ask: Dictionary) -> Dictionary:
	if busy("voice"):
		return {}
	var why := "switched off after the key was refused" if off else "no ANTHROPIC_API_KEY" if _key.is_empty() \
		else "the session's budget is spent" if spent() else ""
	if not why.is_empty():
		return _fall_back(ask, why)
	_sent = {"ask": ask, "at": Time.get_ticks_msec()}
	if not stubbed.is_empty():
		var reply: Dictionary = stubbed.pop_front()
		_on_request_completed(int(reply.get("result", HTTPRequest.RESULT_SUCCESS)), int(reply.get("code", 200)),
			PackedStringArray(), str(reply.get("body", "")).to_utf8_buffer())
		return {}
	if _http == null:
		_fail("no node to send from")
		return {}
	var error := _http.request(URL, PackedStringArray(["content-type: application/json", "anthropic-version: " + API_VERSION,
		"x-api-key: " + _key]), HTTPClient.METHOD_POST, request_body(ask))
	if error != OK:
		_fail("request not sent: %s" % error_string(error))
	return {}


## The Messages API body for [param ask]: her system prompt as system,
## the rest as turns (a run of one role joined, the first a user's), as
## long and as warm as her own mind's voice.
func request_body(ask: Dictionary) -> String:
	var messages: Array = ask.get("messages", [
		{"role": "system", "content": str(ask.get("system", ""))},
		{"role": "user", "content": str(ask.get("user", ""))},
	])
	var system: Array[String] = []
	var turns: Array[Dictionary] = []
	for message: Dictionary in messages:
		var role := str(message.get("role", "user"))
		var text := str(message.get("content", ""))
		if role == "system":
			system.append(text)
			continue
		role = "assistant" if role == "assistant" else "user"
		if turns.is_empty() and role == "assistant":
			turns.append({"role": "user", "content": "(Earlier.)"})
		if not turns.is_empty() and turns.back()["role"] == role:
			turns.back()["content"] += "\n\n" + text
		else:
			turns.append({"role": role, "content": text})
	if turns.is_empty():
		turns.append({"role": "user", "content": "..."})
	return JSON.stringify({"model": model, "max_tokens": OllamaMind.max_tokens("voice"),
		"temperature": OllamaMind.TEMPERATURE["voice"], "system": "\n\n".join(system), "messages": turns})


func take_results() -> Array[Dictionary]:
	var out := _results
	_results = []
	for result: Dictionary in inner.take_results():
		var serial := int(result.get("serial", 0))
		if result.get("kind", "") == "voice" and _fallen.has(serial):
			result["fallback"] = _fallen[serial]
			result["model"] = inner.kind
			_fallen.erase(serial)
		out.append(result)
	return out


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("timed out" if result == HTTPRequest.RESULT_TIMEOUT else "request failed (%d)" % result)
		return
	var response: Variant = OllamaMind._parse(text)
	if code != 200:
		var said := ""
		if response is Dictionary and response.get("error") is Dictionary:
			said = ": %s" % str(response["error"].get("type", ""))
		if code == 401 or code == 403:
			off = true
		_fail("HTTP %d%s" % [code, said])
		return
	var content := ""
	if response is Dictionary and response.get("content") is Array:
		for block: Variant in response["content"]:
			if block is Dictionary and block.get("type") == "text":
				content += str(block.get("text", ""))
	var usage: Dictionary = response.get("usage", {}) if response is Dictionary and response.get("usage") is Dictionary else {}
	var used_in := int(usage.get("input_tokens", 0))
	var used_out := int(usage.get("output_tokens", 0))
	var spent_now := note_spend(model, used_in, used_out)
	if content.strip_edges().is_empty():
		_fail("no text in the reply")
		return
	last_error = ""
	var ask: Dictionary = _sent.get("ask", {})
	var at := int(_sent.get("at", Time.get_ticks_msec()))
	_sent = {}
	var entry := _result_of(ask, content, OllamaMind.parse_voice(content.strip_edges(), str(ask.get("speaker", ""))), "", Time.get_ticks_msec() - at)
	entry["model"] = model
	entry["tokens_in"] = used_in
	entry["tokens_out"] = used_out
	entry["est_cost"] = spent_now
	_results.append(entry)


## The ask out failed for [param why]: it goes to her own mind.
func _fail(why: String) -> void:
	last_error = why
	print("[mind] claude (%s): %s; to %s" % [model, why, inner.kind])
	var ask: Dictionary = _sent.get("ask", {})
	_sent = {}
	var answer := _fall_back(ask, why)
	if not answer.is_empty():
		var entry := _result_of(ask, "", answer, "", 0)
		entry["fallback"] = why
		entry["model"] = inner.kind
		_results.append(entry)


## [param ask] to her own mind instead, for [param why]: its answer now
## (a mind that answers at once), else {} and it comes through
## take_results, noted as a fallback.
func _fall_back(ask: Dictionary, why: String) -> Dictionary:
	_fallen[int(ask.get("serial", 0))] = why
	var answer := inner.voice(ask)
	if not answer.is_empty():
		_fallen.erase(int(ask.get("serial", 0)))
	return answer


## A result in OllamaMind._result's shape (see CompanionMind.take_results).
static func _result_of(ask: Dictionary, raw: String, answer: Dictionary, error: String, latency: int) -> Dictionary:
	return {"kind": "voice", "serial": ask.get("serial", 0), "trigger": ask.get("trigger", ""),
		"prompt": Companion.render(ask["messages"]) if ask.has("messages") else "%s\n\n%s" % [ask.get("system", ""), ask.get("user", "")],
		"raw": raw, "answer": answer, "error": error, "latency_ms": latency,
		"spoken_to": ask.get("spoken_to", false), "asked": ask.get("asked", false), "always": ask.get("always", false),
		"heard": ask.get("heard", "")}
