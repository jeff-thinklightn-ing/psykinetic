extends Node
## The shared parts of the approved look (decision 854; UiRow 860; the quest card's types 862; UiKeyCap 872): UiGlass, UiSlot,
## The shared parts of the approved look (decision 854; UiRow 860; the quest card's types 862; the name plates 865; the answer panel's 886): UiGlass, UiSlot,
## UiPrice, UiTabs, UiLine, UiRow each take their theme types, change them by state,
## and report what they show. No port: it opens no network; no scratch files.

var _failures := 0


func _ready() -> void:
	_test_glass()
	_test_price()
	_test_slot()
	await _test_refused()
	_test_tabs()
	_test_line()
	await _test_row()
	await _test_offer_row()
	await _test_quest_card()
	await _test_key_cap()
	_test_name_plates()
	await _test_answer()
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _test_glass() -> void:
	var pane := UiGlass.new()
	add_child(pane)
	_check(pane.theme_type_variation == &"Glass", "a pane is the theme's Glass")
	_check(pane.get_theme_stylebox(&"panel") is StyleBoxFlat, "the Glass panel resolves")
	var headless := DisplayServer.get_name() == "headless"
	_check(pane.frosted() == (not headless), "the frost is drawn, and never headless")
	UiGlass.set_frost(false)
	_check(not pane.frosted() and not UiGlass.frost, "the flat-tint setting turns the frost off on an open pane")
	UiGlass.set_frost(true)
	_check(pane.frosted() == (not headless), "and back on")
	pane.queue_free()


func _test_price() -> void:
	var chip := UiPrice.new()
	add_child(chip)
	chip.set_gold(3)
	_check(chip.theme_type_variation == &"PriceChip" and chip.mode == "gold" and chip.shown() == "3", "a gold price")
	chip.set_gold(8, true)
	_check(chip.short and chip.get_child(0).theme_type_variation == &"ChipPriceShort", "a price you can't pay is rust")
	var picture := PlaceholderTexture2D.new()
	chip.set_kind(picture, 3)
	_check(chip.mode == "kind" and chip.kind_picture == picture and chip.shown() == "3" and not chip.short, "a price in kind")
	chip.set_time("4 min")
	_check(chip.theme_type_variation == &"TimeChip" and chip.shown() == "4 min", "a time chip")
	chip.set_words("Free")
	_check(chip.theme_type_variation == &"TimeChip" and chip.mode == "words" and chip.shown() == "Free", "words without a coin")
	chip.queue_free()


func _test_slot() -> void:
	var slot := UiSlot.new()
	add_child(slot)
	_check(slot.theme_type_variation == &"Well", "a square at rest is a Well")
	_check(slot.custom_minimum_size.x == float(UiTheme.constant("square")), "a square is the theme's size")
	for name: String in UiSlot.STATES:
		slot.set_state(name)
		_check(slot.theme_type_variation == UiSlot.STATES[name] and slot.get_theme_stylebox(&"panel") is StyleBoxFlat,
			"state %s takes %s" % [name, UiSlot.STATES[name]])
	slot.set_state("in_hand")
	_check(slot.get_child(0).get_child(0).modulate.a < 1.0, "work in hand fades the picture")
	slot.set_state("rest")
	_check(slot.get_child(0).get_child(0).modulate.a == 1.0, "and rest restores it")
	# 854 amended (6): a held hand's square, a brass rim thinner than picked's, the Well's ground; a hover goes back to it.
	var hand: StyleBoxFlat = UiTheme.theme().get_stylebox(&"panel", &"WellHand")
	var picked: StyleBoxFlat = UiTheme.theme().get_stylebox(&"panel", &"WellPicked")
	var well: StyleBoxFlat = UiTheme.theme().get_stylebox(&"panel", &"Well")
	_check(hand.bg_color == well.bg_color and hand.border_width_top > well.border_width_top and hand.border_width_top < picked.border_width_top
		and absf(hand.border_color.h - UiTheme.color("brass").h) < 0.01,
		"a hand's square: the Well's ground, a brass rim between the Well's and picked's")
	slot.set_state("hand")
	slot.mouse_entered.emit()
	var lit := slot.state
	slot.mouse_exited.emit()
	_check(lit == "hover" and slot.state == "hand", "a hover on a hand's square goes back to hand (%s, then %s)" % [lit, slot.state])
	# 854 amended (7): an empty square's picture of what goes there, grey and faint, only while it is empty.
	var kind := PlaceholderTexture2D.new()
	slot.set_picture(null)
	slot.set_empty_picture(kind)
	var shown_empty := slot.empty_shown()
	slot.set_picture(PlaceholderTexture2D.new())
	var hidden_full := not slot.empty_shown()
	slot.set_picture(null)
	_check(shown_empty and hidden_full and slot.empty_shown() and slot._empty.modulate == UiTheme.color("slot_empty")
		and UiTheme.color("slot_empty").a < 0.5 and slot._empty.material is ShaderMaterial,
		"an empty square shows what goes there, grey and faint, and hides it under a thing")
	slot.set_empty_picture(null)
	_check(not slot.empty_shown(), "no picture of what goes there: nothing shown")
	slot.set_state("rest")
	slot.set_count(1)
	_check(slot.count_shown() == "", "a count of one isn't shown")
	slot.set_count(4)
	_check(slot.count_shown() == "4", "a count from two")
	slot.price().set_gold(2)
	_check(slot.price().visible and slot.price().shown() == "2", "a square's price")
	slot.set_mark(PlaceholderTexture2D.new())
	_check(slot.has_mark(), "a work's mark")
	slot.set_mark(null)
	_check(not slot.has_mark(), "no mark")
	slot.set_level(3, 10)
	_check(slot.price().shown() == "3/10" and slot.price().short and slot.level_colour() == UiTheme.color("rust"),
		"a stock well short: 3/10, the numbers and the bar rust")
	slot.set_level(9, 12)
	_check(slot.price().shown() == "9/12" and not slot.price().short and slot.level_colour() == UiTheme.color("brass"), "short: brass, the numbers bone")
	slot.set_level(228, 20)
	_check(slot.price().shown() == "228/20" and slot.level_short() == 0.0 and slot.level_colour() == UiTheme.color("friend"),
		"over enough: the true number, the bar full and no further")
	slot.set_level(2, 0)
	_check(slot.price().shown() == "2" and slot.level_enough == 0, "a thing the town wants none of: the count alone, no bar")
	slot.clear_level()
	_check(not slot._price.visible and slot.level_enough < 0, "no level")
	var got: Array = []
	slot.pressed.connect(func(which: UiSlot) -> void: got.append(which))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	slot._gui_input(click)
	_check(got == [slot], "a click is reported")
	# A click that frees the square (a rebuild) raises no error: it is accepted first.
	var gone := UiSlot.new()
	add_child(gone)
	gone.pressed.connect(func(which: UiSlot) -> void:
		remove_child(which)
		which.queue_free())
	gone._gui_input(click)
	_check(not gone.is_inside_tree(), "a click that takes the square away")
	slot.queue_free()


func _test_refused() -> void:
	var slot := UiSlot.new()
	add_child(slot)
	slot.set_state("picked")
	slot.flash_refused()
	_check(slot.state == "refused" and slot.theme_type_variation == &"WellRefused", "a refused click shows the rust rim")
	slot._process(UiSlot.REFUSED_SECONDS + 0.01)
	_check(slot.state == "picked", "then the state it had")
	slot.queue_free()
	await get_tree().process_frame


