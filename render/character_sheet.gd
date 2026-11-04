class_name CharacterSheet
extends PanelContainer
## The character sheet (decision 787; Jeff: "create a character inventory
## sheet and move hands and armor there"; the coordinator's approval of
## C:/dev/review/ui/character_sheet): the player's hands and armour on a
## plain figure facing you, where they are worn (R in its right hand, on
## your left; L in its left; A on the chest), and the load drawn as two
## bars, no words but on hover. It shows beside the pack, its foot on the
## pack's, whenever the pack shows (I, a chest, a store, a companion), so a
## drag between a hand and the pack crosses one gap. The squares are the
## pack's own SlotBoxes for slots 4, 5 and 6 (PackPanel makes and fills
## them), so a drag, a right click, a double click, the store's prices and
## the practice bars work on them as they did in the pack.

## The figure's proportions, as drawn in the mock at a slot of 132.
const MOCK_SLOT := 132.0
## The load bars' scale: full at this share of what carries the load.
const BAR_TOP := 0.75
const FIGURE_FILL := Color("3d3226")
const FIGURE_EDGE := Color("5c4f3c")

var pack: PackPanel
var title: Label
var figure: Figure
## The whole load against the body's mass (the tall bar on the right).
var body_bar: LoadBar
## The arms' load against their share of it (the short bar under the chest).
var arms_bar: LoadBar
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
## Each slot the sheet shows and its place on the figure (Figure.PLACES).
## A worn slot the server gains later (items' proposal: head 11, neck 12,
## back 13, feet 14, rings 15 and 16, the charm 17) is one line here.
const SLOT_PLACES := {Items.RIGHT_HAND: "right", Items.LEFT_HAND: "left", Items.ARMOUR: "body"}


## A load bar: filled to its share of BAR_TOP, brass while light or
## burdened, rust when heavy, alarm red overloaded; the bands' edges
## (World.load_free, load_heavy, load_overloaded) faint ticks beside it.
class LoadBar:
	extends Control
	var share := 0.0
	var vertical := false

	func _init(upright: bool) -> void:
		vertical = upright
		mouse_filter = Control.MOUSE_FILTER_STOP  # For its hover words.

	func _draw() -> void:
		var whole := Rect2(Vector2.ZERO, size)
		draw_rect(whole, Color(0.1, 0.08, 0.06, 0.85))
		draw_rect(whole, CharacterSheet.FIGURE_EDGE, false, 1.0)
		var inner := whole.grow(-3)
		var fill := clampf(share, 0.0, BAR_TOP) / BAR_TOP
		if fill > 0.0:
			var part := Rect2(inner.position.x, inner.end.y - inner.size.y * fill, inner.size.x, inner.size.y * fill) if vertical \
				else Rect2(inner.position, Vector2(inner.size.x * fill, inner.size.y))
			draw_rect(part, CharacterSheet.band_color(share))
		var tick := UiTheme.color("text_dim")
		for edge: float in [World.load_free, World.load_heavy, World.load_overloaded]:
			var at := edge / BAR_TOP
			if vertical:
				var y := inner.end.y - inner.size.y * at
				draw_line(Vector2(-5, y), Vector2(-1, y), tick, 2.0)
			else:
				var x := inner.position.x + inner.size.x * at
				draw_line(Vector2(x, size.y + 1), Vector2(x, size.y + 5), tick, 2.0)


## The figure: a faint outline facing you on a fixed grid of places, three
## columns by four rows, each a square where that thing is worn (Jeff,
## 2026-11-03: "the other item slots like the hat, the boots, jewelry"; the
## coordinator: lay it out so they drop in without a redraw). Only places
## whose slots exist get a square (CharacterSheet.SLOT_PLACES); the rest
## show the outline. The arms reach down to the hand squares, so R and L
## read as held (the coordinator's note on the mock).
class Figure:
	extends Control
	## Each place's cell: column (0 your left, 1 the middle, 2 your right),
	## row (0 the head's, 4 the feet's). "right" is the figure's right hand.
	## Items' proposed worn slots (head 11, neck 12, back 13, feet 14, rings
	## 15 and 16): the head at the top, the neck below it, the back beside
	## the body, the feet at the bottom, a ring under each hand; the charm
	## (17; Jeff: "charms don't go in the hands. Charm slot.") at the belt.
	const PLACES := {
		"head": Vector2i(1, 0),
		"neck": Vector2i(1, 1),
		"body": Vector2i(1, 2), "back": Vector2i(2, 2),
		"right": Vector2i(0, 3), "charm": Vector2i(1, 3), "left": Vector2i(2, 3),
		"ring_right": Vector2i(0, 4), "feet": Vector2i(1, 4), "ring_left": Vector2i(2, 4),
	}
	var k := 1.0
	var slot := 132.0
	var column_gap := 30.0
	var row_gap := 34.0

	func _init(slot_size: float) -> void:
		slot = slot_size
		k = slot / CharacterSheet.MOCK_SLOT
		column_gap = 30 * k
		row_gap = 34 * k
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(3 * slot + 2 * column_gap + 26 * k + 22 * k, 5 * slot + 4 * row_gap)

	## The top-left of [param place]'s square.
	func place_at(place: String) -> Vector2:
		var cell: Vector2i = PLACES[place]
		return Vector2(cell.x * (slot + column_gap), cell.y * (slot + row_gap))

	func _draw() -> void:
		var cx := place_at("body").x + slot / 2
		var head := place_at("head") + Vector2(slot / 2, slot / 2)
		var chest := place_at("body").y
		var foot := place_at("feet").y + slot - 6 * k
		var hip := place_at("right").y + slot / 2
		var fill := CharacterSheet.FIGURE_FILL
		var edge_colour := CharacterSheet.FIGURE_EDGE
		draw_circle(head, 46 * k, fill)
		draw_arc(head, 46 * k, 0, TAU, 48, edge_colour, 2.0)
		draw_rect(Rect2(cx - 16 * k, head.y + 40 * k, 32 * k, chest - head.y - 40 * k), fill)
		var body := PackedVector2Array([Vector2(cx - 74 * k, chest - 10 * k), Vector2(cx + 74 * k, chest - 10 * k),
			Vector2(cx + 60 * k, hip), Vector2(cx + 50 * k, foot), Vector2(cx + 12 * k, foot),
			Vector2(cx, hip + 40 * k), Vector2(cx - 12 * k, foot), Vector2(cx - 50 * k, foot),
			Vector2(cx - 60 * k, hip)])
		draw_colored_polygon(body, fill)
		var edge := body.duplicate()
		edge.append(body[0])
		draw_polyline(edge, edge_colour, 2.0)
		for side: float in [-1.0, 1.0]:
			var hand := place_at("right" if side < 0 else "left")
			draw_line(Vector2(cx + side * 70 * k, chest), Vector2(hand.x + slot / 2, hand.y + 4 * k), edge_colour, 16 * k)


