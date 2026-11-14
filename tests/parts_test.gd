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
	var faded: Rect2 = placed[1]["rect"]
	_check(inside.encloses(faded) and placed[1]["alpha"] == UiNamePlates.SHADED, "and one that can't step up past the top fades in place, still inside (%s)" % faded)
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
	# The HP bar rides the plate's eased shift (865 amended (2)): the plate's own row while it is plated...
	var now := Time.get_ticks_msec()
	var low := Vector3(0.1, -0.6, 0.0)
	client._plate_rows[7] = {"key": 7, "shift": low, "plated_ms": now}
	_check(client._bar_shift(7, bare, now) == low, "a plated body's bar takes its plate's shift")
	# ...else (the own body, a name off) it eases the row itself: part way in a frame, toward the head's.
	client._plate_rows[7] = {"key": 7, "shift": low, "plated_ms": now - 500, "bar_ms": now - 16}
	var eased := client._bar_shift(7, bare, now)
	_check(eased.length() > 0.0 and eased.length() < low.length(), "unplated, the bar eases on its own (%.3f of %.3f m)" % [eased.length(), low.length()])
	var basis := Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * 0.5)
	var place := Client3D.bar_place(2.0, basis, low)
	_check((basis * place).is_equal_approx(basis * Vector3.UP * 2.0 + low), "the bar sits its shift from its stand in the world, at the body's turn and scale (%s)" % place)
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
	for type: StringName in [&"Body", &"Note", &"FaultHead", &"FoldLink", &"WordsRefused"]:
		_check(type in UiTheme.SIZED_TYPES, "%s follows the text scale" % type)
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
