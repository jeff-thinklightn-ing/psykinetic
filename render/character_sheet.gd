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
var title: Label
var figure: Figure
## The whole load against the body's mass, under the feet; the load's lines
## on hover (PackPanel.load_lines: the whole, the arms, the body).
var load_bar: LoadBar
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
## the hands, the armour and 788's worn slots (the first ring at the
## figure's right hand, the second at its left).
const SLOT_PLACES := {Items.RIGHT_HAND: "right", Items.LEFT_HAND: "left", Items.ARMOUR: "body",
	Items.HEAD: "head", Items.NECK: "neck", Items.BACK: "back", Items.FEET: "feet",
	Items.RING_1: "ring_right", Items.RING_2: "ring_left", Items.CHARM: "charm"}
## Each worn square's name, on hover while it is empty (voice's words).
const SLOT_WORDS := {Items.RIGHT_HAND: "Right hand", Items.LEFT_HAND: "Left hand", Items.ARMOUR: "Body",
	Items.HEAD: "Head", Items.NECK: "Neck", Items.BACK: "Shoulders", Items.FEET: "Feet",
	Items.RING_1: "Ring", Items.RING_2: "Ring", Items.CHARM: "Charm"}


## The load bar: filled to its share of BAR_TOP, brass while light or
## burdened, rust when heavy, alarm red overloaded; the bands' edges
## (World.load_free, load_heavy, load_overloaded) ticks under it.
class LoadBar:
	extends Control
	var share := 0.0

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
		for edge: float in [World.load_free, World.load_heavy, World.load_overloaded]:
			var x := inner.position.x + inner.size.x * edge / BAR_TOP
			draw_line(Vector2(x, whole.end.y + 2), Vector2(x, size.y), tick, 3.0)


