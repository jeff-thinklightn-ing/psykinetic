class_name ClaudeClient
extends Node
## Asks Claude through the Messages API (POST /v1/messages), for builder
## mode, on the server only. The key is the environment's ANTHROPIC_API_KEY
## (on the server box, /etc/psykinetic/env), never in the client or the repo.
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
## Logged with each request (the player who asked, the level).
var log_tag := ""


func _ready() -> void:
	if api_key.is_empty():
		api_key = OS.get_environment("ANTHROPIC_API_KEY")


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
	var started := Time.get_ticks_msec()
	var error := http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(request))
	if error != OK:
		http.queue_free()
		return {"error": "could not send (%s)" % error_string(error)}
	var done: Array = await http.request_completed
	http.queue_free()
	var result: int = done[0]
	var code: int = done[1]
	var text: String = (done[3] as PackedByteArray).get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "timed out" if result == HTTPRequest.RESULT_TIMEOUT else "no answer (%d)" % result}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"error": "HTTP %d, not JSON" % code}
	var response: Dictionary = json.data
	if code != 200:
		var message: String = str(response.get("error", {}).get("message", text.left(200))) if response.get("error") is Dictionary else text.left(200)
		return {"error": "HTTP %d: %s" % [code, message]}
	var used: Dictionary = response.get("usage", {})
	var model := str(response.get("model", body.get("model", DEFAULT_MODEL)))
	print("[builder] %s %s: %d in, %d out, %d cache read, %d cache write, $%.4f, %.1f s, %s" % [log_tag, model,
		int(used.get("input_tokens", 0)), int(used.get("output_tokens", 0)), int(used.get("cache_read_input_tokens", 0)),
		int(used.get("cache_creation_input_tokens", 0)),
		cost(model, int(used.get("input_tokens", 0)), int(used.get("output_tokens", 0)),
			int(used.get("cache_read_input_tokens", 0)), int(used.get("cache_creation_input_tokens", 0))),
		(Time.get_ticks_msec() - started) / 1000.0, response.get("stop_reason", "")])
	return response
