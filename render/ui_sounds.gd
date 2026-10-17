class_name UiSounds
extends Node
## The menus' sounds (decision 395), on the UI bus, flat: every button
## clicks when pressed and ticks when the pointer comes onto it, and a
## slider clicks when let go (so a volume is heard as it is set); a watched
## panel (watch) sounds as it opens and shuts. Main also plays a ping for
## someone else's chat, a chime for a party line, and an error for a
## refusal (play). Buttons are found as they enter the tree, so a panel's
## own code adds no sounds.

## A hover ticks at most this often (ms): a pointer swept across a row
## of buttons makes a patter, not a buzz.
const HOVER_GAP_MS := 80
## Nothing sounds this long after the menus are built (ms): panels being
## laid out are no one's doing.
const QUIET_MS := 1500

## Gives the Sfx to play through (the view's), or null while there is none.
var sfx_of: Callable
## Each slot played, newest last (tests).
var played: Array[String] = []
var _last_hover := 0
var _quiet_until := 0


func _ready() -> void:
	_quiet_until = Time.get_ticks_msec() + QUIET_MS
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "Control", true, false):
		_on_node_added(node)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## [param panel] sounds as it shows (ui.panel_open) and hides
## (ui.panel_close).
func watch(panel: CanvasItem) -> void:
	panel.visibility_changed.connect(func() -> void:
		play("ui.panel_open" if panel.visible else "ui.panel_close"))


## Plays the UI slot [param slot] (ui.*), unless the menus are still being
## built or there is nothing to play through.
func play(slot: String) -> void:
	if Time.get_ticks_msec() < _quiet_until or not sfx_of.is_valid():
		return
	var sfx: Sfx = sfx_of.call()
	if sfx == null or not is_instance_valid(sfx) or not sfx.is_inside_tree():
		return
	played.append(slot)
	sfx.play_flat(slot)


func _on_node_added(node: Node) -> void:
	if node.has_meta(&"ui_sounds"):
		return
	if node is BaseButton:
		node.set_meta(&"ui_sounds", true)
		var button := node as BaseButton
		button.pressed.connect(play.bind("ui.click"))
		button.mouse_entered.connect(_hover.bind(button))
	elif node is Slider:
		node.set_meta(&"ui_sounds", true)
		(node as Slider).drag_ended.connect(func(_changed: bool) -> void: play("ui.click"))


func _hover(button: BaseButton) -> void:
	var now := Time.get_ticks_msec()
	if button.disabled or now - _last_hover < HOVER_GAP_MS:
		return
	_last_hover = now
	play("ui.hover")
