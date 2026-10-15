extends Node
## Writes a --state snapshot with the wilds town populated: forge and kitchen
## standing, 12 residents (Main's RESIDENTS_MAX), for benches: a host run
## with --map=wilds --state=<a copy> has their bodies. Zones are left empty,
## so the level spawns as usual. Run it under a private APPDATA; --out is an
## absolute path, never under the shared user:// (the host rewrites --state).
##   godot --headless --path <repo> res://tools/town_state.tscn -- --out=<path.json>

const TOWN := "wilds/store"
const FOLK := [["smith_1", "Odo", "smith"], ["cook_1", "Mags", "cook"], ["smith_2", "Bran", "smith"],
	["cook_2", "Tilda", "cook"], ["hand_1", "Ash", "hauler"], ["hand_2", "Bea", "hauler"],
	["hand_3", "Cole", "hauler"], ["hand_4", "Dara", "hauler"], ["hand_5", "Eli", "hauler"],
	["hand_6", "Fen", "hauler"], ["hand_7", "Gus", "hauler"], ["hand_8", "Hal", "hauler"]]


func _ready() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var clock := func() -> int: return 0
	var world_map := WorldMap.build()
	var holdings := Holdings.new(world_map, Factions.read(), {}, clock)
	var book := ItemBook.new(clock)
	var stock := Stockpile.new({}, clock, book)
	var work := Production.new({}, stock, holdings, clock)
	var towns := Towns.new({}, work, {}, clock)
	towns.seed_from(world_map)
	for each in FOLK:
		towns.note_rescue(TOWN, each[0], each[1], each[2])
	print("residents: ", towns.residents(TOWN))
	var ok := Snapshot.save(out, {}, [], {"steps": 0, "holdings": holdings.to_dict(), "items": book.to_dict(),
		"stockpile": stock.to_dict(), "production": work.to_dict(), "towns": towns.to_dict()})
	print("saved ", out, " ", ok)
	get_tree().quit(0 if ok else 1)
