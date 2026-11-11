extends RefCounted
## level.json written keeping the file's own text (decision 851): every
## value unchanged from the text it was read from is written as that text,
## so a diff of a saved level shows only what changed. Godot's own round
## trip (JSON.parse_string, then JSON.stringify) reads every number as a
## float and writes "181" back as "181.0", and opens out every line a hand
## kept short ({"cell": [3, 8], ...}): 2,877 of wilds' 3,322 lines, for an
## edit of one.
##
## A changed object or array is written again, its unchanged members still
## in their own text: one kept on one line stays on one line (", " and
## ": ", as the hand writes it), one opened out stays opened out (a tab an
## indent, as JSON.stringify(value, "\t", false) writes it). A new member
## of an array takes its last old sibling's way; a new list of plain values
## is one line. A number written fresh is written without ".0" when whole. No old text, or one that is not
## JSON: the whole value written fresh, opened out.


## [param value] as JSON, in [param old_text]'s own words wherever it is
## unchanged from it. The same value as old_text's gives old_text back,
## byte for byte.
static func write(old_text: String, value: Variant) -> String:
	var root: Variant = _Scan.new(old_text).top() if not old_text.is_empty() else null
	if root == null:
		return _fresh(value, 0, false) + "\n"
	var node: Dictionary = root
	return old_text.substr(0, node["s"]) + _emit(value, node, 0, old_text, false) + old_text.substr(node["e"])


## [param value] at [param depth] (tabs), [param node] the old text's value
## in its place (null for none), [param short] whether its container is
## kept on one line.
static func _emit(value: Variant, node: Variant, depth: int, text: String, short: bool) -> String:
	if node == null:
		return _fresh(value, depth, short)
	var old: Dictionary = node
	if same(value, old["v"]):
		return text.substr(old["s"], old["e"] - old["s"])
	var one_line := not text.substr(old["s"], old["e"] - old["s"]).contains("\n")
	if value is Dictionary and old["v"] is Dictionary:
		var members := PackedStringArray()
		var kids: Dictionary = old["kids"]
		for key: Variant in value:
			members.append(JSON.stringify(str(key)) + ": " + _emit(value[key], kids.get(str(key)), depth + 1, text, one_line))
		return _wrap("{", "}", members, depth, one_line)
	if value is Array and old["v"] is Array:
		var items := PackedStringArray()
		var kids: Array = old["kids"]
		for i in (value as Array).size():
			if i < kids.size():
				items.append(_emit(value[i], kids[i], depth + 1, text, one_line))
			else:
				# A new item: the way of the last old one (a short line among short lines).
				var last: Variant = kids.back() if not kids.is_empty() else null
				var last_short := one_line or (last != null and not text.substr(last["s"], last["e"] - last["s"]).contains("\n"))
				items.append(_fresh(value[i], depth + 1, last_short))
		return _wrap("[", "]", items, depth, one_line)
	return _fresh(value, depth, short)


## [param value] written new at [param depth], on one line when
## [param short].
static func _fresh(value: Variant, depth: int, short: bool) -> String:
	if value is Dictionary:
		var members := PackedStringArray()
		for key: Variant in value:
			members.append(JSON.stringify(str(key)) + ": " + _fresh(value[key], depth + 1, short))
		return _wrap("{", "}", members, depth, short)
	if value is Array:
		var items := PackedStringArray()
		for item: Variant in value:
			items.append(_fresh(item, depth + 1, short))
		# A list of plain values ("cell": [3, 4]) on one line.
		var plain := (value as Array).all(func(item: Variant) -> bool: return not (item is Array or item is Dictionary))
		return _wrap("[", "]", items, depth, short or plain)
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 1e15:
		return str(int(value))
	if value is Vector2i or value is Vector2:
		return _fresh([value.x, value.y], depth, true)
	return JSON.stringify(value)


