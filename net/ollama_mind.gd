class_name OllamaMind
extends CompanionMind
## A mind that asks Ollama's native chat endpoint (/api/chat): JSON-only
## output, reasoning off, the model kept loaded. A URL ending in
## /chat/completions is treated as an OpenAI-compatible endpoint instead,
## with that request and reply shape. Asynchronous: decide() starts a
## request and answers {} at once, so the companion uses the scripted answer
## for that window; the reply, if it comes back in time and parses, is picked
## up by poll() and applied then. One request in flight per companion. Any
## error, timeout or parse failure is logged and simply means the scripted
## answer stands. The tick is never blocked.

const TIMEOUT_SECONDS := 2.0
const SYSTEM_PROMPT := """You are the mind of a companion creature in a small tactical game.
You will be given the situation as JSON. Reply with a single JSON object and nothing else, of the form
{"intent": "FOLLOW"|"HOLD"|"ATTACK"|"SHOVE"|"RETREAT"|"IDLE", "target": <entity name or null>, "say": <one short line or "">}.
ATTACK and SHOVE need the name of a nearby entity as target. Stay in character for your personality card."""

var url := ""
var model := ""
## True when the URL is an OpenAI-compatible endpoint (.../chat/completions)
## rather than Ollama's native /api/chat.
var openai_shaped := false
## What went wrong last time, for the console. "" when the last reply was fine.
var last_error := ""

var _http: HTTPRequest
var _in_flight := false
var _reply: Dictionary = {}
var _stubbed_body := ""


## [param host] is a node to hang the HTTPRequest under.
func _init(endpoint: String, model_name: String, host: Node) -> void:
	kind = "ollama"
	url = endpoint
	model = model_name
	openai_shaped = endpoint.trim_suffix("/").ends_with("/chat/completions")
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	_http.request_completed.connect(_on_request_completed)
	host.add_child(_http)


func decide(context: Dictionary) -> Dictionary:
	if _in_flight:
		return {}
	_in_flight = true
	_reply = {}
	if not _stubbed_body.is_empty():
		# Test hook: pretend the endpoint answered with this body at once.
		var body := _stubbed_body
		_stubbed_body = ""
		_on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body.to_utf8_buffer())
		return {}
	var error := _http.request(url, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, request_body(context))
	if error != OK:
		_fail("request not sent: %s" % error_string(error))
	return {}


## The JSON body sent for [param context]. Reasoning is turned off
## ("think": false): a 2-second window has no room for it. The native
## endpoint is also asked for JSON output and to keep the model loaded.
func request_body(context: Dictionary) -> String:
	var messages := [
		{"role": "system", "content": SYSTEM_PROMPT},
		{"role": "user", "content": JSON.stringify(context)},
	]
	if openai_shaped:
		return JSON.stringify({
			"model": model, "think": false, "stream": false, "temperature": 0.7,
			"messages": messages,
		})
	return JSON.stringify({
		"model": model, "think": false, "stream": false, "format": "json", "keep_alive": -1,
		"messages": messages,
	})


func poll() -> Dictionary:
	if _reply.is_empty():
		return {}
	var answer := _reply
	_reply = {}
	return answer


## Test hook: the next decide() gets this as the endpoint's response body.
func stub_next_reply(body: String) -> void:
	_stubbed_body = body


func _on_request_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("timed out" if result == HTTPRequest.RESULT_TIMEOUT else "request failed (%d)" % result)
		return
	if code != 200:
		_fail("HTTP %d" % code)
		return
	var response: Variant = _parse(body.get_string_from_utf8())
	var content := _openai_content_of(response) if openai_shaped else _native_content_of(response)
	if content.is_empty():
		_fail("no message content in the response")
		return
	var answer: Variant = _parse(_strip_fences(strip_think(content)))
	if answer is not Dictionary or not answer.has("intent"):
		_fail("reply is not a JSON object with an intent: %s" % content.left(80))
		return
	last_error = ""
	_reply = answer


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


func _fail(why: String) -> void:
	_in_flight = false
	last_error = why
	print("[mind] ollama: %s; the scripted answer stands" % why)
