class_name PartyLog
extends RefCounted
## Plain-English record of what happened, kept by the server: pushes,
## impacts, damage, deaths, fire, orders, joins and leaves. Players are named
## by their record name, companions by their name. Companion minds read the
## tail of it as context.

const MAX_LINES := 200

var _lines: Array[String] = []


func add(sentence: String) -> void:
	_lines.append(sentence)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()


## The most recent [param count] sentences, oldest first.
func last(count: int) -> Array[String]:
	var from := maxi(_lines.size() - count, 0)
	return _lines.slice(from)


func size() -> int:
	return _lines.size()