static func _wrap(open: String, close: String, parts: PackedStringArray, depth: int, short: bool) -> String:
	if parts.is_empty():
		return open + close
	if short:
		return open + ", ".join(parts) + close
	var inner := "\t".repeat(depth + 1)
	return open + "\n" + inner + (",\n" + inner).join(parts) + "\n" + "\t".repeat(depth) + close


## Whether [param a] and [param b] are the same JSON value: numbers by
## value (an int 3 and a float 3.0 alike), objects by their keys in order.
static func same(a: Variant, b: Variant) -> bool:
	var a_number := a is int or a is float
	if a_number or b is int or b is float:
		return a_number and (b is int or b is float) and float(a) == float(b)
	if a is Dictionary:
		if not b is Dictionary or (a as Dictionary).size() != (b as Dictionary).size():
			return false
		var a_keys: Array = (a as Dictionary).keys()
		var b_keys: Array = (b as Dictionary).keys()
		for i in a_keys.size():
			if str(a_keys[i]) != str(b_keys[i]) or not same(a[a_keys[i]], b[b_keys[i]]):
				return false
		return true
	if a is Array:
		if not b is Array or (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not same(a[i], b[i]):
				return false
		return true
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	return typeof(a) == typeof(b) and a == b


## The old text read for where each value lies: a node is {"s": its first
## character, "e": one past its last, "v": the value, "kids": an object's
## members by key or an array's items, as nodes}.
class _Scan:
	var text: String
	var at := 0
	var failed := false

	func _init(source: String) -> void:
		text = source

	## The top value's node, or null when the text is not one JSON value.
	func top() -> Variant:
		_space()
		var node := _value()
		_space()
		if failed or at != text.length():
			return null
		return node

	func _space() -> void:
		while at < text.length() and text.unicode_at(at) in [32, 9, 10, 13]:
			at += 1

	func _value() -> Dictionary:
		if at >= text.length():
			failed = true
			return {}
		var start := at
		var c := text.unicode_at(at)
		if c == 123: # {
			at += 1
			var kids := {}
			var value := {}
			_space()
			if at < text.length() and text.unicode_at(at) == 125:
				at += 1
				return {"s": start, "e": at, "v": value, "kids": kids}
			while not failed:
				_space()
				var key_node := _value()
				if failed or not key_node.get("v") is String:
					failed = true
					break
				_space()
				if at >= text.length() or text.unicode_at(at) != 58: # :
					failed = true
					break
				at += 1
				_space()
				var member := _value()
				if failed:
					break
				kids[key_node["v"]] = member
				value[key_node["v"]] = member["v"]
				_space()
				if at < text.length() and text.unicode_at(at) == 44: # ,
					at += 1
				elif at < text.length() and text.unicode_at(at) == 125:
					at += 1
					return {"s": start, "e": at, "v": value, "kids": kids}
				else:
					failed = true
			return {}
		if c == 91: # [
			at += 1
			var kids: Array = []
			var value: Array = []
			_space()
			if at < text.length() and text.unicode_at(at) == 93:
				at += 1
				return {"s": start, "e": at, "v": value, "kids": kids}
			while not failed:
				_space()
				var item := _value()
				if failed:
					break
				kids.append(item)
				value.append(item["v"])
				_space()
				if at < text.length() and text.unicode_at(at) == 44:
					at += 1
				elif at < text.length() and text.unicode_at(at) == 93:
					at += 1
					return {"s": start, "e": at, "v": value, "kids": kids}
				else:
					failed = true
			return {}
		if c == 34: # "
			at += 1
			while at < text.length() and text.unicode_at(at) != 34:
				at += 2 if text.unicode_at(at) == 92 else 1
			if at >= text.length():
				failed = true
				return {}
			at += 1
		else:
			# A number, true, false or null: up to the next delimiter.
			while at < text.length() and not text.unicode_at(at) in [44, 93, 125, 32, 9, 10, 13]:
				at += 1
		var word := text.substr(start, at - start)
		var json := JSON.new()
		if json.parse(word) != OK:
			failed = true
			return {}
		return {"s": start, "e": at, "v": json.data}
