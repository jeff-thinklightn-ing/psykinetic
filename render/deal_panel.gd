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
## A quest's step (747, ui's side: the fallen knight's ask, not yet or
## turn-in; what.level "quest", cost 0) is one button with its own title,
## sending gold 0, with no purse line and no strike line.
## A townsperson's wares (the Rolf fix, ui's side: a Resident's "offers"
## holding lines whose accept is Offers.VENDOR_WARES, the starter stall's
## keeper, 736, or Offers.WARES, a pedlar's, 711) are one button a ware,
## its title ("A sword, 1 gold"), enabled while the purse covers its cost,
## sending its id with that cost; the purse line names the cheapest when
## short, and there is no strike line. Before this, no client path took
## a resident's wares at all (typed words skip visitors).
## Words only (747 amended (5), ui's side: the fallen knight once his quest is
## done; Jeff: "fallen knight was not interactable"): an offer whose accept is
## WORDS_ONLY ("none"), shown when he offers no deal and no refusal, is his
## words in his name and one button, FAREWELL_WORDS, that closes the window
## here and sends nothing; no purse line and no strike line.

## A button pressed: the deal's id and the gold it offers.
signal offered(id: String, gold: int)

const WIDTH := 620.0
## The free deal's one button (548 amended, ui's side).
const AGAIN_WORDS := "Face him again"
## His refusal's button (Jeff: "just put the word refuse"): it starts the fight.
const NO_WORDS := "Refuse"
## How to strike a talking monster, under his deals.
const STRIKE_WORDS := "Shift+click: strike"
## A words-only offer's accept (747 amended (5)): nothing to take.
const WORDS_ONLY := "none"
## A words-only window's one button (voice's word): it closes, sending nothing.
const FAREWELL_WORDS := "Farewell"

## The talking monster shown (his instance id), 0 for none.
var entity_id := 0
## The deal shown (the "offers" message's entry), {} for none.
var deal: Dictionary = {}
## The purse the buttons were last enabled against.
var purse := -1
## The wares shown (a townsperson's, is_ware), [] while a deal is shown.
var wares: Array[Dictionary] = []

var _title: Label
var _words: Label
var _buttons: HFlowContainer
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
	_buttons = HFlowContainer.new()  # A stall's ten wares wrap.
	_buttons.add_theme_constant_override("h_separation", UiTheme.constant("row"))
	_buttons.add_theme_constant_override("v_separation", UiTheme.constant("row"))
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
	wares = []
	deal = first_deal(offers)
	var refuse := no_deal(offers)
	if deal.is_empty():
		deal = refuse
		refuse = {}
	if deal.is_empty():
		deal = words_only(offers)
	if deal.is_empty():
		close()
		return
	entity_id = id
	_title.text = speaker
	_words.text = str(deal.get("words", deal.get("title", "")))
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for step in [] if is_words_only(deal) else steps_of(deal):  # Words only: Farewell alone.
		var button := Button.new()
		if is_quest(deal):
			button.text = str(deal.get("title", AGAIN_WORDS))
		else:
			button.text = (NO_WORDS if is_no(deal) else AGAIN_WORDS) if step == 0 else step_words(step)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_pressed.bind(str(deal.get("id", "")), step))
		_buttons.add_child(button)
	if is_words_only(deal):
		var farewell := Button.new()
		farewell.text = FAREWELL_WORDS
		farewell.focus_mode = Control.FOCUS_NONE
		farewell.pressed.connect(close)  # Here only: nothing is sent.
		_buttons.add_child(farewell)
	if not refuse.is_empty():
		var button := Button.new()
		button.text = NO_WORDS
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_pressed.bind(str(refuse.get("id", "")), 0))
		_buttons.add_child(button)
	set_purse(gold)
	# A quest's step (747) and words only ask no gold, and he cannot be struck.
	_purse.visible = not is_quest(deal) and not is_words_only(deal)
	_strike.visible = not is_quest(deal) and not is_words_only(deal)
	_words.visible = true
	visible = true


