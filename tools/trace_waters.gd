extends Node
## Lays the last cell-painted water as curves (568 amended; Jeff: rivers,
## streams and shorelines are smooth curves, never cell regions), once:
##   Godot --headless --path . res://tools/trace_waters.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
## Each body of water of two cells or more in FOLDERS (the castle's ponds) is
## traced into a closed curve (Curves.trace), its cells then the curve's
## (Curves.laid on the level's floor and water as Level reads them; the old
## water outside it grass), as make_wilds_marks traced the wilds'. A lone
## water cell is a well's, and is left. level.json "waters" is written into
## the file's text, the rest of it as it was; with "waters" there, the level
## is left. (The sample keeps its cell water: terrain's tests of drawing it.)

const FOLDERS := ["res://levels/castle/"]


func _ready() -> void:
	for folder: String in FOLDERS:
		_trace(folder)
	get_tree().quit()


func _trace(folder: String) -> void:
	var doc := MapDoc.open(folder)
	if doc.config.has("waters"):
		print("[waters] %s has its waters: left" % folder)
		return
	var map := doc.map
	var waters: Array = []
	var ground := _ground(doc)
	var seen := {}
	for start: Vector2i in map.cells:
		if seen.has(start) or map.cell(start) != "water":
			continue
		var body := {start: true}
		seen[start] = true
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			for step in Relief.FOUR:
				var next: Vector2i = at + step
				if not seen.has(next) and map.cell(next) == "water":
					seen[next] = true
					body[next] = true
					queue.append(next)
		if body.size() < 2:
			continue
		var points := Curves.trace(body)
		var widths := PackedFloat32Array()
		widths.resize(points.size())
		var inside: Dictionary = Curves.laid(Curves.sample(points, widths, true), true, ground)["cells"]
		for cell: Vector2i in body:
			if not inside.has(cell):
				map.set_cell(cell, "grass")
		for cell: Vector2i in inside:
			map.set_cell(cell, "water")
		waters.append({"points": Curves.to_json(points, widths), "closed": true})
		print("[waters] %s pond at %s: %d cells traced into %d points, %d cells now" % [folder, start, body.size(), points.size(), inside.size()])
	if waters.is_empty():
		return
	var layout := folder + "layout.png"
	map.to_image().save_png(ProjectSettings.globalize_path(layout))
	LevelMap.ensure_image_import(ProjectSettings.globalize_path(layout), layout)
	doc.config["waters"] = waters
	_write_key(folder, "waters", waters)
	var level := Level.parse(map.to_image(), null, doc.config, map.to_relief_image() if map.relief.size() > 0 else null)
	print("[waters] %s laid; %s" % [folder, "nothing said" if level["warnings"].is_empty() else "; ".join(level["warnings"])])


## What a water may lay on: the level's floor and water as Level reads them,
## so the cells written are the ones it lays from the curve on load.
func _ground(doc: MapDoc) -> Dictionary:
	var map := doc.map
	var terrain: Dictionary = Level.parse(map.to_image(), null, doc.config, map.to_relief_image() if map.relief.size() > 0 else null)["terrain"]
	var ground := {}
	for key in ["floor", "water", "fords", "bridged"]:
		for cell: Vector2i in terrain.get(key, []):
			ground[cell] = true
	return ground


func _write_key(folder: String, key: String, value: Variant) -> void:
	var path := ProjectSettings.globalize_path(folder + "level.json")
	var text := FileAccess.get_file_as_string(path)
	var close := text.rfind("}")
	var body := text.substr(0, close).rstrip("\n\t ")
	text = body + ",\n\t" + JSON.stringify(key) + ": " + JSON.stringify(value, "\t", false).replace("\n", "\n\t") + "\n}\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
