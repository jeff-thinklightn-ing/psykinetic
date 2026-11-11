extends Node
## The shared parts of the approved look (decision 854; UiRow 860; the quest card's types 862): UiGlass, UiSlot,
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
	await _test_quest_card()
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
