extends Node
## The look comes from the theme (decision 840): no window sets a colour, font
## or size of its own. This counts, in each file of the game's code, the theme
## overrides (add_theme_*_override and begin_bulk_theme_override in a script,
## theme_override_* in a scene), the loose colours drawn in render/ and main.gd
## (Color(<number>, Color("#, Color.html(, Color8(, Color.WHITE and the other
## named ones but TRANSPARENT) and the fonts loaded outside the theme, and holds
## each file to its line in tests/style_budget.txt. Over the line fails: a new
## colour, font or size goes through ui-design's theme. Under it fails too,
## until the line is lowered in the same commit, so the count only falls. A file
## with no line has a budget of 0. Comments don't count.
## Not counted: render/parts/ and render/ui_theme.gd (they are the look),
## editor/, tools/ and tests/ (not the game), and client3d/art_kit.gd's fonts
## (the carved signs' face is art).
## -- --print-budget writes the whole budget as counted now to this scene's
## scratch folder and prints its path, for ui-design when the rule changes.
## No port: it opens no network.

const BUDGET := "res://tests/style_budget.txt"
const ROOTS: Array[String] = ["render", "client3d", "builder", "net", "sim"]
const FILES: Array[String] = ["main.gd", "main.tscn"]
const EXEMPT_DIRS: Array[String] = ["render/parts/"]
const EXEMPT_FILES: Array[String] = ["render/ui_theme.gd"]
const ART_FONTS: Array[String] = ["client3d/art_kit.gd"]
## Loose colours are counted where the interface is drawn.
const COLOUR_ROOTS: Array[String] = ["render/", "main.gd"]

var _failures := 0
var _override := RegEx.create_from_string("\\b(add_theme_(color|constant|font|font_size|icon|stylebox)_override|begin_bulk_theme_override)\\s*\\(")
var _scene_override := RegEx.create_from_string("^theme_override_")
var _colour := RegEx.create_from_string("\\bColor\\(\\s*([-.\\d]|\"#)|\\bColor\\.html\\(|\\bColor8\\(|\\bColor\\.(?!TRANSPARENT\\b)[A-Z][A-Z_]+\\b")
var _font := RegEx.create_from_string("art/fonts/|\\b(FontVariation|FontFile|SystemFont)\\.new\\(")


func _ready() -> void:
	var counts := count_all()
	if "--print-budget" in OS.get_cmdline_user_args():
		var path: String = preload("res://tests/test_ports.gd").scratch("style_budget.txt")
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(budget_text(counts))
		out.close()
		print("budget as counted now: %s" % ProjectSettings.globalize_path(path))
	var budget := read_budget()
	print("== each file holds to its line in tests/style_budget.txt ==")
	var over: Array[String] = []
	var under: Array[String] = []
	var totals := [0, 0, 0]
	for file: String in _sorted(counts.keys()):
		var have: Array = counts[file]
		var may: Array = budget.get(file, [0, 0, 0])
		for k in 3:
			totals[k] += have[k]
		if have == may:
			continue
		var line := budget_line(file, have)
		var worse: bool = have[0] > may[0] or have[1] > may[1] or have[2] > may[2]
		var what := "%s: %s now, its line says %s." % [file, _said(have), _said(may)]
		if worse:
			over.append("    " + what)
		else:
			under.append("    %s\n      Lower its line in tests/style_budget.txt to: %s" % [what, line if not line.is_empty() else "(delete the line)"])
	var stale: Array[String] = []
	for file: String in _sorted(budget.keys()):
		if not counts.has(file):
			stale.append("    %s has a line but nothing counted in it (gone or exempt): delete the line" % file)
	for message in over + under + stale:
		print(message)
	if not over.is_empty():
		print("      A new colour, font or size goes through ui-design's theme, not an override or a literal: use a theme variation (theme_type_variation) or a part (render/parts/), or ask ui-design for one.")
	_check(over.is_empty(), "no file over its line (%d overrides, %d loose colours, %d fonts in all)" % totals)
	_check(under.is_empty() and stale.is_empty(), "no file under its line: the budget falls with the count")
	print("== the counting rule ==")
	_check(_counts_rule(), "it counts overrides, loose colours and fonts, not comments, strings or exempt files")
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## file (res-relative) -> [overrides, colours, fonts], for every file with any.
func count_all() -> Dictionary:
	var counts := {}
	var files: Array[String] = []
	for root in ROOTS:
		_walk(root, files)
	for file in FILES:
		if FileAccess.file_exists("res://" + file):
			files.append(file)
	for file in files:
		if _exempt(file):
			continue
		var found := count_text(file, FileAccess.get_file_as_string("res://" + file))
		if found != [0, 0, 0]:
			counts[file] = found
	return counts


