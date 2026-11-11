extends Node
## The shared parts of the approved look (decision 854): UiGlass, UiSlot,
## UiPrice, UiTabs, UiLine each take their theme types, change them by state,
## and report what they show. No port: it opens no network; no scratch files.

var _failures := 0


func _ready() -> void:
	_test_glass()
	_test_price()
	_test_slot()
	await _test_refused()
	_test_tabs()
	_test_line()
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
	var got: Array = []
	slot.pressed.connect(func(which: UiSlot) -> void: got.append(which))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	slot._gui_input(click)
	_check(got == [slot], "a click is reported")
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
	line.say("Bought a spear for 1 gold.")
	_check(line.theme_type_variation == &"FootLine" and not line.refused, "what was done, in bone")
	line.refuse("You need 2 more gold.")
	_check(line.theme_type_variation == &"FootLineRefused" and line.refused and line.text == "You need 2 more gold.", "a refusal, in rust")
	line.clear()
	_check(line.text == "" and not line.refused, "cleared")
	line.queue_free()
