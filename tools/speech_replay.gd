extends Node
## Replays a companion's transcript through what she would say now
## (Companion.spoken and the fragment rule), line by line in order, and
## prints each of her lines that comes out differently:
##   Godot --headless --path . --scene tools/speech_replay.tscn -- <transcript> <keeper>
## <transcript>: a Transcript file (<companion>-<date>.txt); <keeper>: the
## name of her player. Events and others' words go into her exchange as
## they did then; her lines are cleaned as if the voice had said them. Only
## the words are replayed: what asked her voice (and so how often) is not.

const KINDS: Array[String] = ["imp", "brute", "sneak"]
var DEATH_LINES: Array = load("res://main.gd").COMPANION_DEATH_LINES


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <transcript> <keeper>")
		get_tree().quit(1)
		return
	var path := args[0]
	var keeper := args[1]
	var companion := path.get_file().get_slice("-", 0)
	var pet := Companion.new()
	pet.name = companion
	pet.keeper_label = keeper
	for kind in KINDS:
		pet._kinds_seen[kind] = true
	var said := 0
	var changed := 0
	var dropped := 0
	var asked := false
	for raw in FileAccess.get_file_as_string(path).split("\n", false):
		var clock := raw.get_slice(" ", 0).split(":")
		if clock.size() == 3:
			World.tick = (int(clock[0]) * 3600 + int(clock[1]) * 60 + int(clock[2])) * World.TICK_RATE
		var text := raw.substr(raw.find(" ") + 1)
		if text.begins_with("["):
			pet._add_turn("user", text, true)
			continue
		var speaker := text.get_slice(":", 0)
		var words := text.substr(speaker.length() + 1).strip_edges()
		if speaker != companion:
			pet._heard.append({"text": words, "tick": World.tick, "speaker": speaker})
			pet._add_turn("user", words, false, speaker)
			asked = speaker == keeper
			continue
		if words in DEATH_LINES:
			continue  # Last words, chosen by Main, not her voice.
		said += 1
		var now := pet.spoken(words, false, asked)
		if not asked and now.split(" ", false).size() < Companion.FRAGMENT_WORDS and not now.ends_with("!"):
			now = ""
		asked = false
		if now != words:
			changed += 1
			dropped += 1 if now.is_empty() else 0
			print("%s  before: %s\n          after:  %s" % [raw.get_slice(" ", 0), words, now if not now.is_empty() else "(nothing)"])
		if not now.is_empty():
			pet.remember_said(now)
			pet._add_turn("assistant", now)
	print("%s: %d lines, %d changed, %d not said" % [path.get_file(), said, changed, dropped])
	pet.free()
	get_tree().quit()
