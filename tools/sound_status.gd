extends SceneTree
## Writes docs/sound_status.md (every sound slot by what it plays from now,
## the placeholders first) and the sound slot block of THIRD_PARTY.md, from
## art/audio/slots.json and the slot folders, and prints the counts. Run it
## after sounds land. sound_kit_test fails while either is out of date.
##   godot --headless --path . --script tools/sound_status.gd

const STATUS := "res://docs/sound_status.md"
const THIRD_PARTY := "res://THIRD_PARTY.md"


func _initialize() -> void:
	var status := SoundKit.status_markdown()
	_write(STATUS, status)
	var text := FileAccess.get_file_as_string(THIRD_PARTY)
	var begin := text.find(SoundKit.THIRD_PARTY_BEGIN)
	var end := text.find(SoundKit.THIRD_PARTY_END)
	if begin < 0 or end < begin:
		push_error("sound_status: %s has no sound slot block (%s ... %s) to fill" % [THIRD_PARTY, SoundKit.THIRD_PARTY_BEGIN, SoundKit.THIRD_PARTY_END])
		quit(1)
		return
	_write(THIRD_PARTY, text.left(begin) + SoundKit.third_party_block() + text.substr(end + SoundKit.THIRD_PARTY_END.length()))
	for line in status.split("\n").slice(3, 5):
		print(line)
	quit(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("wrote %s" % path.trim_prefix("res://"))