## [param speaker]'s wares among [param offers] (wares_of; a Resident's
## "offers" message) for a purse of [param gold], under [param id] (their
## instance id): a button a ware; none closes the window.
func show_wares(speaker: String, offers: Array, gold: int, id: int) -> void:
	wares = wares_of(offers)
	deal = {}
	if wares.is_empty():
		close()
		return
	entity_id = id
	_title.text = speaker
	_words.text = ""
	_words.visible = false
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for ware in wares:
		var button := Button.new()
		button.text = str(ware.get("title", ""))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_pressed.bind(str(ware.get("id", "")), int(ware.get("cost", 0))))
		_buttons.add_child(button)
	set_purse(gold)
	_purse.visible = true
	_strike.visible = false
	visible = true


## The buttons enabled against [param gold], and the purse line.
func set_purse(gold: int) -> void:
	purse = gold
	if not wares.is_empty():
		var costs: Array[int] = []
		var at := 0
		for child in _buttons.get_children():
			if child is Button and at < wares.size():
				child.disabled = int(wares[at].get("cost", 0)) > gold
				costs.append(int(wares[at].get("cost", 0)))
			at += 1
		costs.sort()
		_purse.text = wares_purse_words(gold, costs)
		return
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
	wares = []
	purse = -1


func _pressed(id: String, gold: int) -> void:
	offered.emit(id, gold)


## The first of [param offers] that is a deal with steps and neither his
## refusal nor words only (a cost-0 offer has the one step 0), else {}.
static func first_deal(offers: Array) -> Dictionary:
	for each: Variant in offers:
		if each is Dictionary and not is_no(each) and not is_words_only(each) and not steps_of(each).is_empty():
			return each
	return {}


## His refusal among [param offers] (is_no), else {}.
static func no_deal(offers: Array) -> Dictionary:
	for each: Variant in offers:
		if each is Dictionary and is_no(each):
			return each
	return {}


## The first of [param offers] that is words only (is_words_only), else {}.
static func words_only(offers: Array) -> Dictionary:
	for each: Variant in offers:
		if each is Dictionary and is_words_only(each):
			return each
	return {}


## Whether [param deal] is words only: its accept WORDS_ONLY (747 amended (5)).
static func is_words_only(deal: Dictionary) -> bool:
	return str(deal.get("accept", "")) == WORDS_ONLY


## Whether [param deal] is his refusal: its id ends ":refuse".
static func is_no(deal: Dictionary) -> bool:
	return str(deal.get("id", "")).ends_with(":refuse")


## Whether [param deal] is a quest's step (747, the fallen knight's: what.level
## "quest", no gold): one button, its title, sending gold 0.
static func is_quest(deal: Dictionary) -> bool:
	var what: Variant = deal.get("what", {})
	return what is Dictionary and str(what.get("level", "")) == "quest"


## Whether [param offer] is a ware a townsperson sells (its accept the
## starter stall's Offers.VENDOR_WARES or a pedlar's Offers.WARES).
static func is_ware(offer: Variant) -> bool:
	if not offer is Dictionary or str(offer.get("id", "")).is_empty() or bool(offer.get("open", false)):
		return false
	return str(offer.get("accept", "")) in [Offers.VENDOR_WARES, Offers.WARES]


## The wares among [param offers] (is_ware), in their order.
static func wares_of(offers: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for each: Variant in offers:
		if is_ware(each):
			out.append(each)
	return out


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


## The wares' purse line (voice's words): what you have; short of the least
## of them, what that costs.
static func wares_purse_words(gold: int, costs: Array[int]) -> String:
	if not costs.is_empty() and gold < costs[0]:
		if gold <= 0:
			return "You have no gold; nothing here costs less than %d." % costs[0]
		return "You have %d gold; nothing here costs less than %d." % [gold, costs[0]]
	return "You have %d gold." % gold
