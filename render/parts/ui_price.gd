class_name UiPrice
extends PanelContainer
## A chip on a square's corner (decision 854; the store Jeff approved, 11-10):
## a dark pill holding what a thing costs or pays. Gold: the coin drawn in the
## pill's left margin and the number. In kind (Hob's herbs and antlers): the
## thing's own small picture where the coin goes. A time (work in hand): the
## words alone, on the TimeChip pill (and any words: a free ware). Short (you can't pay it): the number in
## rust, never dimmed. Material (what a work spends besides gold) is a kind
## chip; where it sits is the square's (UiSlot).

## What the chip shows now: "gold", "kind", "time" or "words".
var mode := "gold"
## Gold or a count; -1 for a time chip.
var amount := -1
var short := false
var kind_picture: Texture2D
var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"PriceChip"
	_label = Label.new()
	_label.theme_type_variation = &"ChipPrice"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


## A price in gold: [param gold], in rust when [param can_not_pay].
func set_gold(gold: int, can_not_pay := false) -> void:
	_show("gold", gold, can_not_pay, null, str(gold))


## A price in kind: [param count] of the thing [param picture] shows.
func set_kind(picture: Texture2D, count: int, can_not_pay := false) -> void:
	_show("kind", count, can_not_pay, picture, str(count))


## A time chip: [param words] ("4 min").
func set_time(words: String) -> void:
	_show("time", -1, false, null, words)


## Words alone on the pill without a coin (a free ware: voice's word; a stock
## level's "3/10", in rust while it is well short: 854 amended (2)).
func set_words(words: String, is_short := false) -> void:
	_show("words", -1, is_short, null, words)


func shown() -> String:
	return _label.text


func _show(new_mode: String, n: int, can_not_pay: bool, picture: Texture2D, words: String) -> void:
	mode = new_mode
	amount = n
	short = can_not_pay
	kind_picture = picture
	theme_type_variation = &"TimeChip" if mode in ["time", "words"] else &"PriceChip"
	_label.theme_type_variation = &"ChipPriceShort" if short else &"ChipPrice"
	_label.text = words
	reset_size()
	queue_redraw()


## The coin or the thing, in the pill's left margin.
func _draw() -> void:
	if mode in ["time", "words"]:
		return
	var room := get_theme_stylebox(&"panel").content_margin_left
	var d := minf(room - 12.0, size.y - 12.0)
	var at := Vector2(8.0 + (room - 12.0 - d) / 2.0, (size.y - d) / 2.0)
	if mode == "kind" and kind_picture != null:
		draw_texture_rect(kind_picture, Rect2(at, Vector2(d, d)), false)
		return
	var centre := at + Vector2(d, d) / 2.0
	draw_circle(centre, d / 2.0, UiTheme.color("brass"))
	draw_arc(centre, d / 2.0, 0.0, TAU, 24, UiTheme.color("outline"), 2.0, true)
	draw_arc(centre, d * 0.22, 0.0, TAU, 16, UiTheme.color("brass_bright"), 2.0, true)
