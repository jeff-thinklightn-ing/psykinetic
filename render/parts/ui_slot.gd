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
## corner: one click collects) and in_hand (the picture faded). Never greyed:
## a square that can't be used shows nothing to use. The window's script says
## what a click does; the square only reports it (pressed).

signal pressed(slot: UiSlot)

const STATES := {"rest": &"Well", "hover": &"WellHover", "picked": &"WellPicked", "new": &"WellNew",
	"refused": &"WellRefused", "ready": &"WellNew", "in_hand": &"Well"}
const REFUSED_SECONDS := 1.0
## How far the chips and the mark sit in from the square's edge, inside its margin.
const INSET := -8.0
## A faded picture's strength (work in hand).
const FADED := 0.45
const CORNER := 40.0
const MARK := 52.0

var state := "rest"
## Whether the square lights under the pointer while at rest (a square that
## does nothing on a click stays still).
var hoverable := true
var _picture: TextureRect
var _face: Control
var _count: Label
var _price: UiPrice
var _material: UiPrice
var _mark: TextureRect
var _back_to := "rest"
var _refused_left := 0.0


func _init() -> void:
	theme_type_variation = STATES["rest"]
	mouse_filter = Control.MOUSE_FILTER_STOP
	_face = Control.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)
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
		if hoverable and state == "rest":
			_show_state("hover"))
	mouse_exited.connect(func() -> void:
		if state == "hover":
			_show_state("rest"))
	resized.connect(_place)
	set_process(false)


## The thing's picture (an ItemIcons texture), or none.
func set_picture(picture: Texture2D) -> void:
	_picture.texture = picture


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
		_back_to = "rest" if state == "hover" else state
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


## The mark's disc, and the ready corner, over the panel.
func _draw() -> void:
	if _mark.visible:
		var face_at := _face.position
		var centre := face_at + _mark.position + _mark.size / 2.0
		draw_circle(centre, MARK / 2.0, UiTheme.color("outline"))
		draw_arc(centre, MARK / 2.0, 0.0, TAU, 32, UiTheme.color("edge"), 2.0, true)
	if state == "ready":
		var w := size.x
		draw_colored_polygon(PackedVector2Array([Vector2(w - CORNER - 4.0, 4.0), Vector2(w - 4.0, 4.0), Vector2(w - 4.0, CORNER + 4.0)]),
			UiTheme.color("brass_bright"))
