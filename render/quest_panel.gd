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
## 747 amended (7), ui's side: the card is never drawn over or under an open
## window (windows_of: the controls of the windows that may reach it; a window
## whose rect, OVERLAP_MARGIN wider, meets the card's hides it, and it returns
## RETURN_SECONDS after the last one has gone), and it is drawn only in the
## quest's own place (the quest's "zones", dungeon's; zone_of: the zone the
## local player stands in, "" while it is not known yet, as in the first frames
## after a zone change or a login; a quest with no "zones" is drawn anywhere).

const WIDTH := 300.0
## A window's rect widened by this many pixels meets the card's: an edge a few
## pixels off the card still counts as touching it.
const OVERLAP_MARGIN := 12.0
## The card comes back this long after the last window over its place has
## closed (no flicker while a window animates or is dragged across it).
const RETURN_SECONDS := 0.5
## A thing's mark, drawn (the theme's fonts have no check mark): a tick for
## a done one, a dot for an open one, MARK px square.
const MARK := 16.0
## The line once every thing is done: "Return to " and the giver.
const RETURN_WORDS := "Return to %s."

## The local player's quest, read each frame (Main's).
var quest_of: Callable
## The open windows' controls, an Array (Main's); the card keeps clear of them.
var windows_of: Callable
## The local player's zone name, "" when not known yet (Main's).
var zone_of: Callable
## The quest drawn, {} for none.
var quest: Dictionary = {}

## Seconds since a window last covered the card's place (at most RETURN_SECONDS).
var _clear := RETURN_SECONDS
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


func _process(delta: float) -> void:
	step(delta)


## One frame: placed, redrawn if the quest changed, and shown or hidden by
## the quest, the place and the windows ([param delta] seconds passed).
func step(delta: float) -> void:
	_place()
	if quest_of.is_valid():
		var now: Dictionary = quest_of.call()
		if str(now) != str(quest):
			show_quest(now)
	_clear = 0.0 if _covered() else minf(RETURN_SECONDS, _clear + delta)
	visible = _wanted()


## Whether the card should be drawn: a quest, in its place, with no window
## over it (and none lately).
func _wanted() -> bool:
	return not quest.is_empty() and in_place() and _clear >= RETURN_SECONDS


## Whether the local player stands where the quest is: in one of its "zones",
## or anywhere if it names none. An unknown zone ("") is not in place, so the
## card never flashes before the zone is known.
func in_place() -> bool:
	var zones: Variant = quest.get("zones", [])
	if not zones is Array or (zones as Array).is_empty():
		return true
	var here: String = str(zone_of.call()) if zone_of.is_valid() else ""
	return not here.is_empty() and here in zones


## Whether an open window's rect (OVERLAP_MARGIN wider) meets the card's.
func _covered() -> bool:
	if not windows_of.is_valid():
		return false
	var mine := Rect2(position, Vector2(maxf(size.x, WIDTH), maxf(size.y, get_combined_minimum_size().y)))
	mine = mine.grow(OVERLAP_MARGIN)
	for window: Variant in windows_of.call():
		var control := window as Control
		if is_instance_valid(control) and control != self and control.is_visible_in_tree() \
				and control.get_global_rect().intersects(mine):
			return true
	return false


## Under the corner map and its world map button (Minimap's CORNER_TOP,
## CORNER_SIZE and WORLD_ROW, scaled as it is for screens over BASE_HEIGHT
## lines), its right edge on the map's.
func _place() -> void:
	var screen := get_viewport_rect().size
	var k := maxf(1.0, screen.y / Minimap.BASE_HEIGHT)
	position = Vector2(screen.x - size.x - Minimap.CORNER_MARGIN * k,
			(Minimap.CORNER_TOP + Minimap.CORNER_SIZE + Minimap.WORLD_ROW + 16.0) * k)


## [param given] drawn (Player.quest's shape), or the card hidden for {}.
func show_quest(given: Dictionary) -> void:
	quest = given.duplicate(true)
	visible = _wanted()
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
