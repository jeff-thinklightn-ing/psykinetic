class_name UiTheme
extends RefCounted
## The shared look of every screen (docs/ui_style.md): the project theme,
## render/ui_theme.tres, which every Control inherits. Panels use its
## types and named variations (Title, Heading, Caption, Small, Name,
## Outlined, Inset, HandSlot, Deep) and set no fonts, sizes or colours of
## their own (Hud is the HUD's one line over the world). What is drawn by hand (the compass, the maps, the speech
## bubbles) reads the theme's named colours, fonts, sizes and constants
## from here, so the .tres is the one source of truth.
##
## Colours (type Psykinetic): backing, backing_deep, edge, text, text_dim,
## brass, brass_bright, rust, alarm, party, aloud, friend, water, outline.
## Fonts: serif, serif_bold, sans, sans_bold. Sizes: title, heading, hud,
## body, caption, small, speech. Constants: unit, pad, row, section, slot,
## slot_gap, radius, margin, outline.

const PATH := "res://render/ui_theme.tres"
const TYPE := &"Psykinetic"
## The theme types whose font sizes the text scale multiplies (decision 453).
const SIZED_TYPES: Array[StringName] = [&"Title", &"Heading", &"Hud", &"Caption", &"Small", &"Display", &"TooltipLabel"]
## The meaning colours and their sets: "normal" is the palette's (docs/ui_style.md);
## "distinct" keeps brass and rust, and moves the rest apart for red-green
## colour blindness (friend blue, party pale cyan, alarm magenta: each a
## different lightness as well as hue, so a simulation keeps them apart).
const COLOUR_SETS := {
	"normal": {"friend": "#8fa857", "party": "#3fb8a8", "alarm": "#b8322a", "rust": "#e8792e"},
	"distinct": {"friend": "#7ab8ec", "party": "#c8ecfa", "alarm": "#9c1f5f", "rust": "#e8792e"},
}

static var _theme: Theme
## Every sized theme item's base size, as the .tres has it: [type, name] -> size.
static var _base_sizes: Dictionary = {}
static var _base_default_size := 0
static var text_scale := 1.0
static var colour_set := "normal"


## The project theme, loaded from PATH where the project has none (tests
## running a scene without the project settings).
static func theme() -> Theme:
	if _theme == null:
		_theme = ThemeDB.get_project_theme()
		if _theme == null:
			_theme = load(PATH)
	return _theme


static func color(name: StringName) -> Color:
	var found := theme()
	if found == null or not found.has_color(name, TYPE):
		push_warning("[ui] no colour %s in the theme" % name)
		return Color.MAGENTA
	return found.get_color(name, TYPE)


static func font(name: StringName) -> Font:
	var found := theme()
	if found == null or not found.has_font(name, TYPE):
		return ThemeDB.fallback_font
	return found.get_font(name, TYPE)


static func size(name: StringName) -> int:
	var found := theme()
	if found == null or not found.has_font_size(name, TYPE):
		return ThemeDB.fallback_font_size
	return found.get_font_size(name, TYPE)


static func constant(name: StringName) -> int:
	var found := theme()
	if found == null or not found.has_constant(name, TYPE):
		push_warning("[ui] no constant %s in the theme" % name)
		return 0
	return found.get_constant(name, TYPE)


## The fonts' credit, for the Options' Credits section (sound's provider
## hook, decision 406 amended): {summary, entries: [{title, by, license, url}]}.
static func credits() -> Dictionary:
	return {"summary": "Fonts: Alegreya and Alegreya Sans by Huerta Tipografica (SIL Open Font License 1.1)",
		"entries": [
			{"title": "Alegreya", "by": "Juan Pablo del Peral, Huerta Tipografica", "license": "SIL Open Font License 1.1",
				"url": "https://github.com/huertatipografica/Alegreya"},
			{"title": "Alegreya Sans", "by": "Juan Pablo del Peral, Huerta Tipografica", "license": "SIL Open Font License 1.1",
				"url": "https://github.com/huertatipografica/Alegreya-Sans"}]}


## A colour swatch's box for a Button (pc-character's hair and skin choices):
## the colour itself, edged in brass when [param chosen], else in the edge.
static func swatch_style(colour: Color, chosen: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(constant("radius"))
	box.set_border_width_all(3 if chosen else 2)
	box.border_color = color("brass_bright") if chosen else color("edge")
	return box


## The theme's font sizes multiplied by [param k] (1.0 the .tres's own):
## the default size, the sized variations and the Psykinetic sizes, so
## every label on the theme and everything reading UiTheme.size follows.
## A size a class kept in a static var at load follows at the next start.
static func apply_text_scale(k: float) -> void:
	var found := theme()
	if found == null:
		return
	if _base_sizes.is_empty():
		_base_default_size = found.default_font_size
		for type in SIZED_TYPES:
			if found.has_font_size("font_size", type):
				_base_sizes[[type, &"font_size"]] = found.get_font_size("font_size", type)
		for name in found.get_font_size_list(TYPE):
			_base_sizes[[TYPE, name]] = found.get_font_size(name, TYPE)
		for name in found.get_font_size_list(&"RichTextLabel"):
			_base_sizes[[&"RichTextLabel", name]] = found.get_font_size(name, &"RichTextLabel")
	text_scale = clampf(k, 0.5, 2.0)
	found.default_font_size = roundi(_base_default_size * text_scale)
	for key: Array in _base_sizes:
		found.set_font_size(key[1], key[0], roundi(int(_base_sizes[key]) * text_scale))


## The meaning colours set to [param name]'s set (COLOUR_SETS; "normal" the
## palette's). Applied at start by Net from colours=, before the panels
## load: a change in the Options shows from the next start.
static func apply_colours(name: String) -> void:
	var found := theme()
	if found == null or not COLOUR_SETS.has(name):
		return
	colour_set = name
	var set: Dictionary = COLOUR_SETS[name]
	for key: String in set:
		var was := found.get_color(key, TYPE) if found.has_color(key, TYPE) else Color.WHITE
		found.set_color(key, TYPE, Color(Color.html(set[key]), was.a))


## A type's stylebox, for a control that draws one by hand: style("panel", "Inset").
static func style(name: StringName, type: StringName) -> StyleBox:
	var found := theme()
	if found == null or not found.has_stylebox(name, type):
		return StyleBoxEmpty.new()
	return found.get_stylebox(name, type)
