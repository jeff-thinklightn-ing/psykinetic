class_name UiRow
extends PanelContainer
## A person's ask as a row (decision 860; the talk window's mock the coordinator
## approved, 11-11, in the look Jeff approved 11-10): the window's width, its
## words on the left (RowWords), the asker's own line under them where they
## have one (RowLine, dim: voice's rule, none otherwise), and what it costs on
## the right, the store's chip (UiPrice, with the coin, rust when you can't
## pay). At least MIN_HEIGHT tall (56 px at 1080, the text scale on top): a
## row is a thing to hit. Its state is its rim: rest, hover (flame), refused
## (rust for REFUSED_SECONDS, then back; the window says why in its foot). Never
## greyed. The window's script says what a click does; the row only reports it
## (pressed), having accepted the click first (a click that rebuilds the list
## frees the row; 854 amended (1)).

signal pressed(row: UiRow)

const STATES := {"rest": &"Row", "hover": &"RowHover", "refused": &"RowRefused"}
const REFUSED_SECONDS := 1.0
## Canvas units: 112 = 56 px at 1080 lines.
const MIN_HEIGHT := 112.0

var state := "rest"
var _words: Label
var _line: Label
var _price: UiPrice
var _back_to := "rest"
var _refused_left := 0.0


func _init() -> void:
	theme_type_variation = STATES["rest"]
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = MIN_HEIGHT
	var across := HBoxContainer.new()
	across.theme_type_variation = &"Strip"
	across.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(across)
	var said := VBoxContainer.new()
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.alignment = BoxContainer.ALIGNMENT_CENTER
	said.theme_type_variation = &"Stack"
	said.mouse_filter = Control.MOUSE_FILTER_IGNORE
	across.add_child(said)
	_words = Label.new()
	_words.theme_type_variation = &"RowWords"
	_words.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	said.add_child(_words)
	_line = Label.new()
	_line.theme_type_variation = &"RowLine"
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.visible = false
	said.add_child(_line)
	_price = UiPrice.new()
	_price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price.visible = false
	across.add_child(_price)
	mouse_entered.connect(func() -> void:
		if state == "rest":
			_show_state("hover"))
	mouse_exited.connect(func() -> void:
		if state == "hover":
			_show_state("rest"))
	set_process(false)


## The ask's words (the server's title).
func set_words(words: String) -> void:
	_words.text = words


func words() -> String:
	return _words.text


## The asker's own line under the words, or "" for none (the row is then one line).
func set_line(line: String) -> void:
	_line.text = line
	_line.visible = not line.is_empty()


func line() -> String:
	return _line.text if _line.visible else ""


## The chip: [code]price().set_gold(6, short)[/code]; hidden by clear_price.
func price() -> UiPrice:
	_price.visible = true
	return _price


func clear_price() -> void:
	_price.visible = false


func has_price() -> bool:
	return _price.visible


## The rust rim for REFUSED_SECONDS, then the state it had.
func flash_refused() -> void:
	if state != "refused":
		_back_to = "rest"
	_show_state("refused")
	_refused_left = REFUSED_SECONDS
	set_process(true)


func _process(delta: float) -> void:
	_refused_left -= delta
	if _refused_left <= 0.0:
		set_process(false)
		_show_state("hover" if _back_to == "rest" and get_global_rect().has_point(get_global_mouse_position()) else _back_to)


func _show_state(name: String) -> void:
	state = name
	theme_type_variation = STATES[name]


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		# Accepted before it is reported (854 amended (1)).
		accept_event()
		pressed.emit(self)
