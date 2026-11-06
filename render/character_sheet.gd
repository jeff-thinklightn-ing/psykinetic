class_name CharacterSheet
extends PanelContainer
## The character sheet (decision 787; Jeff: "create a character inventory
## sheet and move hands and armor there"; the coordinator's approval of
## C:/dev/review/ui/character_sheet): the player's hands, armour and worn
## things (788) on a filled figure facing you, each square where it is worn
## (R in its right hand, on your left; L in its left; A on the chest; the
## hat on the head, the boots at the feet; Figure), and the load drawn as
## two bars under it, no words but on hover. It shows beside the pack, its
## foot on the pack's, whenever the pack shows (I, a chest, a store, a
## companion), so a drag between a hand and the pack crosses one gap. The
## squares are the pack's own SlotBoxes for the worn slots (PackPanel makes
## and fills them), so a drag, a right click, a double click, the store's
## prices and the practice bars work on them as they did in the pack.

## The slot the bars' sizes are drawn for (the theme's own, 132).
const MOCK_SLOT := 132.0
## The load bars' scale: full at this share of what carries the load.
const BAR_TOP := 0.75
const FIGURE_FILL := Color("4e4131")
const FIGURE_EDGE := Color("85745a")
## The sheet's squares, a share of the pack's, centred on their places, so
## the body shows round them.
const SQUARE := 0.84

var pack: PackPanel
var title: Label
var figure: Figure
## The whole load against the body's mass (the upper bar under the figure).
var body_bar: LoadBar
## The arms' load against their share of it (the lower bar).
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
## Each slot the sheet shows and its place on the figure (Figure.PLACES):
## the hands, the armour and 788's worn slots (the first ring on the
## figure's right hand, the second on its left).
const SLOT_PLACES := {Items.RIGHT_HAND: "right", Items.LEFT_HAND: "left", Items.ARMOUR: "body",
	Items.HEAD: "head", Items.NECK: "neck", Items.BACK: "back", Items.FEET: "feet",
	Items.RING_1: "ring_right", Items.RING_2: "ring_left", Items.CHARM: "charm"}


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


## The figure: a filled body facing you (Jeff, for v0.1.205: "the
## hilariously long neck on the stick man"), a head on its shoulders, a
## torso, arms and legs, and each worn slot's square where that thing is
## worn: the hat on the head, the amulet at the throat, the cloak on its
## left shoulder (your right), the chest's armour on the torso, the hands at
## the ends of the arms, a ring under each hand, the charm at the belt and
## the boots at the feet (788's slots). An empty square still shows its
## outline, so the figure reads as a body wearing nothing. Places and the
## body are in slots (SLOT units), so the figure scales with the theme's slot.
class Figure:
	extends Control
	## Each place's square's top-left, in slots: x from your left, y down.
	## "right" is the figure's right hand (on your left).
	const PLACES := {
		"head": Vector2(1.22, 0.0),
		"neck": Vector2(1.22, 1.2), "back": Vector2(2.44, 1.2),
		"body": Vector2(1.22, 2.4),
		"right": Vector2(0.0, 2.9), "left": Vector2(2.44, 2.9),
		"charm": Vector2(1.22, 3.6),
		"ring_right": Vector2(0.0, 4.1), "ring_left": Vector2(2.44, 4.1),
		"feet": Vector2(1.22, 5.0),
	}
	## The figure's width and height, in slots.
	const WIDE := 3.44
	const TALL := 6.0
	## One side of the body's outline (your left), in slots from the middle
	## line: neck, shoulder, armpit, waist, hip, knee, ankle, the sole's
	## outer and inner ends, the inner knee, the fork; mirrored for the other.
	const SIDE: Array[Vector2] = [Vector2(-0.24, 1.08), Vector2(-0.26, 1.3), Vector2(-0.86, 1.4), Vector2(-1.02, 1.62),
		Vector2(-0.84, 2.3), Vector2(-0.64, 3.5), Vector2(-0.76, 4.25), Vector2(-0.7, 5.0), Vector2(-0.62, 5.82),
		Vector2(-0.66, 5.96), Vector2(-0.12, 5.96), Vector2(-0.12, 5.0), Vector2(0.0, 4.55)]
	const HEAD_RADIUS := 0.6
	## An arm: shoulder to wrist (the hand's square's top), its width.
	const ARM_FROM := Vector2(-0.96, 1.62)
	const ARM_WIDTH := 0.3
	var slot := 132.0

	func _init(slot_size: float) -> void:
		slot = slot_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(WIDE, TALL) * slot

	## The top-left of [param place]'s square.
	func place_at(place: String) -> Vector2:
		return (PLACES[place] as Vector2) * slot

	## The middle line's x, in pixels.
	func middle() -> float:
		return place_at("body").x + slot / 2

	## The body's outline, in pixels: SIDE, then SIDE mirrored back up.
	func outline() -> PackedVector2Array:
		var cx := middle()
		var out := PackedVector2Array()
		for p: Vector2 in SIDE:
			out.append(Vector2(cx + p.x * slot, p.y * slot))
		for i in range(SIDE.size() - 2, -1, -1):
			out.append(Vector2(cx - SIDE[i].x * slot, SIDE[i].y * slot))
		return out

	func _draw() -> void:
		var cx := middle()
		var fill := CharacterSheet.FIGURE_FILL
		var edge := CharacterSheet.FIGURE_EDGE
		var line := maxf(2.0, slot / 60.0)
		# The arms first, the torso drawn over their tops.
		for side: float in [-1.0, 1.0]:
			var hand := place_at("right" if side < 0 else "left")
			var from := Vector2(cx + side * absf(ARM_FROM.x) * slot, ARM_FROM.y * slot)
			var to := Vector2(hand.x + slot / 2, hand.y + slot * 0.1)
			var across := (to - from).orthogonal().normalized() * ARM_WIDTH * slot / 2
			var arm := PackedVector2Array([from - across, from + across, to + across * 0.8, to - across * 0.8])
			draw_colored_polygon(arm, fill)
			draw_polyline(PackedVector2Array([arm[0], arm[3], arm[2], arm[1]]), edge, line)
		var body := outline()
		draw_colored_polygon(body, fill)
		var closed := body.duplicate()
		closed.append(body[0])
		draw_polyline(closed, edge, line)
		var head := Vector2(cx, place_at("head").y + slot / 2)
		draw_circle(head, HEAD_RADIUS * slot, fill)
		draw_arc(head, HEAD_RADIUS * slot, 0, TAU, 64, edge, line)


func _init() -> void:
	name = "CharacterSheet"
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	visible = false


## Made by [param owner_pack]: the title, the figure, its squares (the
## pack's SlotBoxes for SLOT_PLACES) and the two bars.
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
		box.custom_minimum_size = PackPanel.SLOT_SIZE * SQUARE
		box.size = box.custom_minimum_size
		box.position = figure.place_at(SLOT_PLACES[i]) + PackPanel.SLOT_SIZE * (1.0 - SQUARE) / 2
		figure.add_child(box)
		boxes[i] = box
	# The two load bars under the feet, the figure's width: the whole load,
	# then the arms' (their band ticks below each).
	var k := slot / MOCK_SLOT
	body_bar = LoadBar.new(false)
	body_bar.custom_minimum_size = Vector2(figure.custom_minimum_size.x, 20 * k)
	column.add_child(body_bar)
	arms_bar = LoadBar.new(false)
	arms_bar.custom_minimum_size = Vector2(figure.custom_minimum_size.x, 14 * k)
	column.add_child(arms_bar)
	add_theme_stylebox_override("panel", PackPanel.solid_panel())


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
