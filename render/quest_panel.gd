class_name QuestPanel
extends PanelContainer
## The quest tracker (747, ui's side; dungeon's fallen knight's quest): the
## local player's Player.quest ({} for none, else {title, giver, items:
## [{name, done}], ready}, replicated) as a small card at the HUD's right,
## under the corner map (the hints have the top left):
## the quest's title, one line a thing to do, a done one ticked (Mark) in
## the theme's green, and once all are done (ready) a line to go back to
## who gave it (RETURN_WORDS). Hidden while there is no quest; redrawn only
## when the quest changes. The look is the shared theme's (UiTheme,
## docs/ui_style.md).

const WIDTH := 300.0
## A thing's mark, drawn (the theme's fonts have no check mark): a tick for
## a done one, a dot for an open one, MARK px square.
const MARK := 16.0
## The line once every thing is done: "Return to " and the giver.
const RETURN_WORDS := "Return to %s."

## The local player's quest, read each frame (Main's).
var quest_of: Callable
## The quest drawn, {} for none.
var quest: Dictionary = {}

var _title: Label
var _rows: VBoxContainer
var _return: Label


func _init() -> void:
	name = "QuestPanel"
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	column.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	column.add_child(_rows)
	_return = Label.new()
	_return.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_return.add_theme_color_override("font_color", UiTheme.color("brass_bright"))
	column.add_child(_return)
	if not quest.is_empty():
		show_quest(quest)


func _process(_delta: float) -> void:
	_place()
	if not quest_of.is_valid():
		return
	var now: Dictionary = quest_of.call()
	if str(now) != str(quest):
		show_quest(now)


## Under the corner map (Minimap's CORNER_TOP and CORNER_SIZE, scaled as it is
## for screens over BASE_HEIGHT lines), its right edge on the map's.
func _place() -> void:
	var screen := get_viewport_rect().size
	var k := maxf(1.0, screen.y / Minimap.BASE_HEIGHT)
	position = Vector2(screen.x - size.x - Minimap.CORNER_MARGIN * k,
			(Minimap.CORNER_TOP + Minimap.CORNER_SIZE + 16.0) * k)


## [param given] drawn (Player.quest's shape), or the card hidden for {}.
func show_quest(given: Dictionary) -> void:
	quest = given.duplicate(true)
	visible = not quest.is_empty()
	if _rows == null:
		return  # Drawn at _ready.
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	if quest.is_empty():
		return
	_title.text = str(quest.get("title", ""))
	for item: Dictionary in quest.get("items", []):
		var done := bool(item.get("done", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mark := Mark.new()
		mark.done = done
		mark.colour = UiTheme.color("friend") if done else UiTheme.color("text_dim")
		row.add_child(mark)
		var label := Label.new()
		label.text = str(item.get("name", ""))
		label.add_theme_color_override("font_color", UiTheme.color("friend") if done else UiTheme.color("text"))
		row.add_child(label)
		_rows.add_child(row)
	_return.text = RETURN_WORDS % str(quest.get("giver", "")) if bool(quest.get("ready", false)) else ""
	_return.visible = _return.text != ""


## The rows, in order, each [its Mark, its Label] (tests).
func rows() -> Array[Array]:
	var out: Array[Array] = []
	for row in _rows.get_children():
		if not row.is_queued_for_deletion():
			out.append([row.get_child(0), row.get_child(1)])
	return out


## A row's mark: a tick when [member done], else a dot, in [member colour].
class Mark extends Control:
	var done := false
	var colour := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(MARK, MARK)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if done:
			draw_polyline(PackedVector2Array([Vector2(MARK * 0.15, MARK * 0.55), Vector2(MARK * 0.4, MARK * 0.8),
					Vector2(MARK * 0.85, MARK * 0.2)]), colour, 2.5, true)
		else:
			draw_circle(Vector2(MARK, MARK) * 0.5, 2.0, colour)
