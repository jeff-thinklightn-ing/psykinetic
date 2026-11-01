class_name PartyLog
extends RefCounted
## Plain-English record of what happened, kept by the server: pushes,
## impacts, damage, deaths, fire, orders, joins and leaves. Players are named
## by their record name, companions by their name. Companion minds read the
## tail of it as context.

const MAX_LINES := 200

var _lines: Array[String] = []


## A sentence opening on a monster's in-sentence name ("the draugr hits
## you", 752, dungeon's side) is kept with its first letter capital.
func add(sentence: String) -> void:
	if sentence.begins_with("the "):
		sentence = "T" + sentence.substr(1)
	_lines.append(sentence)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()


## The most recent [param count] sentences, oldest first.
func last(count: int) -> Array[String]:
	var from := maxi(_lines.size() - count, 0)
	return _lines.slice(from)


func size() -> int:
	return _lines.size()