func _init() -> void:
	name = "CharacterSheet"
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	visible = false


## Made by [param owner_pack]: the title, the figure, the three squares (its
## own SlotBoxes) and the two bars.
func build(owner_pack: PackPanel) -> void:
	pack = owner_pack
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	title = Label.new()
	title.theme_type_variation = &"Heading"
	column.add_child(title)
	var slot := PackPanel.SLOT_SIZE.x
	figure = Figure.new(slot)
	column.add_child(figure)
	for i: int in SLOT_PLACES:
		var box := pack._box(true, i, true)
		box.position = figure.place_at(SLOT_PLACES[i])
		figure.add_child(box)
		boxes[i] = box
	var k := figure.k
	# The arms' bar in the gap under the chest's square.
	var chest := figure.place_at("body")
	arms_bar = LoadBar.new(false)
	arms_bar.position = Vector2(chest.x, chest.y + slot + 9 * k)
	arms_bar.size = Vector2(slot, 16 * k)
	figure.add_child(arms_bar)
	body_bar = LoadBar.new(true)
	body_bar.position = Vector2(figure.custom_minimum_size.x - 22 * k, 10 * k)
	body_bar.size = Vector2(22 * k, figure.custom_minimum_size.y - 10 * k)
	figure.add_child(body_bar)


## A load's band colour by its share (decision 676's bands).
static func band_color(share: float) -> Color:
	if share >= World.load_overloaded:
		return UiTheme.color("alarm")
	if share >= World.load_heavy:
		return UiTheme.color("rust")
	return UiTheme.color("brass")


## Shows [param who]'s name and load; the squares are filled by the pack.
## [param lines] are PackPanel.load_lines(who): the whole, then the parts.
func show_for(who: GridEntity, lines: PackedStringArray) -> void:
	title.text = name_of(who)
	var capacity := World.load_capacity(who) if who != null else 1.0
	var arms := who.load_arms if who != null else 0.0
	var body := who.load_body if who != null else 0.0
	var whole := (arms + body) / maxf(capacity, 0.001)
	var held := arms / maxf(capacity * World.ARMS_SHARE, 0.001)
	var arms_words := ""
	var body_words := PackedStringArray()
	for line: String in lines:
		if line.begins_with("arms "):
			arms_words = line
		else:
			body_words.append(line)
	if body_bar.share != whole or body_bar.tooltip_text != "\n".join(body_words):
		body_bar.share = whole
		body_bar.tooltip_text = "\n".join(body_words)
		body_bar.queue_redraw()
	if arms_bar.share != held or arms_bar.tooltip_text != arms_words:
		arms_bar.share = held
		arms_bar.tooltip_text = arms_words
		arms_bar.queue_redraw()


## The sheet's heading: the player's name.
static func name_of(who: GridEntity) -> String:
	if who == null:
		return ""
	return who.label if not who.label.is_empty() else String(who.name)


## [param beside]'s left, its foot level with the pack's.
func place_beside(beside: Control) -> void:
	var right := beside.offset_right - beside.size.x - UiTheme.constant("slot_gap") * 4
	var least := get_combined_minimum_size()
	if offset_right != right or offset_bottom != beside.offset_bottom or offset_right - offset_left != least.x:
		offset_right = right
		offset_left = right - least.x
		offset_bottom = beside.offset_bottom
		offset_top = beside.offset_bottom - least.y


## The bars as shown (tests): [body share, arms share, body words, arms words].
func load_shown() -> Array:
	return [body_bar.share, arms_bar.share, body_bar.tooltip_text, arms_bar.tooltip_text]