## [overrides, colours, fonts] in [param text], as the file [param file].
func count_text(file: String, text: String) -> Array:
	var found := [0, 0, 0]
	var scene := file.ends_with(".tscn")
	var colours := false
	for root in COLOUR_ROOTS:
		colours = colours or file.begins_with(root)
	colours = colours and not scene
	var fonts := file not in ART_FONTS
	for raw in text.split("\n"):
		var line: String = raw.strip_edges() if scene else code_of(raw)
		if line.is_empty():
			continue
		if scene:
			if _scene_override.search(line) != null:
				found[0] += 1
		else:
			found[0] += _override.search_all(line).size()
			if colours:
				found[1] += _colour.search_all(line).size()
		if fonts:
			found[2] += _font.search_all(line).size()
	return found


## [param line] without its comment: from the first # outside a string.
static func code_of(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if not quote.is_empty():
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
		i += 1
	return line


func read_budget() -> Dictionary:
	var budget := {}
	for raw in FileAccess.get_file_as_string(BUDGET).split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var fields := line.split(" ", false)
		if fields.size() != 4:
			print("    tests/style_budget.txt: \"%s\" is not \"path overrides colours fonts\"" % line)
			_failures += 1
			continue
		budget[fields[0]] = [fields[1].to_int(), fields[2].to_int(), fields[3].to_int()]
	return budget


static func budget_line(file: String, have: Array) -> String:
	return "" if have == [0, 0, 0] else "%s %d %d %d" % [file, have[0], have[1], have[2]]


func budget_text(counts: Dictionary) -> String:
	var head := FileAccess.get_file_as_string(BUDGET).split("\n")
	var out := ""
	for line in head:
		if not line.begins_with("#"):
			break
		out += line + "\n"
	for file: String in _sorted(counts.keys()):
		out += budget_line(file, counts[file]) + "\n"
	return out


func _walk(dir: String, into: Array[String]) -> void:
	for file in DirAccess.get_files_at("res://" + dir):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			into.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at("res://" + dir):
		_walk(dir + "/" + sub, into)


func _exempt(file: String) -> bool:
	if file in EXEMPT_FILES:
		return true
	for dir in EXEMPT_DIRS:
		if file.begins_with(dir):
			return true
	return false


## The rule on lines made up for it, so a change to a pattern shows here.
func _counts_rule() -> bool:
	var cases := [
		["render/x.gd", "\tlabel.add_theme_color_override(\"font_color\", Color(1, 0, 0))", [1, 1, 0]],
		["render/x.gd", "\tbox.add_theme_constant_override(\"separation\", 8)  # add_theme_font_override(", [1, 0, 0]],
		["render/x.gd", "\tvar c := Color(\"#4a3a25\") + Color.WHITE + Color.html(s) + Color8(1, 2, 3)", [0, 4, 0]],
		["render/x.gd", "\tvar c := Color.TRANSPARENT; var d := Color(base, 0.5); var e := theme_color", [0, 0, 0]],
		["render/x.gd", "\tvar s := \"# not a comment\"; begin_bulk_theme_override()", [1, 0, 0]],
		["render/x.gd", "## add_theme_color_override(\"font_color\", Color.WHITE)", [0, 0, 0]],
		["client3d/x.gd", "\tl.add_theme_font_size_override(\"font_size\", 9); var c := Color(1, 1, 1)", [1, 0, 0]],
		["client3d/x.gd", "\tvar f := FontVariation.new(); load(\"res://art/fonts/x.ttf\")", [0, 0, 2]],
		["client3d/art_kit.gd", "\tvar f := load(\"res://art/fonts/carve.ttf\")", [0, 0, 0]],
		["main.tscn", "theme_override_font_sizes/font_size = 40", [1, 0, 0]],
	]
	var ok := true
	for case: Array in cases:
		var got := count_text(case[0], case[1])
		if got != case[2]:
			print("    %s: \"%s\" counts %s, not %s" % [case[0], case[1].strip_edges(), got, case[2]])
			ok = false
	ok = ok and _exempt("render/parts/ui_slot.gd") and _exempt("render/ui_theme.gd") and not _exempt("render/pack_panel.gd")
	return ok


static func _said(have: Array) -> String:
	return "%d overrides, %d colours, %d fonts" % have


func _sorted(keys: Array) -> Array[String]:
	keys.sort()
	var out: Array[String] = []
	for key: Variant in keys:
		out.append(str(key))
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