func _test_tabs() -> void:
	var tabs := UiTabs.new()
	add_child(tabs)
	var heads: Array[String] = ["Store", "Donate", "Locker"]
	tabs.set_tabs(heads)
	_check(tabs.visible and tabs.names() == heads and tabs.current == 0, "three places, the first lit")
	_check((tabs.get_child(0) as Button).button_pressed and (tabs.get_child(0) as Button).theme_type_variation == &"Tab", "a Tab, lit")
	var chose: Array = []
	tabs.chosen.connect(func(i: int) -> void: chose.append(i))
	tabs._choose(2)
	tabs._choose(2)
	_check(chose == [2] and tabs.current == 2, "a click on another place says so once")
	var one: Array[String] = ["Store"]
	tabs.set_tabs(one)
	_check(not tabs.visible, "one place shows no strip")
	tabs.queue_free()


func _test_line() -> void:
	var line := UiLine.new()
	add_child(line)
	line.size = Vector2(1600.0, 0.0)  # A window's width: autowrapped, a line a word at none.
	line.say("Bought a spear for 1 gold.")
	_check(line.theme_type_variation == &"FootLine" and not line.refused, "what was done, in bone")
	line.refuse("You need 2 more gold.")
	_check(line.theme_type_variation == &"FootLineRefused" and line.refused and line.text == "You need 2 more gold.", "a refusal, in rust")
	var said := line.get_combined_minimum_size().y
	line.clear()
	_check(line.text == "" and not line.refused, "cleared")
	_check(said > 0.0 and is_equal_approx(line.get_combined_minimum_size().y, said), "and still a line high (%s, %s)" % [said, line.get_combined_minimum_size().y])
	line.queue_free()


func _test_row() -> void:
	var row := UiRow.new()
	add_child(row)
	row.size.x = 1320.0
	_check(row.theme_type_variation == &"Row" and row.get_theme_stylebox(&"panel") is StyleBoxFlat, "an ask at rest is a Row")
	row.set_words("Walk Bram home")
	_check(row.words() == "Walk Bram home" and row.line() == "" and not row.has_price(), "words alone: no line, no chip")
	var alone := row.get_combined_minimum_size().y
	_check(alone >= UiRow.MIN_HEIGHT, "a row is a thing to hit (%s >= %s)" % [alone, UiRow.MIN_HEIGHT])
	row.set_line("The roof's half on.")
	_check(row.line() == "The roof's half on." and row.get_combined_minimum_size().y > alone, "the asker's line under the words makes it taller")
	row.set_line("")
	_check(row.line() == "" and is_equal_approx(row.get_combined_minimum_size().y, alone), "and none again")
	row.price().set_gold(6, true)
	_check(row.has_price() and row.price().shown() == "6" and row.price().short, "the gold, in rust when you can't pay")
	row.clear_price()
	_check(not row.has_price(), "no chip")
	for name: String in UiRow.STATES:
		row._show_state(name)
		_check(row.theme_type_variation == UiRow.STATES[name] and row.get_theme_stylebox(&"panel") is StyleBoxFlat,
			"state %s takes %s" % [name, UiRow.STATES[name]])
	row._show_state("rest")
	row.flash_refused()
	_check(row.state == "refused" and row.theme_type_variation == &"RowRefused", "a refused ask shows the rust rim")
	row._process(UiRow.REFUSED_SECONDS + 0.01)
	_check(row.state != "refused", "then it goes back")
	var got: Array = []
	row.pressed.connect(func(which: UiRow) -> void:
		got.append(which)
		remove_child(which)
		which.queue_free())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	row._gui_input(click)
	_check(got == [row] and not row.is_inside_tree(), "a click is reported, even one that takes the row away")
	await get_tree().process_frame


