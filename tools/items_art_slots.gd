extends SceneTree
## Writes art/kit/slots_items.json, every item's ArtKit slot, from the item
## catalog (levels/items.json, Items.art_slots):
##   Godot --headless --path . --script tools/items_art_slots.gd
## Run it after changing the catalog; tests/items_test checks the file is
## current. ArtKit reads it beside art/kit/slots.json. Then it runs
## tools/art_status.gd, so docs/art_status.md and THIRD_PARTY.md count them.


func _init() -> void:
	var text := JSON.stringify(Items.art_slots(), "\t") + "\n"
	var file := FileAccess.open(Items.ART_SLOTS, FileAccess.WRITE)
	if file == null:
		printerr("[items] cannot write %s" % Items.ART_SLOTS)
		quit(1)
		return
	file.store_string(text)
	file.close()
	print("[items] %s: %d slots, OK" % [Items.ART_SLOTS, Items.ids().size()])
	# The art status report counts these slots too: written again, by a
	# fresh run (ArtKit reads its manifest once).
	var output := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/art_status.gd"], output, true)
	print("".join(output).strip_edges())
	quit(code)
