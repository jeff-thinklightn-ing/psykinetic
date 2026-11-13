class_name UiSlot
extends PanelContainer
## A square (decision 854; the store Jeff approved, 11-10, and its services):
## a thing's picture large on the light cloth ground, its count top left, a
## chip bottom right (UiPrice: a price, a price in kind, or the time left on
## work in hand), a work's mark top right (a dark disc: this keeper works on
## it, or this square is that work; never a number) and a material chip bottom
## left (what a work spends besides gold). Its state is its rim (the theme's
## Well types): rest, hover, picked (brass), new (flame: just arrived),
## refused (rust, for REFUSED_SECONDS, then back), ready (flame with its lit
## corner: one click collects), in_hand (the picture faded) and hand (a held
## hand's square on the character sheet: a thinner, softer brass rim than
## picked's, 854 amended (6); a hover goes back to it, as to rest). Never greyed:
## a square that can't be used shows nothing to use. The window's script says
## what a click does; the square only reports it (pressed).
## An empty square may show what goes there (set_empty_picture, 854 amended (7);
## the pack mock's worn squares without the figure): the picture grey and faint
## (the theme's slot_empty), under the thing's own and shown only while it has none.

signal pressed(slot: UiSlot)

const STATES := {"rest": &"Well", "hover": &"WellHover", "picked": &"WellPicked", "new": &"WellNew",
	"refused": &"WellRefused", "ready": &"WellNew", "in_hand": &"Well", "hand": &"WellHand"}
## The states a hover lights and goes back to (854 amended (6)).
const RESTING: Array[String] = ["rest", "hand"]
const REFUSED_SECONDS := 1.0
## How far the chips and the mark sit in from the square's edge, inside its margin.
const INSET := -8.0
## A faded picture's strength (work in hand).
const FADED := 0.45
const CORNER := 40.0
const MARK := 52.0
## A stock level's bar up the left edge (854 amended (2)): its width and inset.
const LEVEL_WIDTH := 14.0
const LEVEL_INSET := 10.0

var state := "rest"
## Whether the square lights under the pointer while at rest (a square that
## does nothing on a click stays still).
var hoverable := true
var _picture: TextureRect
## What goes here, grey and faint, while the square is empty (854 amended (7)).
var _empty: TextureRect
static var _grey: Shader
var _face: Control
var _count: Label
var _price: UiPrice
var _material: UiPrice
var _mark: TextureRect
## A stock level, have and enough (set_level); enough < 0: none shown.
var level_have := 0
var level_enough := -1
var _back_to := "rest"
## The resting state a hover goes back to.
var _resting := "rest"
var _refused_left := 0.0


func _init() -> void:
	theme_type_variation = STATES["rest"]
	mouse_filter = Control.MOUSE_FILTER_STOP
	_face = Control.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)
	_empty = TextureRect.new()
	_empty.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_empty.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty.visible = false
	if _grey == null:
		_grey = Shader.new()
		_grey.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tCOLOR = vec4(vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))), c.a);\n}\n"
	var grey := ShaderMaterial.new()
	grey.shader = _grey
	_empty.material = grey
	_empty.modulate = UiTheme.color("slot_empty")
	_face.add_child(_empty)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face.add_child(_picture)
	_count = Label.new()
	_count.theme_type_variation = &"SquareCount"
	_count.position = Vector2(INSET, INSET)
	_count.visible = false
	_face.add_child(_count)
	_mark = TextureRect.new()
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	_face.add_child(_mark)
	_price = UiPrice.new()
	_price.visible = false
	_face.add_child(_price)
	_material = UiPrice.new()
	_material.visible = false
	_face.add_child(_material)
	var size_now := float(UiTheme.constant("square"))
	custom_minimum_size = Vector2(size_now, size_now)
	mouse_entered.connect(func() -> void:
		if hoverable and state in RESTING:
			_resting = state
			_show_state("hover"))
	mouse_exited.connect(func() -> void:
		if state == "hover":
			_show_state(_resting))
	resized.connect(_place)
	# The face is sized after the square (in a grid in a scroll, only once laid
	# out): placed again then, so no chip stays where a zero-sized face put it
	# (886; Store A as built, 11-12: chips on the squares' top edges).
	_face.resized.connect(_place)
	set_process(false)


## The thing's picture (an ItemIcons texture), or none.
func set_picture(picture: Texture2D) -> void:
	_picture.texture = picture
	_empty.visible = picture == null and _empty.texture != null


## What goes in this square, shown grey and faint while it is empty (a worn
## square's kind: a hat on Head, a ring on a Ring), or none.
func set_empty_picture(picture: Texture2D) -> void:
	_empty.texture = picture
	_empty.visible = _picture.texture == null and picture != null


func empty_shown() -> bool:
	return _empty.visible


func picture() -> Texture2D:
	return _picture.texture


