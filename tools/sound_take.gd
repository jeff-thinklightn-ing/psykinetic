extends Node
## Lists a take in art/audio/takes.json, then writes docs/sound_status.md and
## THIRD_PARTY.md's sound block as tools/sound_status.gd does. Run by
## tools/sound_take.ps1, which makes the file first:
##   godot --headless --path . --scene res://tools/sound_take.tscn -- --slot=<slot> --file=<file>
##       --from=<source> --original=<text> --sha256=<hex> [--by=<author>] [--url=<page>]

const STATUS := "res://docs/sound_status.md"
const THIRD_PARTY := "res://THIRD_PARTY.md"


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var at := arg.find("=")
		if arg.begins_with("--") and at > 2:
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	for needed: String in ["slot", "file", "from", "sha256"]:
		if str(args.get(needed, "")) == "":
			_fail("--%s is needed" % needed)
			return
	if not SoundKit.has(args.slot):
		_fail("no slot %s" % args.slot)
		return
	if SoundKit.source(args.from).is_empty():
		_fail("no source %s" % args.from)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SoundKit.TAKES))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var all: Dictionary = data.get("takes", {})
	var list: Array = all.get(args.slot, [])
	for take: Dictionary in list:
		if take.get("file") == args.file:
			_fail("%s already lists %s" % [args.slot, args.file])
			return
	var take := {"file": args.file, "from": args.from, "original": args.get("original", ""), "sha256": args.sha256}
	for extra: String in ["by", "url"]:
		if str(args.get(extra, "")) != "":
			take[extra] = args[extra]
	list.append(take)
	all[args.slot] = list
	var sorted := {}
	var names := all.keys()
	names.sort()
	for name: String in names:
		sorted[name] = all[name]
	data["takes"] = sorted
	_write(SoundKit.TAKES, JSON.stringify(data, "\t", false) + "\n")
	SoundKit.reload()
	_write(STATUS, SoundKit.status_markdown())
	var text := FileAccess.get_file_as_string(THIRD_PARTY)
	var begin := text.find(SoundKit.THIRD_PARTY_BEGIN)
	var end := text.find(SoundKit.THIRD_PARTY_END)
	if begin >= 0 and end > begin:
		_write(THIRD_PARTY, text.left(begin) + SoundKit.third_party_block() + text.substr(end + SoundKit.THIRD_PARTY_END.length()))
	print("sound_take: %s lists %d takes" % [args.slot, list.size()])
	get_tree().quit(0)


func _fail(message: String) -> void:
	printerr("sound_take: " + message)
	get_tree().quit(1)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