## A talk window's offer row (OfferRow) holds its price chip: built as BarterPanel._row builds it (the chip
## anchored centre right inside the button, so the button's own minimum never counts it), at every text
## scale the Options give, the row is at least the chip's height and the laid-out chip sits inside it
## (Hob's two offers, the second cut off at its foot: the coordinator, 11-16).
func _test_offer_row() -> void:
	for k: float in [1.0, 0.5, 1.5, 2.0]:
		UiTheme.apply_text_scale(k)
		var panel := BarterPanel.new()
		var row: Button = panel._row("Set the bone", 12, false)
		add_child(row)
		row.size = Vector2(900.0, 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var chip := row.get_node("Price") as Control
		var row_h := row.get_combined_minimum_size().y
		var chip_h := chip.get_combined_minimum_size().y
		print("OFFER ROW at text scale %.1f: the row %.0f px, the chip %.0f px; laid out, the row %.0f, the chip from %.0f to %.0f" % [k, row_h, chip_h, row.size.y, chip.position.y, chip.position.y + chip.size.y])
		_check(row_h >= chip_h, "an offer row holds its chip at text scale %.1f (%s >= %s)" % [k, row_h, chip_h])
		_check(chip.position.y >= 0.0 and chip.position.y + chip.size.y <= row.size.y + 0.5, "the laid-out chip sits inside its row at text scale %.1f" % k)
		row.queue_free()
		panel.free()
	UiTheme.apply_text_scale(1.0)
	await get_tree().process_frame


## The quest card's types (862): built as quest_panel builds it, at the mock's cap of
## four rows (a title, three lines, the return line), it fits the reserved rect, 600 x 316
## canvas units (C:/dev/review/ui-design/hud); a done line follows the colour set.
func _test_quest_card() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"QuestCard"
	var column := VBoxContainer.new()
	column.theme_type_variation = &"QuestColumn"
	card.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "Clear the crypt"
	column.add_child(title)
	var rows := VBoxContainer.new()
	rows.theme_type_variation = &"QuestRows"
	column.add_child(rows)
	for line: Array in [["Brand the Ox", &"QuestDone"], ["Robbers 5/5", &"QuestDone"], ["The fallen knight", &"QuestDone"]]:
		var item := HBoxContainer.new()
		item.theme_type_variation = &"QuestItem"
		var mark := Control.new()
		mark.custom_minimum_size = Vector2.ONE * UiTheme.constant(&"mark")
		item.add_child(mark)
		var label := Label.new()
		label.theme_type_variation = line[1]
		label.text = line[0]
		item.add_child(label)
		rows.add_child(item)
	var back := Label.new()
	back.theme_type_variation = &"QuestReturn"
	back.text = "Return to the fallen knight."
	column.add_child(back)
	add_child(card)
	await get_tree().process_frame
	var need := card.get_combined_minimum_size()
	_check(need.y <= 316.0, "the card at its cap fits its rect's height (%s <= 316)" % need.y)
	_check(need.x <= 600.0, "and its width (%s <= 600)" % need.x)
	_check(UiTheme.constant(&"mark") == 28, "a line's mark is 28 units")
	var done_label: Label = rows.get_child(0).get_child(1)
	_check(done_label.get_theme_color(&"font_color") == UiTheme.color(&"friend"), "a done line is the friend colour")
	UiTheme.apply_colours("distinct")
	_check(UiTheme.theme().get_color(&"font_color", &"QuestDone") == Color(Color.html(UiTheme.COLOUR_SETS["distinct"]["friend"]), 1.0),
		"a done line follows the distinct colour set")
	UiTheme.apply_colours("normal")
	_check(UiTheme.theme().get_color(&"font_color", &"QuestDone") == UiTheme.color(&"friend"), "and back")
	remove_child(card)
	card.queue_free()


## The hints' keys (872): a key's cap, a mouse button drawn, a row with its
## joins, and the strip of six in the HUD's reserved hints rect.
func _test_key_cap() -> void:
	var cap := UiKeyCap.new()
	cap.set_key("E")
	add_child(cap)
	await get_tree().process_frame
	_check(cap.theme_type_variation == &"KeyCap" and not cap.is_mouse(), "a key is a cap")
	var need := cap.get_combined_minimum_size()
	_check(need.x >= need.y and need.y >= 52.0, "a cap is at least square and at least 52 units tall (%s)" % need)
	cap.set_key("LMB")
	await get_tree().process_frame
	need = cap.get_combined_minimum_size()
	_check(cap.theme_type_variation == &"KeyMouse" and cap.is_mouse(), "a mouse button is drawn as a mouse")
	_check(need.x < need.y, "a mouse is taller than wide (%s)" % need)
	cap.queue_free()
	var keys := UiKeyCap.row(["Shift", "+", "LMB"])
	add_child(keys)
	_check(keys.get_child_count() == 3 and keys.get_child(0) is UiKeyCap and keys.get_child(1) is Label
		and (keys.get_child(1) as Label).theme_type_variation == &"KeyJoin" and (keys.get_child(2) as UiKeyCap).is_mouse(),
		"a row: a cap, the join's words, a mouse")
	keys.queue_free()
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"HintStrip"
	var rows := VBoxContainer.new()
	rows.theme_type_variation = &"HintRows"
	strip.add_child(rows)
	for line: Array in [[["LMB"], "walk there, or attack; on a friend, talk"], [["RMB"], "off hand; empty-handed, shove"],
			[["E"], "talk, or open a door"], [["I"], "your pack and gear"], [["Enter"], "say something"], [["M"], "the map"], [["H"], "every key"]]:
		var item := HBoxContainer.new()
		item.theme_type_variation = &"HintLine"
		var at := UiKeyCap.row(line[0])
		at.custom_minimum_size.x = 140.0
		item.add_child(at)
		var words := Label.new()
		words.theme_type_variation = &"HintFoot" if line[1] == "every key" else &"HintWords"
		words.text = line[1]
		item.add_child(words)
		rows.add_child(item)
	add_child(strip)
	await get_tree().process_frame
	need = strip.get_combined_minimum_size()
	_check(need.x <= 1160.0 and need.y <= 780.0, "the strip fits the HUD's hints rect (%s <= 1160 x 780)" % need)
	for type: StringName in [&"KeyText", &"KeyJoin", &"HintWords", &"HintFoot", &"HintGroup"]:
		_check(type in UiTheme.SIZED_TYPES, "%s follows the text scale" % type)
	strip.queue_free()
## Names over heads (865): one size at every depth, the nearer placed first, a
## plate that meets it stepped up one plate, a third that still meets faded; the
## 3D labels kept for their words but drawn on no layer while the HUD has them.
func _test_name_plates() -> void:
	var plates := UiNamePlates.new()
	add_child(plates)
	var font := plates.get_theme_font(&"font", &"NameText")
	var size := plates.get_theme_font_size(&"font_size", &"NameText")
	var plate := plates.get_theme_stylebox(&"panel", &"NamePlate")
	_check(size >= 42 and plate is StyleBoxFlat, "a name is at least 42 units (21 px at 1080) on its plate (%d)" % size)
	var near := {"key": 1, "text": "Agnes", "at": Vector2(1000, 600), "depth": 8.0, "plain": true}
	var far := {"key": 2, "text": "Hale", "at": Vector2(1010, 604), "depth": 9.0, "plain": true}
	var apart := {"key": 3, "text": "Rolf", "at": Vector2(2000, 600), "depth": 20.0, "plain": true}
	var placed := plates.place([far, apart, near], font, size, plate)
	_check(placed.size() == 3 and placed[0]["entry"] == near, "the nearest is placed first")
	var a: Rect2 = placed[0]["rect"]
	var b: Rect2 = placed[1]["rect"]
	var c: Rect2 = placed[2]["rect"]
	_check(is_equal_approx(a.end.y, 600.0 - UiNamePlates.LIFT) and is_equal_approx(a.get_center().x, 1000.0), "its foot just over the head, centred on it")
	_check(not a.intersects(b) and b.end.y <= a.position.y and placed[1]["alpha"] == 1.0, "the farther one that would meet it steps up a plate")
	_check(is_equal_approx(c.size.y, a.size.y) and placed[2]["alpha"] == 1.0, "one apart: the same size, untouched, at any depth")
	_check(plates.placed_rect(1) == a and plates.placed_rect(3) == c and plates.placed_rect(99) == Rect2(),
		"placed_rect: a key's plate as last placed, none for a key not shown (885 amended (1): the builder panel keeps off it)")
	var third := {"key": 4, "text": "Bram", "at": Vector2(1005, 602), "depth": 10.0, "plain": true}
	placed = plates.place([near, far, third], font, size, plate)
	_check(placed[2]["alpha"] == UiNamePlates.SHADED, "a third that still meets is faded")
	# The screen's edge (865, animation's Umbrage film: names between the lens
	# and the player grew and were clipped by the frame).
	var screen := Rect2(0, 0, 3840, 2160)
	var off_top := {"key": 5, "text": "Hazel", "at": Vector2(1500, -40), "depth": 3.0, "plain": true}
	var at_lens := {"key": 6, "text": "Maud", "at": Vector2(2500, 900), "depth": 0.8, "plain": true}
	var high := {"key": 7, "text": "Agnes", "at": Vector2(3830, 30), "depth": 2.5, "plain": true}
	var under := {"key": 8, "text": "Isolde", "at": Vector2(3800, 40), "depth": 4.0, "plain": true}
	placed = plates.place([off_top, at_lens, high, under], font, size, plate, screen)
	_check(placed.size() == 2 and placed[0]["entry"] == high and placed[1]["entry"] == under,
		"a head off the screen, or nearer the lens than NEAR, has no plate (%d placed)" % placed.size())
	var held: Rect2 = placed[0]["rect"]
	var inside := screen.grow(-UiNamePlates.EDGE)
	_check(inside.encloses(held) and is_equal_approx(held.size.y, a.size.y), "a head on the screen's edge keeps its plate whole, held inside it, the same size (%s)" % held)
	# The climb's top (the coordinator's plate rules, 11-14): the farther row, whose climb would leave the
	# screen's top, drops: not drawn.
	_check(bool(placed[1]["gone"]) and float(placed[1]["alpha"]) == 0.0, "and the farther one whose climb would leave the top drops, not drawn (gone %s, alpha %.2f)" % [placed[1]["gone"], placed[1]["alpha"]])
	_check(plates.placed_rect(int((placed[1]["entry"] as Dictionary).get("key", 0))) == Rect2(), "placed_rect: a dropped row is none")
	# The health bar in the name's row (865 amended (3), the approved C:/dev/review/ui-design/bar_mock): under
	# the name, centred, one size at every depth, its length by max hp within least and most.
	var gap := float(plates.get_theme_constant(&"gap", &"HpBar"))
	var per_hp := float(plates.get_theme_constant(&"per_hp", &"HpBar"))
	var least := float(plates.get_theme_constant(&"least", &"HpBar"))
	var most := float(plates.get_theme_constant(&"most", &"HpBar"))
	var hold := float(plates.get_theme_constant(&"hold", &"HpBar"))
	_check(gap > 0.0 and per_hp > 0.0 and least < most and hold >= 8.0 and plates.get_theme_stylebox(&"panel", &"HpBar") is StyleBoxFlat,
		"the theme's HpBar: gap %d, %d per hp, %d to %d long, hold %d, and its backing" % [gap, per_hp, least, most, hold])
	var hurt := {"key": 11, "text": "Agnes", "at": Vector2(1000, 600), "depth": 8.0, "plain": true, "bar": 1.0, "share": 0.5, "max_hp": 20}
	var small := {"key": 12, "text": "Imp", "at": Vector2(2000, 600), "depth": 30.0, "plain": true, "bar": 1.0, "share": 1.0, "max_hp": 2}
	var huge := {"key": 13, "text": "Hale", "at": Vector2(3000, 600), "depth": 9.0, "plain": true, "bar": 0.5, "share": 1.0, "max_hp": 1000000}
	var unbarred := {"key": 14, "text": "Rolf", "at": Vector2(1000, 1600), "depth": 9.0, "plain": true, "bar": 0.0, "max_hp": 20}
	placed = plates.place([hurt, small, huge, unbarred], font, size, plate)
	var keyed := {}  # Two share a depth, so their order is the sort's: look each up by its key.
	for one: Dictionary in placed:
		keyed[(one["entry"] as Dictionary)["key"]] = one
	var name_rect: Rect2 = keyed[11]["rect"]
	var bar_rect: Rect2 = keyed[11]["bar"]
	_check(is_equal_approx(bar_rect.position.y, name_rect.end.y + gap) and is_equal_approx(bar_rect.end.y, 600.0 - UiNamePlates.LIFT)
		and is_equal_approx(bar_rect.get_center().x, name_rect.get_center().x),
		"the bar just under the name, centred on it, its foot where the plate's was (%s under %s)" % [bar_rect, name_rect])
	_check(is_equal_approx(bar_rect.size.x, clampf(per_hp * 20.0, least, most)) and is_equal_approx((keyed[12]["bar"] as Rect2).size.x, least)
		and is_equal_approx((keyed[13]["bar"] as Rect2).size.x, most) and is_equal_approx((keyed[12]["bar"] as Rect2).size.y, bar_rect.size.y),
		"its length by max hp (20: %d), never under least nor over most, the same height far and near" % bar_rect.size.x)
	_check(keyed[14]["bar"] == null and is_equal_approx((keyed[14]["rect"] as Rect2).end.y, 1600.0 - UiNamePlates.LIFT), "no bar shown: the name alone, on its head")
	_check(plates.placed_rect(11) == name_rect.merge(bar_rect) and plates.placed_rect(14) == keyed[14]["rect"],
		"placed_rect: the row as drawn, the name merged with its bar; the name alone with no bar (builder's body_rects keeps off both)")
	_check(UiNamePlates.bar_fill(1.0) == &"fill_high" and UiNamePlates.bar_fill(0.4) == &"fill_mid" and UiNamePlates.bar_fill(0.2) == &"fill_low",
		"the fill by the share left")
	# The bar whenever it shows, its name drawn or not (the coordinator, 11-14): a hurt foe at arm's length,
	# nearer than NEAR, keeps its bar with no name; a body whose name the view hides keeps its bar; with no bar
	# shown, neither has a row. Off the screen, none.
	var arms := {"key": 31, "text": "Imp", "at": Vector2(1900, 300), "depth": 1.0, "plain": true, "bar": 1.0, "share": 0.4, "max_hp": 12}
	var hidden := {"key": 32, "text": "Imp", "at": Vector2(600, 1200), "depth": 30.0, "plain": true, "named": false, "bar": 1.0, "share": 0.5, "max_hp": 12}
	var quiet := {"key": 33, "text": "Imp", "at": Vector2(3000, 1200), "depth": 30.0, "plain": true, "named": false, "bar": 0.0, "max_hp": 12}
	var gone := {"key": 34, "text": "Imp", "at": Vector2(-50, 900), "depth": 6.0, "plain": true, "bar": 1.0, "share": 0.5, "max_hp": 12}
	placed = plates.place([arms, hidden, quiet, gone], font, size, plate, screen)
	_check(placed.size() == 2 and placed[0]["entry"] == arms and placed[1]["entry"] == hidden,
		"a hurt body at 1.0 m and one whose name is hidden each keep a row; one with no bar shown, or off the screen, has none (%d)" % placed.size())
	var arm_bar: Rect2 = placed[0]["bar"] if placed.size() > 0 and placed[0]["bar"] != null else Rect2()
	_check(placed.size() == 2 and not bool(placed[0]["named"]) and not bool(placed[1]["named"]) and arm_bar.has_area()
		and is_equal_approx(arm_bar.end.y, 300.0 - UiNamePlates.LIFT) and inside.encloses(arm_bar),
		"at arm's length: the bar drawn, no name, its foot just over the head, inside the screen (%s)" % arm_bar)
	_check(plates.placed_rect(31) == arm_bar and plates.placed_rect(33) == Rect2(), "placed_rect: a bar-only row is its bar; a body with no row, none")
	# Two rows brushing past each other (the no-twitch rule): the farther steps up on touching, stays up
	# till clear by hold, and comes to each place eased, never in a frame.
	var row_high := name_rect.size.y + gap + bar_rect.size.y
	var front := {"key": 21, "text": "Hale", "at": Vector2(1000, 600), "depth": 8.0, "plain": true, "bar": 1.0, "share": 1.0, "max_hp": 20}
	var back := {"key": 22, "text": "Tourbot", "at": Vector2(1000, 600.0 + row_high - 2.0), "depth": 9.0, "plain": true, "bar": 1.0, "share": 1.0, "max_hp": 20}
	var stand := func() -> float: return float((back["at"] as Vector2).y) - UiNamePlates.LIFT
	placed = plates.place([front, back], font, size, plate, Rect2(), 1.0)
	var top := (placed[0]["rect"] as Rect2).position.y
	_check((placed[1]["bar"] as Rect2).end.y <= top - UiNamePlates.GAP + 0.5, "touching by 2 px: the farther row steps up, bar and all")
	back["at"] = Vector2(1000, 600.0 + row_high + hold * 0.5)
	placed = plates.place([front, back], font, size, plate, Rect2(), 1.0)
	_check((placed[1]["bar"] as Rect2).end.y <= top - UiNamePlates.GAP + 0.5, "clear by %d px, under hold: it stays up" % (hold * 0.5))
	back["at"] = Vector2(1000, 600.0 + row_high + hold + 4.0)
	placed = plates.place([front, back], font, size, plate, Rect2(), 0.016)
	var easing := (placed[1]["bar"] as Rect2).end.y
	_check(easing > top and easing < stand.call() - 1.0, "clear by more than hold: it comes down, eased, part way in a frame (%.0f of %.0f)" % [easing, stand.call()])
	placed = plates.place([front, back], font, size, plate, Rect2(), 1.0)
	_check(is_equal_approx((placed[1]["bar"] as Rect2).end.y, stand.call()), "and settles on its own head")
	# Up, then met where it stands by a third (bar_row4: a row dropped to fade on its stand for 35 ms and stepped
	# back): it climbs on past the third (the coordinator's plate rules, 11-14: no two rows overlap) and fades,
	# never back to its stand.
	var low := {"key": 41, "text": "Hale", "at": Vector2(1000, 600), "depth": 8.0, "plain": true, "bar": 1.0, "share": 1.0, "max_hp": 20}
	var rising := {"key": 42, "text": "Tourbot", "at": Vector2(1000, 600.0 + row_high - 2.0), "depth": 10.0, "plain": true, "bar": 1.0, "share": 1.0, "max_hp": 20}
	placed = plates.place([low, rising], font, size, plate, Rect2(), 1.0)
	var low_top := (placed[0]["rect"] as Rect2).position.y
	var up_foot := (placed[1]["bar"] as Rect2).end.y
	var meeting := {"key": 43, "text": "Rolf", "at": Vector2(1000, low_top - UiNamePlates.GAP - 5.0 + UiNamePlates.LIFT), "depth": 9.0, "plain": true, "bar": 1.0, "share": 1.0, "max_hp": 20}
	placed = plates.place([low, rising, meeting], font, size, plate, Rect2(), 1.0)
	var kept: Dictionary = placed[2] if (placed[2]["entry"] as Dictionary)["key"] == 42 else placed[1]
	var rows3: Array[Rect2] = []
	for one: Dictionary in placed:
		rows3.append((one["rect"] as Rect2).merge(one["bar"] as Rect2))
	var apart3 := not rows3[0].intersects(rows3[1]) and not rows3[0].intersects(rows3[2]) and not rows3[1].intersects(rows3[2])
	_check((kept["bar"] as Rect2).end.y <= up_foot + 0.5 and absf(float(kept["alpha"]) - UiNamePlates.SHADED) < 0.01 and apart3,
		"met up there by a third: it climbs on past it (%.0f, was %.0f), faded (%.2f), no two rows overlapping (%s), never back to its stand for a frame" % [(kept["bar"] as Rect2).end.y, up_foot, float(kept["alpha"]), apart3])
	# His plate kept apart (the coordinator, 11-15: Rhea's row lay on mine, Tourbot's): a body beside him at his
	# depth, or nearer, steps off his plate; one nearer whose row lies on his body below his plate stays on its
	# stand (only a row behind him steps off his body); behind him, his body as before.
	var me := {"key": 51, "text": "Tourbot", "at": Vector2(1000, 600), "depth": 5.0, "plain": true, "own_body": Rect2(970, 600, 60, 300)}
	var beside := {"key": 52, "text": "Rhea", "at": Vector2(1030, 604), "depth": 5.0, "plain": true}
	var nearer := {"key": 53, "text": "Hale", "at": Vector2(980, 590), "depth": 3.0, "plain": true}
	var below := {"key": 54, "text": "Imp", "at": Vector2(1010, 800), "depth": 4.0, "plain": true}
	for other: Dictionary in [beside, nearer]:
		placed = plates.place([me, other], font, size, plate)
		var mine: Rect2 = placed[0]["rect"]
		var theirs: Rect2 = placed[1]["rect"]
		_check(placed[0]["entry"] == me and not mine.intersects(theirs) and theirs.end.y <= mine.position.y + 0.5,
			"%s at depth %.0f beside me (5): steps off my plate, above it (%s over %s)" % [other["text"], other["depth"], theirs, mine])
	placed = plates.place([me, below], font, size, plate)
	_check(is_equal_approx((placed[1]["rect"] as Rect2).end.y, 800.0 - UiNamePlates.LIFT) and float(placed[1]["alpha"]) == 1.0,
		"a nearer row lying on my body below my plate stays on its stand, whole (%s)" % placed[1]["rect"])
	var behind_me := {"key": 55, "text": "Bram", "at": Vector2(1010, 800), "depth": 9.0, "plain": true}
	placed = plates.place([me, behind_me], font, size, plate)
	_check(not (placed[1]["rect"] as Rect2).intersects(Rect2(970, 600, 60, 300)), "a row behind me still steps off my body (%s)" % placed[1]["rect"])
	remove_child(plates)
	plates.free()
	var client := Client3D.new()  # Never in the tree: the layers alone.
	var puppet := Node3D.new()
	var label := Label3D.new()
	label.name = "Name"
	puppet.add_child(label)
	var mark := Sprite3D.new()
	mark.name = "BossMark"
	label.add_child(mark)
	client._puppets[7] = puppet
	client.names_on_hud = true
	_check(label.layers == 0 and mark.layers == 0, "with the names on the HUD, the 3D name and skull draw nothing")
	# The night's body layer (858) tags a puppet's parts as they enter the tree,
	# often after the label was hidden: it leaves a part drawn nowhere as it is
	# (865 amended (1); the names showed twice over heads on main).
	puppet.set_meta("entity_id", 7)
	var body := MeshInstance3D.new()
	puppet.add_child(body)
	client._tag_body(label)
	client._tag_body(mark)
	client._tag_body(body)
	_check(label.layers == 0 and mark.layers == 0 and body.layers == 1 | Client3D.BODY_LAYER,
		"a hidden name and skull stay drawn nowhere when the night's body layer tags the puppet (%d, %d); its body takes the layer (%d)" % [label.layers, mark.layers, body.layers])
	client.names_on_hud = false
	_check(label.layers == 1 and mark.layers == 1, "and draw again without")
	puppet.free()
	client.free()
	_test_plate_heights()
	_test_plate_laid()


## 865 amended (8) (the coordinator's find on ui-design's beds pair: the sleeping keeper's plate 0.80 m past
## her head, out beyond the wall): a sleeper laid back by _lay (SLEEP_MIDDLE, the aside, the bed's height)
## and turned half round has its plate over its head bone as drawn, by Client3D._plate_shift on a real
## puppet (Body, Model, rig), within 0.1 m; standing, the same puppet's shift stays nought.
func _test_plate_laid() -> void:
	var lib := load("res://art/models/animations/goblin.res") as AnimationLibrary
	var client := Client3D.new()
	var puppet := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	puppet.add_child(body)
	var model := (load(Client3D.HUMAN["scene"]) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	body.add_child(model)
	add_child(puppet)
	puppet.position = Vector3(17.0, 0.0, 7.0)
	var rig := AnimRig.make(model, lib, 0.0, true, null)
	rig.loop("Idle", 0.0)
	puppet.set_meta("rig", rig)
	puppet.set_meta("faces", 0.0)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := skeleton.find_bone("Head")
	_plate_pose(skeleton, lib.get_animation("Idle"), 0.0)
	var stand := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	var row := {}
	var standing := client._plate_shift(puppet, row)
	_check(standing.length() < 0.001, "standing, the puppet's plate stays on its stand (%.3f)" % standing.length())
	# Asleep on a bed 0.28 m up, facing east (yaw 0), as the Mughouse's keeper lies (948).
	puppet.set_meta("work", "sleep")
	puppet.set_meta("bed_height", 0.28)
	client._lay(puppet, body, 0.0)
	rig.loop("Sleep_Side", 0.0)
	_plate_pose(skeleton, lib.get_animation("Sleep_Side"), 0.0)
	var lying := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	var plate := stand + client._plate_shift(puppet, row)
	_check(body.position.length() > 0.5, "the sleeper's Body is laid off its stand (%s)" % body.position)
	_check(plate.distance_to(lying) < 0.1, "asleep on a bed, the plate is over the head as drawn (%.3f m off: plate %s, head %s; the Body laid at %s)" % [
		plate.distance_to(lying), plate.snapped(Vector3.ONE * 0.01), lying.snapped(Vector3.ONE * 0.01), body.position.snapped(Vector3.ONE * 0.01)])
	puppet.free()
	client.free()


## 865 amended (2) (the coordinator, on playtest's bind7 and bind8: a kneeling companion's
## plate sat on the player's face, then 130 px off her head; its rulings of 11-13): a plate
## goes with its head, down and across together, once the head is PLATE_FOLLOW_FROM below
## the body's standing Idle head, fully from PLATE_FOLLOW_FULL, eased; the sitters and tired
## idles follow by clip, a dodge, roll, landing or sword attack never does. On the people's
## own body (human_m) and the game's clips.
func _test_plate_heights() -> void:
	var lib := load("res://art/models/animations/goblin.res") as AnimationLibrary
	var model := (load("res://art/models/characters/human_m.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := skeleton.find_bone("Head")
	var idle := Client3D.idle_head(skeleton, head, lib.get_animation("Idle"))
	_plate_pose(skeleton, lib.get_animation("Idle"), 0.0)
	_check(skeleton.get_bone_global_pose(head).origin.distance_to(idle) < 0.001,
		"the Idle head read off the clip is where the skeleton puts it (%s)" % idle)
	# Every clip whose head is held deep (its worst 0.4 s over 0.35 below Idle) is named on one of
	# the three lists, so a new one can't go unseen; a posture is additive, never a body's clip.
	var unnamed: Array[String] = []
	for clip: String in lib.get_animation_list():
		var plain := clip.trim_prefix(Client3D.PEOPLE_PREFIX)
		if plain in Client3D.POSTURES.values() or plain in Client3D.PLATE_FOLLOW_CLIPS or plain in Client3D.PLATE_HOLD_CLIPS \
				or plain in Client3D.PLATE_LOW_CLIPS:
			continue
		var worst := _plate_worst_window(skeleton, head, idle, lib.get_animation(clip))
		if worst > 0.35:
			unnamed.append("%s %.2f" % [clip, worst])
	_check(unnamed.is_empty(), "every clip held over 0.35 below Idle is on FOLLOW, HOLD or LOW (not: %s)" % [unnamed])
	# Upright bodies: the plate never moves over a whole clip, its own or its fight's.
	for clip: String in ["Idle", "Walk", "Jog_Short", "Sprint_Short", "Sword_Attack", "Axe_Sweep", "Shield_Bash",
			"Hit_Stomach", "Recoil", "Dodge_Left", "Roll", "Jump_Land"]:
		var most := 0.0
		var anim := lib.get_animation(clip)
		for i in 31:
			_plate_pose(skeleton, anim, anim.length * i / 30.0)
			most = maxf(most, Client3D.plate_shift(skeleton, head, idle, clip).length())
		_check(most == 0.0, "%s: the plate stays exactly on its stand over the whole clip (%.3f)" % [clip, most])
	# Low bodies: the plate is on the head.
	for clip: String in ["Kneel_Work", "Fixing_Kneeling", "Crouch_Idle", "GroundSit_Idle", "Sleep_Side", "Sitting_Idle",
			"Idle_Tired"]:
		var anim := lib.get_animation(clip)
		_plate_pose(skeleton, anim, anim.length * 0.5)
		var at := skeleton.get_bone_global_pose(head).origin
		var plate := idle + Client3D.plate_shift(skeleton, head, idle, clip)
		_check(plate.distance_to(at) < 0.01, "%s: the plate is over the head (%.3f m off)" % [clip, plate.distance_to(at)])
	# In the world, at the body's own turn and scale.
	_plate_pose(skeleton, lib.get_animation("Kneel_Work"), 0.0)
	var local := Client3D.plate_shift(skeleton, head, idle, "Kneel_Work")
	model.rotation.y = PI * 0.5
	model.scale = Vector3.ONE * 0.5
	var turned := Client3D.plate_shift(skeleton, head, idle, "Kneel_Work")
	_check(turned.is_equal_approx(Basis(Vector3.UP, PI * 0.5) * local * 0.5), "turned and scaled with the body (%s, %s)" % [local, turned])
	model.rotation.y = 0.0
	model.scale = Vector3.ONE
	# Getting up, and a sitter standing: the plate rides up with the head, eased, never a jump.
	var up := lib.get_animation("Get_Up")
	# Settled on the body as Get_Up begins (lying), the pose the rise starts from: a plate taken off any
	# other pose starts the rise a metre or more from its head and its first eased step is that gap's share.
	# Fixed 1/60 s steps: a long frame in the game closes more of the gap at once, as far as the head went.
	_plate_pose(skeleton, up, 0.0)
	var plate := Client3D.plate_shift(skeleton, head, idle, "Get_Up")
	var step := 0.0
	for i in int(up.length * 60.0) + 30:
		_plate_pose(skeleton, up, minf(i / 60.0, up.length))
		var was := plate
		plate = Client3D.eased_shift(plate, Client3D.plate_shift(skeleton, head, idle, "Get_Up"), 1.0 / 60.0)
		step = maxf(step, plate.distance_to(was))
	_check(step < 0.12, "getting up, no frame moves the plate more than 0.12 m (%.3f)" % step)
	_check(plate.length() < 0.02, "and it settles on the stand (%.3f)" % plate.length())
	_plate_pose(skeleton, lib.get_animation("Sitting_Idle"), 0.0)
	plate = Client3D.plate_shift(skeleton, head, idle, "Sitting_Idle")
	var seated := plate.length()
	_plate_pose(skeleton, lib.get_animation("Idle"), 0.0)
	var rose := Client3D.eased_shift(plate, Client3D.plate_shift(skeleton, head, idle, "Idle"), 1.0 / 60.0)
	_check(seated > 0.3 and rose.length() > seated * 0.7, "a sitter standing: one frame takes the plate only part way up (%.2f of %.2f m left)" % [rose.length(), seated])
	_check(Client3D.eased_shift(plate, Vector3.ZERO, Client3D.PLATE_EASE).length() < seated * 0.06, "and most of the way in PLATE_EASE")
	_check(Client3D.plate_follow(0.49, "Walk") == 0.0 and Client3D.plate_follow(0.65, "Walk") == 1.0
		and is_equal_approx(Client3D.plate_follow(0.575, "Walk"), 0.5), "the ramp: nothing at 0.49, half at 0.575, all at 0.65")
	# A low clip's band (look_plate4: Rhea's Kneel_Work at half depth, her head 0.42-0.47 below Idle).
	_check(Client3D.plate_follow(0.14, "Kneel_Work") == 0.0 and is_equal_approx(Client3D.plate_follow(0.225, "Kneel_Work"), 0.5)
		and Client3D.plate_follow(0.42, "Kneel_Work") == 1.0 and Client3D.plate_follow(0.47, "Kneel_Work") == 1.0,
		"a low clip's band: nothing at 0.14, half at 0.225, all of a half squat's 0.42 to 0.47")
	_check(Client3D.plate_follow(0.45, "Sword_Attack") == 0.0 and Client3D.plate_follow(0.45, "Walk") == 0.0,
		"an upright or held clip at the same 0.45 keeps its plate on its stand")
	model.free()
	var client := Client3D.new()
	var bare := Node3D.new()
	add_child(bare)
	var bare_row := {}
	_check(client._plate_shift(bare, bare_row) == Vector3.ZERO and client._plate_shift(bare, bare_row) == Vector3.ZERO, "a body with no skeleton or rig keeps the label's place")
	# Looked for again soon while newly missing (a body rebuilt as the camera nears), then once a second.
	bare_row["looked"] = Time.get_ticks_msec() - Client3D.PLATE_LOOK_SOON - 1
	_check(client._plate_shift(bare, bare_row) == Vector3.ZERO and int(bare_row["looked"]) >= Time.get_ticks_msec() - 50,
		"newly missing, it is looked for again after PLATE_LOOK_SOON ms")
	bare_row["missing"] = Time.get_ticks_msec() - Client3D.PLATE_LOOK_QUICK - 1
	var was_looked := Time.get_ticks_msec() - Client3D.PLATE_LOOK_SOON - 1
	bare_row["looked"] = was_looked
	client._plate_shift(bare, bare_row)
	_check(int(bare_row["looked"]) == was_looked, "missing past PLATE_LOOK_QUICK ms, only once a second")
	bare.free()
	client.free()


## [param skeleton] posed as [param anim] at [param t] (its tracks, the rest elsewhere).
func _plate_pose(skeleton: Skeleton3D, anim: Animation, t: float) -> void:
	skeleton.reset_bone_poses()
	for k in anim.get_track_count():
		var name := str(anim.track_get_path(k).get_concatenated_subnames())
		var b := skeleton.find_bone(name)
		if b < 0 and name.contains(":"):
			b = skeleton.find_bone(name.get_slice(":", name.get_slice_count(":") - 1))
		if b < 0:
			continue
		match anim.track_get_type(k):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(b, anim.position_track_interpolate(k, t))
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(b, anim.rotation_track_interpolate(k, t))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(b, anim.scale_track_interpolate(k, t))


## The highest mean drop of [param skeleton]'s [param head] below [param idle] over any 0.4 s
## of [param anim] (30 samples a second, a loop taken round its end).
func _plate_worst_window(skeleton: Skeleton3D, head: int, idle: Vector3, anim: Animation) -> float:
	var loops := anim.loop_mode != Animation.LOOP_NONE
	var count := maxi(2, int(ceil(anim.length * 30.0)))
	var drops := PackedFloat32Array()
	for i in count:
		_plate_pose(skeleton, anim, anim.length * i / float(count if loops else count - 1))
		drops.append(idle.y - skeleton.get_bone_global_pose(head).origin.y)
	var n := clampi(12, 1, count)
	var worst := -INF
	for s in (count if loops else count - n + 1):
		var sum := 0.0
		for i in n:
			sum += drops[(s + i) % count]
		worst = maxf(worst, sum / n)
	return worst


## Builder's answer panel's look (886): a building's code inline as a chip, its
## letter and figure apart; a line's marks all chips and its words kept; the
## window's close; the panel's types on the text scale.
func _test_answer() -> void:
	var rich := RichTextLabel.new()
	rich.theme_type_variation = &"Lines"
	rich.fit_content = true
	rich.custom_minimum_size.x = 1400.0
	add_child(rich)
	UiCodeChip.add_line(rich, "The door of [T1] temple at (190,\u00a0199); [F12] forge.")
	await get_tree().process_frame
	var said := rich.get_parsed_text()
	_check(said == "The door of \u00a0T\u00a01\u00a0 temple at (190,\u00a0199); \u00a0F\u00a012\u00a0 forge.",
		"a line's codes drawn as chips, letter and figure a hair apart, its words kept (%s)" % said.c_escape())
	# 886 amended (1) and (2): the hair is a no-break space in the regular face at HAIR_SCALE of the line
	# (the bold's hair space is wider than a space; the hair space U+200A breaks), so it is narrower than
	# a space; the chip's back has no side padding (it covered the words' spaces); builder's bullet type.
	var plain := rich.get_theme_font(&"normal_font")
	var size := rich.get_theme_font_size(&"normal_font_size")
	_check(plain.get_string_size("\u00a0", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(size * UiCodeChip.HAIR_SCALE)).x
		< plain.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5, "the hair, a small no-break space, is under half a space")
	_check(rich.get_theme_constant(&"text_highlight_h_padding") == 0, "the chip's back reaches no further than its own edge spaces")
	var theme := UiTheme.theme()
	_check(theme.get_type_variation_base(&"LineBullet") == &"Label" and theme.get_color(&"font_color", &"LineBullet") == UiTheme.color("text_dim")
		and theme.get_font_size(&"font_size", &"LineBullet") == theme.get_font_size(&"normal_font_size", &"Lines"),
		"LineBullet: a Label, dim, the Lines' size")
	# A person's chat band (the trader mock: 38 units a line, 52 between baselines): a RichTextLabel variation.
	_check(theme.get_type_variation_base(&"Chat") == &"RichTextLabel" and theme.get_font_size(&"normal_font_size", &"Chat") == 38
		and theme.get_font_size(&"bold_font_size", &"Chat") == 38 and theme.get_constant(&"line_separation", &"Chat") == 14,
		"Chat: a RichTextLabel at 38 with 14 between lines (the trader mock's 52 a line)")
	# The typing line's speech mark: the theme's size and colour, taking no press.
	var say := UiSayMark.new()
	add_child(say)
	await get_tree().process_frame
	_check(say.custom_minimum_size == Vector2(44, 42) and say.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and say.get_theme_color(&"mark", &"SayMark") == Color(UiTheme.color("brass_bright"), 0.86),
		"UiSayMark: 44 by 42 (its tail 12), brass_bright, no press (%s)" % [say.custom_minimum_size])
	say.queue_free()
	# Inside its field (ui's speech mark take beside the trader mock, 11-14): a SayLine LineEdit leaves the mark
	# its room (94 at the left: 24 in, 44 wide, the caret 26 after), stands about the mock's 94 tall, and the
	# mark, its child, sits 24 in and centred, lit while the field has the keys.
	var say_line := LineEdit.new()
	say_line.theme_type_variation = &"SayLine"
	say_line.size = Vector2(600, 10)
	add_child(say_line)
	var inner := UiSayMark.new()
	say_line.add_child(inner)
	await get_tree().process_frame
	var tall := say_line.get_combined_minimum_size().y
	_check(theme.get_type_variation_base(&"SayLine") == &"LineEdit" and say_line.get_theme_stylebox(&"normal").get_margin(SIDE_LEFT) == 94.0
		and say_line.get_theme_stylebox(&"focus").get_margin(SIDE_LEFT) == 94.0 and tall >= 88.0 and tall <= 100.0,
		"SayLine: 94 at its left for the mark and the caret's gap, %.0f tall (the mock's 94)" % tall)
	say_line.size = Vector2(600, tall)
	await get_tree().process_frame
	_check(inner.position == Vector2(24, roundf((tall - 42.0) / 2.0)), "the mark inside its field, 24 in, centred down it (%s)" % [inner.position])
	_check(inner.get_theme_color(&"mark_idle", &"SayMark").a < inner.get_theme_color(&"mark", &"SayMark").a, "resting, the mark dims; lit while the field has the keys")
	say_line.queue_free()
	_check(rich.get_theme_color(&"figure", &"CodeChip") != rich.get_theme_color(&"letter", &"CodeChip")
		and rich.get_theme_color(&"back", &"CodeChip").a > 0.5, "a chip: a dark back, the figure brighter than the letter")
	_check(UiCodeChip._split("T1") == PackedStringArray(["T", "1"]) and UiCodeChip._split("WS3") == PackedStringArray(["WS", "3"]),
		"a code splits into its letters and its figure")
	rich.queue_free()
	# 886 amended (2): a chip never breaks at a wrap. A narrow paragraph with a chip after every word, so
	# some chip falls where a line ends: each chip's letter and figure share a line, and at least one
	# chip sits at a line's edge (the wrap did reach a chip).
	var narrow := RichTextLabel.new()
	narrow.theme_type_variation = &"Lines"
	narrow.fit_content = true
	narrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narrow.custom_minimum_size.x = 260.0
	narrow.size.x = 260.0
	add_child(narrow)
	var words := ""
	for i in 24:
		words += "%s [%s%d] " % ["ab".repeat(1 + i % 4), "TSHI"[i % 4], 1 + i % 9]
	UiCodeChip.add_line(narrow, words.strip_edges())
	await get_tree().process_frame
	await get_tree().process_frame
	var parsed := narrow.get_parsed_text()
	var split_chips := 0
	var at_line_start := 0
	var chips := 0
	for at in parsed.length() - 2:
		if parsed[at] == " " and parsed[at + 1] in "TSHI" and parsed[at + 2] == " ":
			chips += 1
			var line := narrow.get_character_line(at + 1)
			if narrow.get_character_line(at + 3) != line:
				split_chips += 1
			# A chip at a line's edge: the wrap falls just before it or just after it (the line breaker keeps
			# it with the word before, so mostly after: its next word starts the next line).
			if (at > 0 and narrow.get_character_line(at - 1) != narrow.get_character_line(at)) \
					or (at + 6 < parsed.length() and narrow.get_character_line(at + 6) != narrow.get_character_line(at + 4)):
				at_line_start += 1
	_check(chips == 24 and split_chips == 0 and at_line_start > 0 and narrow.get_line_count() > 4,
		"a chip at a wrap stays whole: %d chips, %d split, %d at a line's edge, %d lines" % [chips, split_chips, at_line_start, narrow.get_line_count()])
	narrow.queue_free()
	var close := UiClose.new()
	var pressed := [0]
	close.pressed.connect(func() -> void: pressed[0] += 1)
	add_child(close)
	await get_tree().process_frame
	_check(close.get_combined_minimum_size().x >= 72.0 and close.theme_type_variation == &"Close", "a close is a 72-unit target (%s)" % close.get_combined_minimum_size())
	close.pressed.emit()
	_check(pressed[0] == 1 and close.text.is_empty(), "a close presses, and has no words: its x is drawn")
	close.queue_free()
	for type: StringName in [&"Body", &"Note", &"FaultHead", &"FoldLink", &"WordsRefused", &"WorkingDots"]:
		_check(type in UiTheme.SIZED_TYPES, "%s follows the text scale" % type)
	# 886 amended (3), the builder panel's spacing (the mock beside the hosted sheet, 11-14): the rule under a
	# panel's head (2 units, the rim's bone faint, 22 its height), the key groups 40 apart, the answer pane 34
	# under its keys and otherwise the Glass pane, the working line's dots in brass_bright.
	var rule := HSeparator.new()
	rule.theme_type_variation = &"HeadRule"
	add_child(rule)
	var line_style := rule.get_theme_stylebox(&"separator") as StyleBoxLine
	_check(line_style != null and line_style.thickness == 2 and line_style.color.a < 0.3 and line_style.color.r > 0.9
		and rule.get_theme_constant(&"separation") == 22, "HeadRule: a 2-unit faint bone line, 22 high")
	rule.queue_free()
	var groups := HBoxContainer.new()
	groups.theme_type_variation = &"KeyGroups"
	add_child(groups)
	_check(groups.get_theme_constant(&"separation") == 40, "KeyGroups: 40 between a key and its words and the next key")
	groups.queue_free()
	var answer_pane := PanelContainer.new()
	answer_pane.theme_type_variation = &"AnswerGlass"
	add_child(answer_pane)
	var answer_style := answer_pane.get_theme_stylebox(&"panel") as StyleBoxFlat
	var glass_style := theme.get_stylebox(&"panel", &"Glass") as StyleBoxFlat
	_check(answer_style != null and glass_style != null and answer_style.content_margin_bottom == 34.0
		and answer_style.content_margin_left == glass_style.content_margin_left and answer_style.content_margin_top == glass_style.content_margin_top
		and answer_style.bg_color == glass_style.bg_color and answer_style.border_color == glass_style.border_color
		and answer_style.corner_radius_top_left == glass_style.corner_radius_top_left and answer_style.shadow_size == glass_style.shadow_size,
		"AnswerGlass: the Glass pane with 34 under its keys")
	answer_pane.queue_free()
	_check(theme.get_type_variation_base(&"WorkingDots") == &"Label" and theme.get_color(&"font_color", &"WorkingDots") == UiTheme.color("brass_bright"),
		"WorkingDots: a Label in brass_bright")
	var quiet := ScrollContainer.new()
	quiet.theme_type_variation = &"QuietScroll"
	quiet.custom_minimum_size = Vector2(800.0, 400.0)
	var grid := GridContainer.new()
	grid.columns = 4
	quiet.add_child(grid)
	var squares: Array[UiSlot] = []
	for k in 8:
		var square := UiSlot.new()
		square.price().set_gold(k + 1)
		grid.add_child(square)
		squares.append(square)
	add_child(quiet)
	for i in 3:
		await get_tree().process_frame
	_check(quiet.get_theme_stylebox(&"panel") is StyleBoxEmpty, "a quiet scroll draws no box of its own (886)")
	var off := 0
	for square in squares:
		var chip := square._price
		if not chip.visible or chip.position.x + chip.size.x < square._face.size.x * 0.75 or chip.position.y + chip.size.y < square._face.size.y * 0.75:
			off += 1
	_check(off == 0, "a square in a grid in a scroll has its price chip bottom right once laid out (%d off)" % off)
	quiet.queue_free()
	# The talk box's marks (427 amended (1), the coordinator's ruling 11-12): a notice's mark
	# rust in the bold sans, its words bone at full strength; a speaker's name brass in the
	# bold sans (the serif's hairlines go soft at the talk box's size).
	_check(theme.get_color(&"mark", &"TalkNotice") == UiTheme.color("rust") and theme.get_color(&"words", &"TalkNotice").a == 1.0
		and theme.get_font(&"mark_font", &"TalkNotice") == UiTheme.font("sans_bold"), "a notice's mark rust bold sans, its words full bone")
	_check(theme.get_color(&"name", &"TalkName") == UiTheme.color("brass_bright") and theme.get_font(&"name_font", &"TalkName") == UiTheme.font("sans_bold"),
		"a speaker's name brass bold sans")
	var block := PanelContainer.new()
	block.theme_type_variation = &"FaultBlock"
	add_child(block)
	await get_tree().process_frame
	var style := block.get_theme_stylebox(&"panel") as StyleBoxFlat
	_check(style != null and style.border_width_left > style.border_width_top, "a fault block has its broad left edge")
	block.queue_free()
