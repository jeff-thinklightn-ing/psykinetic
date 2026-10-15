extends SceneTree
## Writes docs/art_status.md (every art slot by what it is drawn from now,
## the placeholders first), art/kit/status.json (the same for tools, in
## art/kit/priority.json's order) and the art slot block of THIRD_PARTY.md, from
## art/kit/slots.json and the slot folders, and prints the counts. Run it
## after art lands; tools/art_drop.ps1 does. art_kit_test fails while
## either is out of date.
##   godot --headless --path . --script tools/art_status.gd

const STATUS := "res://docs/art_status.md"
const STATUS_JSON := "res://art/kit/status.json"
const THIRD_PARTY := "res://THIRD_PARTY.md"


func _initialize() -> void:
	var status := ArtCheck.status_markdown()
	_write(STATUS, status)
	_write(STATUS_JSON, ArtCheck.status_json())
	var text := FileAccess.get_file_as_string(THIRD_PARTY)
	var begin := text.find(ArtCheck.THIRD_PARTY_BEGIN)
	var end := text.find(ArtCheck.THIRD_PARTY_END)
	if begin < 0 or end < begin:
		push_error("art_status: %s has no art slot block (%s ... %s) to fill" % [THIRD_PARTY, ArtCheck.THIRD_PARTY_BEGIN, ArtCheck.THIRD_PARTY_END])
		quit(1)
		return
	_write(THIRD_PARTY, text.left(begin) + ArtCheck.third_party_block() + text.substr(end + ArtCheck.THIRD_PARTY_END.length()))
	for line in status.split("\n").slice(3, 5):
		print(line)
	quit(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("wrote %s" % path.trim_prefix("res://"))
