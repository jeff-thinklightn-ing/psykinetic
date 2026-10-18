class_name CounterPanel
extends PanelContainer
## The counter screen (ui's step 4; economy's counter job, decision 438, at
## buildings' temple counter and the store's): beside the pack while a
## temple or shop counter is open, on the shop panel's pattern. What can be
## done to each thing the player carries there (the thing's title, the
## work's words, the price and materials in brass, Order; a refusal's why
## in rust beside it), what of theirs is being worked (how long is left),
## and what waits for them (Collect), with the last refusal under it all.
## Main feeds it economy's "counter" message (show_counter) and sends what
## the buttons ask (order_pressed, collect_pressed). The look is the shared
## theme's (UiTheme, docs/ui_style.md).

## Order pressed: the slot, the effect, the target id ("" but for a reforge).
signal order_pressed(slot: int, effect: String, to_id: String)
## Collect pressed: the finished thing's uid.
signal collect_pressed(uid: int)

const WIDTH := 760.0
const KIND_WORDS := {"temple": "The temple's counter", "shop": "The smith's counter"}
const EFFECT_WORDS := {"bless": "blessed", "reforge": "reforged", "mend": "mended"}

## The last data shown (economy's shape).
var data := {}

var _title: Label
var _jobs: VBoxContainer
var _working: VBoxContainer
var _waiting: VBoxContainer
var _why: Label


func _init() -> void:
	name = "Counter"
	visible = false


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	column.add_child(_title)
	_jobs = VBoxContainer.new()
	_jobs.add_theme_constant_override("separation", UiTheme.constant("unit"))
	column.add_child(_jobs)
	_working = VBoxContainer.new()
	_working.add_theme_constant_override("separation", 4)
	column.add_child(_working)
	_waiting = VBoxContainer.new()
	_waiting.add_theme_constant_override("separation", 4)
	column.add_child(_waiting)
	_why = Label.new()
	_why.add_theme_color_override("font_color", UiTheme.color("rust"))
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.custom_minimum_size = Vector2(WIDTH - 2 * UiTheme.constant("pad"), 0)
	_why.visible = false
	column.add_child(_why)


## The words for what [param effect] does, from items' catalog when it has
## them (Items.growth()["says"]), else the effect's own word.
static func effect_words(effect: String) -> String:
	var says := str(Items.growth().get("says", {}).get(effect, ""))
	return "%s%s" % [EFFECT_WORDS.get(effect, effect), ": " + says if not says.is_empty() else ""]


## Economy's "counter" message for the open counter; [param titles] is a
## slot's title as the pack shows it (the slot note's head, or the catalog
## name), by slot, for the rows' names.
func show_counter(given: Dictionary, titles: Callable) -> void:
	data = given
	_title.text = str(KIND_WORDS.get(str(given.get("kind", "")), "The counter"))
	for box: VBoxContainer in [_jobs, _working, _waiting]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var jobs: Array = given.get("jobs", []) if given.get("jobs") is Array else []
	if jobs.is_empty():
		_jobs.add_child(_caption("Nothing you carry can be worked here."))
	for job: Variant in jobs:
		if job is Dictionary:
			_jobs.add_child(_job_row(job, titles))
	var working: Array = given.get("working", []) if given.get("working") is Array else []
	if not working.is_empty():
		_working.add_child(_caption("Being worked:"))
		for each: Variant in working:
			if each is Dictionary:
				var left := int(each.get("left_seconds", 0))
				var when := "ready in about %d minute%s" % [ceili(left / 60.0), "" if ceili(left / 60.0) == 1 else "s"] \
						if left >= 60 else "ready in %d seconds" % left
				_working.add_child(_caption("%s, being %s; %s" % [Items.name_of(str(each.get("id", ""))),
					EFFECT_WORDS.get(str(each.get("effect", "")), str(each.get("effect", ""))), when]))
	var waiting: Array = given.get("waiting", []) if given.get("waiting") is Array else []
	if not waiting.is_empty():
		_waiting.add_child(_caption("Waiting for you:"))
		for each: Variant in waiting:
			if each is Dictionary:
				_waiting.add_child(_waiting_row(each))
	_why.text = str(given.get("why", ""))
	_why.visible = not _why.text.is_empty()


## The rows shown, "title: words" with the button's word in brackets (tests).
func rows_shown() -> Array[String]:
	var out: Array[String] = []
	for box: VBoxContainer in [_jobs, _working, _waiting]:
		for row: Node in box.get_children():
			if row is Label:
				out.append((row as Label).text)
			else:
				var words: Label = row.find_child("Words", true, false)
				var button: Button = row.get_node_or_null("Button")
				var why: Label = row.get_node_or_null("Why")
				out.append("%s%s%s" % [words.text, " [%s]" % button.text if button != null else "",
					" (%s)" % why.text if why != null else ""])
	return out


func why_shown() -> String:
	return _why.text


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH - 2 * UiTheme.constant("pad"), 0)
	return label


func _job_row(job: Dictionary, titles: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.constant("row"))
	var slot := int(job.get("slot", -1))
	var effect := str(job.get("effect", ""))
	var to_id := str(job.get("to_id", ""))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var words := Label.new()
	words.name = "Words"
	var title := str(titles.call(slot)) if titles.is_valid() else Items.name_of(str(job.get("id", "")))
	words.text = "%s: %s%s" % [title, EFFECT_WORDS.get(effect, effect), " into a %s" % Items.name_of(to_id) if not to_id.is_empty() else ""]
	words.add_theme_font_override("font", UiTheme.font("serif"))
	column.add_child(words)
	var says := effect_words(effect)
	if says.contains(":"):
		var about := Label.new()
		about.theme_type_variation = &"Caption"
		about.text = says.substr(says.find(":") + 2)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(about)
	var cost: Array[String] = []
	if int(job.get("price", 0)) > 0:
		cost.append("%d gold" % int(job["price"]))
	var materials: Dictionary = job.get("materials", {}) if job.get("materials") is Dictionary else {}
	for what: Variant in materials:
		cost.append("%d %s" % [int(materials[what]), Items.name_of(str(what))])
	if not cost.is_empty():
		var price := Label.new()
		price.text = ", ".join(cost)
		price.add_theme_color_override("font_color", UiTheme.color("brass"))
		price.theme_type_variation = &"Caption"
		column.add_child(price)
	row.add_child(column)
	if bool(job.get("ok", true)):
		var button := Button.new()
		button.name = "Button"
		button.text = "Order"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void: order_pressed.emit(slot, effect, to_id))
		row.add_child(button)
	else:
		var why := Label.new()
		why.name = "Why"
		why.text = str(job.get("why", "not now"))
		why.theme_type_variation = &"Caption"
		why.add_theme_color_override("font_color", UiTheme.color("rust"))
		why.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(why)
	return row


func _waiting_row(each: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.constant("row"))
	var words := Label.new()
	words.name = "Words"
	words.text = "%s, %s" % [Items.name_of(str(each.get("id", ""))), EFFECT_WORDS.get(str(each.get("effect", "")), str(each.get("effect", "")))]
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_font_override("font", UiTheme.font("serif"))
	row.add_child(words)
	var button := Button.new()
	button.name = "Button"
	button.text = "Collect"
	var uid := int(each.get("uid", 0))
	button.pressed.connect(func() -> void: collect_pressed.emit(uid))
	row.add_child(button)
	return row