## The figure: a body facing you, shaded from the light at your upper left
## (its lit side and top lighter, its far side and legs darker, a light rim
## along the lit edge), a cloak hanging behind its left shoulder (your
## right), a belt, hands at the ends of its arms with their fingers reaching
## to the ring squares, and each worn slot's square where that thing is worn.
## Places and the body are in slots (SLOT units), so the figure scales with
## the theme's slot; it stands at least four of the pack's rows tall, so a
## fourth row (a satchel, later) never changes the window's height.
class Figure:
	extends Control
	## Each place's square's top-left, in slots: x from your left, y down.
	## "right" is the figure's right hand (on your left).
	const PLACES := {
		"head": Vector2(1.7, 0.05),
		"neck": Vector2(1.7, 1.17), "back": Vector2(2.95, 1.0),
		"body": Vector2(1.7, 2.29),
		"right": Vector2(0.05, 2.95), "left": Vector2(3.35, 2.95),
		"charm": Vector2(1.7, 3.41),
		"ring_right": Vector2(0.05, 4.13), "ring_left": Vector2(3.35, 4.13),
		"feet": Vector2(1.7, 5.55),
	}
	## The figure's width and height, in slots.
	const WIDE := 4.45
	const TALL := 6.62
	## One side of the body's outline (your left), in slots from the middle
	## line: the neck, the shoulder's top and point, the armpit, the waist,
	## the hip, the knee, the ankle, the sole's outer and inner ends, the
	## inner ankle and knee, the fork; mirrored for the other.
	const SIDE: Array[Vector2] = [Vector2(-0.24, 1.0), Vector2(-0.42, 1.32), Vector2(-0.98, 1.46), Vector2(-0.94, 2.05),
		Vector2(-0.74, 3.25), Vector2(-0.84, 3.95), Vector2(-0.66, 5.15), Vector2(-0.52, 6.18), Vector2(-0.66, 6.6),
		Vector2(-0.12, 6.6), Vector2(-0.14, 6.18), Vector2(-0.16, 5.15), Vector2(0.0, 4.45)]
	const HEAD_RADIUS := 0.62
	## An arm: from the shoulder to the hand's square's top, its width.
	const ARM_FROM := Vector2(-0.84, 1.55)
	const ARM_WIDTH := 0.36
	## The belt's band, in slots down.
	const BELT_Y := Vector2(3.72, 3.94)
	var slot := 160.0

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

	## The shade at [param at]: lighter up and toward your left.
	func shade(at: Vector2) -> Color:
		var down := clampf(at.y / (TALL * slot), 0.0, 1.0)
		var across := clampf(0.5 + (at.x - middle()) / (WIDE * slot), 0.0, 1.0)
		var light := clampf(1.0 - down * 0.8 - across * 0.7, 0.0, 1.0)
		return CharacterSheet.FIGURE_SHADE.lerp(CharacterSheet.FIGURE_LIGHT, light)

	func _shaded(points: PackedVector2Array) -> void:
		var colours := PackedColorArray()
		for p: Vector2 in points:
			colours.append(shade(p))
		draw_polygon(points, colours)

	func _edge(points: PackedVector2Array, width: float) -> void:
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, CharacterSheet.FIGURE_EDGE, width, true)

	func _draw() -> void:
		var cx := middle()
		var line := maxf(2.0, slot / 60.0)
		# The cloak first, behind everything: from the left shoulder (your
		# right) down behind the arm to the knee.
		var cloak := PackedVector2Array([Vector2(cx + 0.3 * slot, 1.3 * slot), Vector2(cx + 1.25 * slot, 1.42 * slot),
			Vector2(cx + 1.4 * slot, 5.0 * slot), Vector2(cx + 0.55 * slot, 5.25 * slot)])
		draw_colored_polygon(cloak, CharacterSheet.CLOAK)
		_edge(cloak, line * 0.75)
		# The arms, the torso drawn over their tops; a hand at each end, its
		# fingers reaching down to the ring's square.
		for side: float in [-1.0, 1.0]:
			var hand := place_at("right" if side < 0 else "left")
			var from := Vector2(cx + side * absf(ARM_FROM.x) * slot, ARM_FROM.y * slot)
			var to := Vector2(hand.x + slot / 2, hand.y + slot * 0.15)
			var across := (to - from).orthogonal().normalized() * ARM_WIDTH * slot / 2
			var arm := PackedVector2Array([from - across, from + across, to + across * 0.8, to - across * 0.8])
			_shaded(arm)
			_edge(arm, line)
			var palm := Rect2(hand.x + slot * 0.2, hand.y + slot * 0.55, slot * 0.6, slot * 0.75)
			var fingers := PackedVector2Array([palm.position, Vector2(palm.end.x, palm.position.y),
				Vector2(palm.end.x - slot * 0.06, palm.end.y), Vector2(palm.position.x + slot * 0.06, palm.end.y)])
			_shaded(fingers)
			_edge(fingers, line)
		var body := outline()
		_shaded(body)
		# The belt across the waist (the charm hangs at its buckle).
		var belt := Geometry2D.intersect_polygons(body, PackedVector2Array([Vector2(0, BELT_Y.x * slot),
			Vector2(size.x, BELT_Y.x * slot), Vector2(size.x, BELT_Y.y * slot), Vector2(0, BELT_Y.y * slot)]))
		for part: PackedVector2Array in belt:
			draw_colored_polygon(part, CharacterSheet.BELT)
		_edge(body, line)
		# The light along the lit edge: the head's upper left and the body's
		# left side from the shoulder to the knee.
		var lit := PackedVector2Array()
		for i in range(1, 7):
			lit.append(body[i] + Vector2(line * 1.5, 0))
		draw_polyline(lit, CharacterSheet.FIGURE_RIM, line, true)
		var head := Vector2(cx, place_at("head").y + slot / 2)
		var face := PackedVector2Array()
		for i in 48:
			face.append(head + Vector2.from_angle(TAU * i / 48.0) * HEAD_RADIUS * slot)
		_shaded(face)
		_edge(face, line)
		draw_arc(head, HEAD_RADIUS * slot - line * 1.5, PI * 1.05, PI * 1.6, 16, CharacterSheet.FIGURE_RIM, line, true)


func _init() -> void:
	name = "CharacterSheet"
	add_theme_constant_override("separation", UiTheme.constant("row"))
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## Made by [param owner_pack]: the title, the figure, its squares (the
## pack's SlotBoxes for SLOT_PLACES, the pack's size) and the bar.
func build(owner_pack: PackPanel) -> void:
	pack = owner_pack
	title = Label.new()
	title.theme_type_variation = &"Heading"
	add_child(title)
	var slot := PackPanel.SLOT_SIZE.x
	figure = Figure.new(slot)
	add_child(figure)
	for i: int in SLOT_PLACES:
		var box := pack._box(true, i, true)
		box.custom_minimum_size = PackPanel.SLOT_SIZE
		box.size = box.custom_minimum_size
		box.position = figure.place_at(SLOT_PLACES[i])
		box.tooltip_text = SLOT_WORDS[i]
		figure.add_child(box)
		boxes[i] = box
	load_bar = LoadBar.new()
	load_bar.custom_minimum_size = Vector2(figure.custom_minimum_size.x, 36 * slot / MOCK_SLOT)
	add_child(load_bar)


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
	title.text = name_of(who)
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
