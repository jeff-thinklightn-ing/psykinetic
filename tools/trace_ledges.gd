extends Node
## Writes level.json's "ledges" (decision 585) for each level in FOLDERS from
## its relief as it is (Level.ledges_of), again each run:
##   Godot --headless --path . res://tools/trace_ledges.tscn
## (a scene, not a --script run: parsing the level needs the autoloads).
## For a level made by hand (the sample's outcrop); make_hills and
## make_wilds_marks write their own, and MapDoc.save writes them when the
## relief changes. The key is written into the file's text, the rest of it
## as it was.

const FOLDERS := ["res://levels/sample/"]


func _ready() -> void:
	for folder: String in FOLDERS:
		var doc := MapDoc.open(folder)
		var map := doc.map
		if not map.has_relief():
			print("[ledges] %s has no relief: left" % folder)
			continue
		var level := Level.parse(map.to_image(), null, doc.config, map.to_relief_image())
		var ledges := Level.ledges_of(level["terrain"])
		_drop_key(folder, "ledges")
		if not ledges.is_empty():
			_write_key(folder, "ledges", ledges)
		doc.config["ledges"] = ledges
		var again := Level.parse(map.to_image(), null, doc.config, map.to_relief_image())
		print("[ledges] %s: %d ledges; %s" % [folder, ledges.size(), "nothing said" if again["warnings"].is_empty() else "; ".join(again["warnings"])])
	get_tree().quit()


## [param key] taken out of [param folder]'s level.json text, the rest as it was.
func _drop_key(folder: String, key: String) -> void:
	var path := ProjectSettings.globalize_path(folder + "level.json")
	var text := FileAccess.get_file_as_string(path)
	var start := text.find(",\n\t" + JSON.stringify(key) + ":")
	if start < 0:
		return
	var end := text.find(",\n\t\"", start + 2)
	if end < 0:
		end = text.rfind("\n}")
	text = text.substr(0, start) + text.substr(end)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_key(folder: String, key: String, value: Variant) -> void:
	var path := ProjectSettings.globalize_path(folder + "level.json")
	var text := FileAccess.get_file_as_string(path)
	var close := text.rfind("}")
	var body := text.substr(0, close).rstrip("\n\t ")
	text = body + ",\n\t" + JSON.stringify(key) + ": " + JSON.stringify(value, "\t", false).replace("\n", "\n\t") + "\n}\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
