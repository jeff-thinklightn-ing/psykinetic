class_name DealPanel
extends PanelContainer
## A talking monster's deals as buttons (decision 629, ui's side; Jeff on
## v0.1.169: "no way to give gold to draugr"). E on a peaceable talking
## monster within hearing greets him (npc's "greet" command, his first
## offer spoken); his "offers" message opens this window with his name,
## his words and one button for each sum of gold his deal takes (the
## deal's what.steps), each enabled while the local purse covers it; a
## button sends the "offer" command {id, gold: that step} and his answer
## is spoken as the typed path's is. It closes when his offers come back
## empty (a pact on), when he stops being peaceable (struck, provoked, a
## pact: Monster.peaceable, npc's 648), when the player leaves hearing,
## or by Esc; Main._update_deal watches. The typed path (a sum or a yes in
## earshot) stays. The look is the shared theme's (UiTheme, docs/ui_style.md).
## A deal with no steps and a cost of 0 (548 amended, ui's side: the draugr
## faced again by one who has paid once; Jeff: "as long as you paid once you
## get unlimited attempts") is one button with no sum, AGAIN_WORDS, enabled
## whatever the purse, sending gold 0 as a step button sends its sum.
## His refusal (an offer whose id ends ":refuse", cost 0: dungeon's, Jeff's trap
## in the barrow, where a plain click only talks) is one more button,
## NO_WORDS, after the deal's, enabled whatever the purse, sending gold 0;
## alone when he offers nothing else a purse covers. The window says how
## to strike him (STRIKE_WORDS).

## A button pressed: the deal's id and the gold it offers.
signal offered(id: String, gold: int)

const WIDTH := 620.0
## The free deal's one button (548 amended, ui's side).
const AGAIN_WORDS := "Face him again"
## His refusal's button (Jeff: "just put the word refuse"): it starts the fight.
const NO_WORDS := "Refuse"
## How to strike a talking monster, under his deals.
const STRIKE_WORDS := "Shift+click: strike"

## The talking monster shown (his instance id), 0 for none.
var entity_id := 0
## The deal shown (the "offers" message's entry), {} for none.
var deal: Dictionary = {}
## The purse the buttons were last enabled against.
var purse := -1

var _title: Label
var _words: Label
var _buttons: HBoxContainer
var _purse: Label
var _strike: Label


func _init() -> void:
	name = "DealPanel"
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	column.add_child(_title)
	_words = Label.new()
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_words)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(_buttons)
	_purse = Label.new()
	_purse.theme_type_variation = &"Caption"
	_purse.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	column.add_child(_purse)
	_strike = Label.new()
	_strike.theme_type_variation = &"Caption"
	_strike.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	_strike.text = STRIKE_WORDS
	column.add_child(_strike)


## [param speaker]'s [param offers] (the "offers" message's list) for a
## purse of [param gold], under [param id] (his instance id): the first
## deal with steps is shown, a button a step; none closes the window.
func show_deals(speaker: String, offers: Array, gold: int, id: int) -> void:
	deal = first_deal(offers)
	var refuse := no_deal(offers)
	if deal.is_empty():
		deal = refuse
		refuse = {}
	if deal.is_empty():
		close()
		return
	entity_id = id
	_title.text = speaker
	_words.text = str(deal.get("words", deal.get("title", "")))
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for step in steps_of(deal):
		var button := Button.new()
		button.text = (NO_WORDS if is_no(deal) else AGAIN_WORDS) if step == 0 else step_words(step)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_pressed.bind(str(deal.get("id", "")), step))
		_buttons.add_child(button)
	if not refuse.is_empty():
		var button := Button.new()
		button.text = NO_WORDS
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_pressed.bind(str(refuse.get("id", "")), 0))
		_buttons.add_child(button)
	set_purse(gold)
	visible = true


## The buttons enabled against [param gold], and the purse line.
func set_purse(gold: int) -> void:
	purse = gold
	var steps := steps_of(deal)
	var i := 0
	for child in _buttons.get_children():
		if child is Button and i < steps.size():
			child.disabled = steps[i] > gold
		i += 1
	_purse.text = purse_words(gold, steps)


func close() -> void:
	visible = false
	entity_id = 0
	deal = {}
	purse = -1


func _pressed(id: String, gold: int) -> void:
	offered.emit(id, gold)


## The first of [param offers] that is a deal with steps and not his
## refusal, else {}.
static func first_deal(offers: Array) -> Dictionary:
	for each: Variant in offers:
		if each is Dictionary and not is_no(each) and not steps_of(each).is_empty():
			return each
	return {}


## His refusal among [param offers] (is_no), else {}.
static func no_deal(offers: Array) -> Dictionary:
	for each: Variant in offers:
		if each is Dictionary and is_no(each):
			return each
	return {}


## Whether [param deal] is his refusal: its id ends ":refuse".
static func is_no(deal: Dictionary) -> bool:
	return str(deal.get("id", "")).ends_with(":refuse")


## [param deal]'s sums of gold, least first: its what.steps, else its cost;
## [0] for a free deal (no steps, "cost" given as 0: 548 amended, ui's side).
static func steps_of(deal: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var what: Variant = deal.get("what", {})
	if what is Dictionary:
		for step: Variant in what.get("steps", []):
			if int(step) > 0 and int(step) not in out:
				out.append(int(step))
	if out.is_empty() and int(deal.get("cost", 0)) > 0:
		out.append(int(deal.get("cost", 0)))
	if out.is_empty() and deal.has("cost") and int(deal["cost"]) == 0 and str(deal.get("id", "")) != "":
		out.append(0)
	out.sort()
	return out


static func step_words(step: int) -> String:
	return "%d gold" % step


## The purse line: what you have; short of the least, what he asks.
static func purse_words(gold: int, steps: Array[int]) -> String:
	if not steps.is_empty() and gold < steps[0]:
		return "You have %d gold; he asks %d at the least." % [gold, steps[0]]
	return "You have %d gold." % gold
