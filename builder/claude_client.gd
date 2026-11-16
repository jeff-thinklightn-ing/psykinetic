class_name ClaudeClient
extends Node
## Asks Claude through the Messages API (POST /v1/messages), for builder
## mode, on the server only. The key is the environment's ANTHROPIC_API_KEY
## (on the server box, /etc/psykinetic/env), never in the client or the repo,
## and ANTHROPIC_WORKSPACE_ID when the key is not scoped to a workspace (sent
## as anthropic-workspace-id). Neither is ever logged; each response's
## request-id is.
## send() is awaited: one request at a time, each on an HTTPRequest of its
## own, with a long timeout (a turn with thinking and tool calls takes a
## while). Refusals fall back server side to another model ("fallbacks":
## "default"). Every response's usage is logged with what it cost.

const URL := "https://api.anthropic.com/v1/messages"
const DEFAULT_MODEL := "claude-opus-5-5"
const TIMEOUT_SECONDS := 300.0
## Dollars per million tokens: input, output, cache read, cache write
## (5 minutes). Unknown models are priced as Opus.
const PRICES := {
	"claude-opus-5-5": [4.0, 20.0, 0.20, 5.0],
	"claude-sonnet-5-5": [2.0, 10.0, 0.20, 2.5],
	"claude-haiku-5-5": [0.10, 0.50, 0.01, 0.125],
	"claude-opus-4-8": [5.0, 25.0, 0.50, 6.25],
}
const FALLBACK_BETA := "server-side-fallback-2026-07-01"

var api_key := ""
var workspace_id := ""
## Logged with each request (the player who asked, the level).
var log_tag := ""
## The tag this client's lines go under: [builder] for builder mode's asks, [lawspeaker] for his rounds
## (decision 448), so a line names who asked.
var log_name := "builder"
## What a refused key stops, in the one plain line its first refusal prints (the coordinator, 11-16).
var refused_stops := "no builder answers until it is mended"
## The HTTP status of this run's first 401 or 403 (the key refused), 0 for none: said once, in a line of
## our own words, never the key and none of the API's text.
var refused := 0
## The refused line as said, and how many times (once a run; tests read them).
var refused_line := ""
var refusals_said := 0
## An error message from the API as logged: bounded.
const MESSAGE_CHARS := 200


func _ready() -> void:
	if api_key.is_empty():
		api_key = OS.get_environment("ANTHROPIC_API_KEY")
	if workspace_id.is_empty():
		workspace_id = OS.get_environment("ANTHROPIC_WORKSPACE_ID")


func has_key() -> bool:
	return not api_key.is_empty()


## The cost in dollars of a response's usage on [param model].
static func cost(model: String, input: int, output: int, cache_read: int, cache_write: int) -> float:
	var price: Array = PRICES.get(model, PRICES[DEFAULT_MODEL])
	return (input * price[0] + output * price[1] + cache_read * price[2] + cache_write * price[3]) / 1000000.0


## Sends [param body] (a Messages API request); the response as a
## Dictionary, or {"error": "..."}.
func send(body: Dictionary) -> Dictionary:
	if not has_key():
		return {"error": "no ANTHROPIC_API_KEY on the server"}
	var request := body.duplicate()
	request["fallbacks"] = "default"
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: " + api_key,
		"anthropic-version: 2023-06-01",
		"anthropic-beta: " + FALLBACK_BETA,
	])
	if not workspace_id.is_empty():
		headers.append("anthropic-workspace-id: " + workspace_id)
	var started := Time.get_ticks_msec()
	var error := http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(request))
	if error != OK:
		http.queue_free()
		return {"error": "could not send (%s)" % error_string(error)}
	var done: Array = await http.request_completed
	http.queue_free()
	return _answered(done, body, started)


## The answer to a request: [param done] (request_completed's result, code, headers and body), for
## [param body] sent at [param started] (msec). Logged as each request is; a refused key said once.
func _answered(done: Array, body: Dictionary, started: int) -> Dictionary:
	var result: int = done[0]
	var code: int = done[1]
	var text: String = (done[3] as PackedByteArray).get_string_from_utf8()
	var request_id := ""
	for header: String in done[2]:
		if header.to_lower().begins_with("request-id:"):
			request_id = header.substr(header.find(":") + 1).strip_edges()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "timed out" if result == HTTPRequest.RESULT_TIMEOUT else "no answer (%d)" % result}
	var json := JSON.new()
	var answered := json.parse(text) == OK and json.data is Dictionary
	if code != 200:
		var message: String = str(json.data["error"].get("message", text)) if answered and json.data.get("error") is Dictionary else text
		message = message.replace("\r", " ").replace("\n", " ").left(MESSAGE_CHARS)
		print("%sHTTP %d, request %s: %s" % [_line_head(), code, request_id, message])
		if code in [401, 403] and refused == 0:
			refused = code
			refused_line = "[%s] the API key is refused (HTTP %d): %s" % [log_name, code, refused_stops]
			refusals_said += 1
			print(refused_line)
		return {"error": "HTTP %d: %s" % [code, message], "status": code}
	if not answered:
		return {"error": "HTTP %d, not JSON" % code}
	var response: Dictionary = json.data
	var used: Dictionary = response.get("usage", {})
	var model := str(response.get("model", body.get("model", DEFAULT_MODEL)))
	print("%s%s (request %s): %d in, %d out, %d cache read, %d cache write, $%.4f, %.1f s, %s" % [_line_head(), model, request_id,
		int(used.get("input_tokens", 0)), int(used.get("output_tokens", 0)), int(used.get("cache_read_input_tokens", 0)),
		int(used.get("cache_creation_input_tokens", 0)),
		cost(model, int(used.get("input_tokens", 0)), int(used.get("output_tokens", 0)),
			int(used.get("cache_read_input_tokens", 0)), int(used.get("cache_creation_input_tokens", 0))),
		(Time.get_ticks_msec() - started) / 1000.0, response.get("stop_reason", "")])
	return response


## "[builder] <the asker>: ", or "[lawspeaker] " with no tag: what each request's line starts with.
func _line_head() -> String:
	return "[%s] %s" % [log_name, log_tag + ": " if not log_tag.is_empty() else ""]
