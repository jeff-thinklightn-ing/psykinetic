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

static var _theme: Theme


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


## A type's stylebox, for a control that draws one by hand: style("panel", "Inset").
static func style(name: StringName, type: StringName) -> StyleBox:
	var found := theme()
	if found == null or not found.has_stylebox(name, type):
		return StyleBoxEmpty.new()
	return found.get_stylebox(name, type)
