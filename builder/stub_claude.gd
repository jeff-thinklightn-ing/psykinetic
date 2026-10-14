class_name StubClaude
extends RefCounted
## Stands in for ClaudeClient in tests and on a server with no key
## (--builder-stub): send() answers from a script instead of the API.
## Each turn is a list of tool calls ({name, input}) or a closing text; the
## script runs once per request (a follow-up starts it again), so a test can
## say exactly what "Claude" did. The bodies it was sent are kept.

## Turns, in order: an Array of {name, input} (tool calls), or a String
## (the closing words).
var turns: Array = []
var sent: Array[Dictionary] = []
var _turn := 0


func _init(script_turns: Array = []) -> void:
	turns = script_turns


func send(body: Dictionary) -> Dictionary:
	sent.append(body.duplicate(true))
	# A new request (the last message is the player's words, not tool results) starts the script again.
	var last: Dictionary = body["messages"].back()
	if last.get("content") is String:
		_turn = 0
	var usage := {"input_tokens": 1000, "output_tokens": 200, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
	if _turn >= turns.size():
		return {"model": body.get("model", ""), "stop_reason": "end_turn", "usage": usage,
			"content": [{"type": "text", "text": "Done."}]}
	var turn: Variant = turns[_turn]
	_turn += 1
	if turn is String:
		return {"model": body.get("model", ""), "stop_reason": "end_turn", "usage": usage, "content": [{"type": "text", "text": turn}]}
	var content: Array = []
	for i in (turn as Array).size():
		var call: Dictionary = turn[i]
		content.append({"type": "tool_use", "id": "stub_%d_%d" % [_turn, i], "name": call["name"], "input": call.get("input", {})})
	await Engine.get_main_loop().process_frame
	return {"model": body.get("model", ""), "stop_reason": "tool_use", "usage": usage, "content": content}
