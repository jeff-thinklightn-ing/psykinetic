class_name CharacterSheet
extends VBoxContainer
## The character sheet (decision 787; Jeff: "create a character inventory
## sheet and move hands and armor there"; the coordinator's approval of
## C:/dev/review/ui/character_sheet; the sheet pass, Jeff: "keep
## iterating"): the left side of the pack's window, the player's name over a
## shaded figure facing you with each worn square at its place on the body
## (the hat on the head, the amulet at the throat, the cloak behind the
## shoulder, the armour on the body, the hands at the ends of the arms, a
## ring at each hand's fingers, the charm at the belt, the boots at the
## feet; Figure), each empty square's name on hover (voice's SLOT_WORDS), and
## the load as one bar under the feet, its words on hover. The squares are
## the pack's own SlotBoxes for the worn slots, the pack's size (PackPanel
## makes and fills them), so a drag, a right click, a double click, the
## store's prices and the practice bars work on them as in the pack.

## The slot the bar's height is drawn for (the theme's slot at 3840 x 2160).
const MOCK_SLOT := 160.0
## The load bar's scale: full at this share of what carries the load.
const BAR_TOP := 0.75
## The figure's palette, the panel's browns: its lit and its shaded side,
## its edge and the light along its lit edge, the cloak behind it, the belt.
const FIGURE_LIGHT := Color("6e5b42")
const FIGURE_FILL := Color("4e4131")
const FIGURE_SHADE := Color("31281e")
const FIGURE_EDGE := Color("85745a")
const FIGURE_RIM := Color("a8916c")
const CLOAK := Color("2c2a33")
const BELT := Color("2a2118")

var pack: PackPanel
## The heading over the figure and its worn squares (787 amended (4), voice's).
const GEAR_WORDS := "Gear"
## The word beside the weight meter (pack-1080; voice reads it, 787 amended (6)).
const LOAD_WORDS := "Load"
var title: Label
## The worn squares, GEAR_COLUMNS a line, head to feet (the mock: no figure).
var grid: GridContainer
## The whole load against the body's mass, under the feet; the load's lines
## on hover (PackPanel.load_lines: the whole, the arms, the body).
var load_bar: LoadBar
## The meter's name beside it.
var load_word: Label
## The squares, by slot.
var boxes: Dictionary[int, PackPanel.SlotBox] = {}
## The sheet's two modes (Jeff, via the coordinator: a companion has the
## same worn slots; one companion's are yours to change, every other's only
## to look at): false, editable (drag, equip, as the pack); true, read-only
## (no drag from or onto a square, no click's equip or use; the tips show).
## The player's own is always editable; which companion opens which way is
## companions' design.
var read_only := false:
	set(value):
		read_only = value
		for box: PackPanel.SlotBox in boxes.values():
			box.read_only = value
## Each slot the sheet shows, in reading order, four to a line (the approved pack window: Head, Neck,
## Shoulders, Body / Right hand, Left hand, Ring, Ring / Charm, Feet, Satchel); the dictionary's values name the
## place (a hover name's key).
const GEAR_COLUMNS := 4
const SLOT_PLACES := {Items.HEAD: "head", Items.NECK: "neck", Items.BACK: "back", Items.ARMOUR: "body",
	Items.RIGHT_HAND: "right", Items.LEFT_HAND: "left", Items.RING_1: "ring_right", Items.RING_2: "ring_left",
	Items.CHARM: "charm", Items.FEET: "feet", Items.BAG: "bag"}
## Each worn square's name, on hover while it is empty (voice's words).
const SLOT_WORDS := {Items.RIGHT_HAND: "Right hand", Items.LEFT_HAND: "Left hand", Items.ARMOUR: "Body",
	Items.HEAD: "Head", Items.NECK: "Neck", Items.BACK: "Shoulders", Items.FEET: "Feet",
	Items.RING_1: "Ring", Items.RING_2: "Ring", Items.CHARM: "Charm", Items.BAG: "Satchel"}


