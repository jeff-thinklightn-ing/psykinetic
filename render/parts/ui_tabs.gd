class_name UiTabs
extends HBoxContainer
## The named places at a window's head (decision 854; the store Jeff approved,
## 11-10: Store, Donate, Locker; Hob's Healing): one Tab button each, one lit,
## a click on another lights it and says so (chosen). The words are voice's,
## given by the window. One place alone shows no strip (a counter only serves).

signal chosen(index: int)

var current := -1
var _group := ButtonGroup.new()


func _init() -> void:
	theme_type_variation = &"Strip"


## [param names] in order, [param open] lit; one name or none hides the strip.
func set_tabs(names: Array[String], open := 0) -> void:
	for old in get_children():
		remove_child(old)
		old.queue_free()
	_group = ButtonGroup.new()
	for i in names.size():
		var tab := Button.new()
		tab.theme_type_variation = &"Tab"
		tab.text = names[i]
		tab.toggle_mode = true
		tab.button_group = _group
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(func() -> void: _choose(i))
		add_child(tab)
	visible = names.size() > 1
	current = -1
	if not names.is_empty():
		show_tab(clampi(open, 0, names.size() - 1))


## Lights [param index] without saying so (the window opened a place itself).
func show_tab(index: int) -> void:
	if index < 0 or index >= get_child_count():
		return
	current = index
	(get_child(index) as Button).set_pressed_no_signal(true)


func names() -> Array[String]:
	var out: Array[String] = []
	for tab in get_children():
		out.append((tab as Button).text)
	return out


func _choose(index: int) -> void:
	if index == current:
		return
	current = index
	chosen.emit(index)