## How many (shown from 2).
func set_count(n: int) -> void:
	_count.text = str(n)
	_count.visible = n > 1


func count_shown() -> String:
	return _count.text if _count.visible else ""


## The chip: [code]price().set_gold(3)[/code], set_kind, set_time; hidden by
## clear_price.
func price() -> UiPrice:
	_price.visible = true
	_place.call_deferred()
	return _price


func clear_price() -> void:
	_price.visible = false


## What a work spends besides gold (the town's ore): its picture and count.
func set_spends(picture: Texture2D, count: int) -> void:
	_material.set_kind(picture, count)
	_material.visible = true
	_place.call_deferred()


func clear_spends() -> void:
	_material.visible = false


## The work's mark (art/ui/marks), or null for none.
func set_mark(mark: Texture2D) -> void:
	_mark.texture = mark
	_mark.visible = mark != null


func has_mark() -> bool:
	return _mark.visible


## A town's stock on this square (854 amended (2); the town window Jeff's
## look carries, the coordinator's approval 11-11): a bar up the left edge
## filled have/enough (never past full), rust when half short or worse, brass
## while short, green at enough; and the true have/enough on the coinless
## pill ("14/10" over enough), its numbers rust with the bar, so it reads
## without colour. A thing the town wants none of (enough 0): the count
## alone, no bar.
func set_level(have: int, enough: int) -> void:
	level_have = have
	level_enough = maxi(enough, 0)
	if level_enough == 0:
		price().set_words(str(have))
	else:
		price().set_words("%d/%d" % [have, level_enough], level_short() >= 0.5)
	queue_redraw()


func clear_level() -> void:
	level_enough = -1
	clear_price()
	queue_redraw()


## How far short of enough, 0 (at enough or over, or no level) to 1 (none).
func level_short() -> float:
	if level_enough <= 0:
		return 0.0
	return clampf(1.0 - float(level_have) / float(level_enough), 0.0, 1.0)


## The bar's colour: the town sheet's rule (rust, brass, the friend colour).
func level_colour() -> Color:
	var short := level_short()
	if short >= 0.5:
		return UiTheme.color("rust")
	if short > 0.0:
		return UiTheme.color("brass")
	return UiTheme.color("friend")


## One of STATES' names.
func set_state(name: String) -> void:
	if not STATES.has(name):
		push_warning("[ui] UiSlot: no state %s" % name)
		return
	_refused_left = 0.0
	set_process(false)
	_show_state(name)


## The rust rim for REFUSED_SECONDS, then the state it had.
func flash_refused() -> void:
	if state != "refused":
		_back_to = _resting if state == "hover" else state
	_show_state("refused")
	_refused_left = REFUSED_SECONDS
	set_process(true)


func _process(delta: float) -> void:
	_refused_left -= delta
	if _refused_left <= 0.0:
		set_process(false)
		_show_state(_back_to)


func _show_state(name: String) -> void:
	state = name
	theme_type_variation = STATES[name]
	_picture.modulate.a = FADED if name == "in_hand" else 1.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		# Accepted before it is reported: a click that rebuilds the squares
		# frees this one, and accept_event out of the tree is an error (854
		# amended (1); v0.1.202's click).
		accept_event()
		pressed.emit(self)


## The chips and the mark at their corners (the face is the square inside its margin).
func _place() -> void:
	var face := _face.size
	_mark.size = Vector2(MARK, MARK) - Vector2(16.0, 16.0)
	_mark.position = Vector2(face.x - MARK - INSET + 8.0, INSET + 8.0)
	if _price.visible:
		_price.reset_size()
		_price.position = face - _price.size - Vector2(INSET, INSET)
	if _material.visible:
		_material.reset_size()
		_material.position = Vector2(INSET, face.y - _material.size.y - INSET)


## The level's bar, the mark's disc, and the ready corner, over the panel.
func _draw() -> void:
	if level_enough > 0:
		var well := Rect2(LEVEL_INSET, LEVEL_INSET + 2.0, LEVEL_WIDTH, size.y - 2.0 * LEVEL_INSET - 4.0)
		draw_rect(well, UiTheme.color("outline"))
		var filled := well.size.y * (1.0 - level_short())
		if filled > 0.0:
			draw_rect(Rect2(well.position.x, well.end.y - filled, LEVEL_WIDTH, filled), level_colour())
	if _mark.visible:
		var face_at := _face.position
		var centre := face_at + _mark.position + _mark.size / 2.0
		draw_circle(centre, MARK / 2.0, UiTheme.color("outline"))
		draw_arc(centre, MARK / 2.0, 0.0, TAU, 32, UiTheme.color("edge"), 2.0, true)
	if state == "ready":
		var w := size.x
		draw_colored_polygon(PackedVector2Array([Vector2(w - CORNER - 4.0, 4.0), Vector2(w - 4.0, 4.0), Vector2(w - 4.0, CORNER + 4.0)]),
			UiTheme.color("brass_bright"))