## The load bar: filled to its share of BAR_TOP, brass while light or
## burdened, rust when heavy, alarm red overloaded; the bands' edges
## (World.load_free, load_heavy, load_overloaded) ticks under it.
class LoadBar:
	extends Control
	var share := 0.0
	## The band edges drawn under the bar (the sheet's); the store window's bar has none (its mock).
	var ticks := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP  # For its hover words.

	func _draw() -> void:
		var whole := Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.7))
		draw_rect(whole, Color(0.1, 0.08, 0.06, 0.85))
		var inner := whole.grow(-3)
		var fill := clampf(share, 0.0, BAR_TOP) / BAR_TOP
		if fill > 0.0:
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * fill, inner.size.y)), CharacterSheet.band_color(share))
		draw_rect(whole, CharacterSheet.FIGURE_EDGE, false, 2.0)
		var tick := UiTheme.color("text_dim")
		for edge: float in ([World.load_free, World.load_heavy, World.load_overloaded] if ticks else []):
			var x := inner.position.x + inner.size.x * edge / BAR_TOP
			draw_line(Vector2(x, whole.end.y + 2), Vector2(x, size.y), tick, 3.0)


func _init() -> void:
	name = "CharacterSheet"
	add_theme_constant_override("separation", UiTheme.constant("row"))
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## Made by [param owner_pack]: the title, the figure, its squares (the
## pack's SlotBoxes for SLOT_PLACES, the pack's size) and the bar.
func build(owner_pack: PackPanel) -> void:
	pack = owner_pack
	title = Label.new()
	title.theme_type_variation = &"Title"
	add_child(title)
	grid = GridContainer.new()
	grid.columns = GEAR_COLUMNS
	grid.theme_type_variation = &"Squares"
	add_child(grid)
	for i: int in SLOT_PLACES:
		var box := pack._box(true, i, i in [Items.RIGHT_HAND, Items.LEFT_HAND])
		box.tooltip_text = SLOT_WORDS[i]
		grid.add_child(box)
		boxes[i] = box
	var load_row := HBoxContainer.new()  # "Load" beside the meter (pack-1080).
	add_child(load_row)
	load_word = Label.new()
	load_word.theme_type_variation = &"Caption"
	load_word.text = LOAD_WORDS
	load_word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	load_row.add_child(load_word)
	load_bar = LoadBar.new()
	load_bar.custom_minimum_size = Vector2(0, 36 * PackPanel.SLOT_SIZE.x / MOCK_SLOT)
	load_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(load_bar)


## A load's band colour by its share (decision 676's bands).
static func band_color(share: float) -> Color:
	if share >= World.load_overloaded:
		return UiTheme.color("alarm")
	if share >= World.load_heavy:
		return UiTheme.color("rust")
	return UiTheme.color("brass")


## Shows [param who]'s name and load, and names each empty square on hover
## (a filled one shows its thing's tip); the squares are filled by the pack.
## [param lines] are PackPanel.load_lines(who): the whole, then the parts.
func show_for(who: GridEntity, lines: PackedStringArray) -> void:
	title.text = GEAR_WORDS  # 787 amended (4): what you wear is headed Gear (voice), the carried squares Pack.
	var capacity := World.load_capacity(who) if who != null else 1.0
	var whole := (who.load_arms + who.load_body) / maxf(capacity, 0.001) if who != null else 0.0
	var words := "\n".join(lines)
	if load_bar.share != whole or load_bar.tooltip_text != words:
		load_bar.share = whole
		load_bar.tooltip_text = words
		load_bar.queue_redraw()
	for i: int in boxes:
		var empty := who == null or i >= who.slots.size() or who.slots[i].is_empty()
		boxes[i].tooltip_text = str(SLOT_WORDS[i]) if empty else ""


## The sheet's heading: the player's name.
static func name_of(who: GridEntity) -> String:
	if who == null:
		return ""
	return who.label if not who.label.is_empty() else String(who.name)


## The bar as shown (tests): [share, words].
func load_shown() -> Array:
	return [load_bar.share, load_bar.tooltip_text]
