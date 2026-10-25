extends Node
## The core screens (ui's step 2): the main menu's buttons, the connect
## screen's fields, states and buttons, the pause panel, Esc's order
## (what is open closes first, then the pause), and the options' Window,
## Resolution, Controls and hints choices writing to Net and settings.cfg.
## The in-game panels (step 3): the item tip's lines from a slot note, the
## talk panel's pin, fade and channel, the context hint and the place.
## Run it with tests/run.ps1 or run.sh. Prints PASS/FAIL per assertion and
## quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17840)  # Its own, beside the other tests'.
	Client3D.feel_path = ""  # 673 step 2: the defaults, whatever the tuned file holds.
	_test_menu()
	_test_connect_screen()
	_test_game_menu()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await _test_escape()
	_test_options_choices()
	_test_item_tip()
	_test_stacks_ui()
	await _test_talk_panel()
	_test_context_and_place()
	_test_talk_no_panel()
	_test_sim_reads()
	_test_minimap_turn()
	_test_revive_reads()
	_test_screenshot_key()
	_test_aim()
	_test_down_screen()
	_test_card_page()
	_test_counter_panel()
	_test_world_map()
	_test_town_sheet()  # After the map's test: the sheet's names build the map's graph (place_words).
	await _test_deal_window()
	_test_door_note()
	_test_arrival_card()
	_test_room_names()
	_test_admin_panel()
	_test_tuning_panel()
	_test_access()
	_test_keys()
	_test_barter()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_menu() -> void:
	print("== the main menu: Play, Options, Quit, the version ==")
	var menu := MainMenu.new()
	add_child(menu)
	var played := [false]
	menu.play_pressed.connect(func() -> void: played[0] = true)
	menu.play.pressed.emit()
	_check(played[0], "Play asks Main to play")
	_check(menu.options.text == "Options" and menu.quit.text == "Quit", "Options and Quit are there")
	_check(menu.version.text == "v%s" % Net.version, "the version in the corner (%s)" % menu.version.text)
	menu.set_status("no answer")
	_check(menu.status.visible and menu.status.text == "no answer", "the server's status under the buttons")
	menu.queue_free()


func _test_connect_screen() -> void:
	print("== the connect screen: states, failures, the fields ==")
	var screen := ConnectScreen.new()
	add_child(screen)
	screen.set_state("connecting to 10.0.0.1:7777")
	_check(screen.state_shown() == "connecting to 10.0.0.1:7777" and screen.buttons_shown().is_empty(),
		"while connecting: the words, no buttons")
	screen.set_state("the server did not answer", true)
	_check(screen.failed and screen.buttons_shown() == ["Change server", "Retry"],
		"a failure offers Change server and Retry (%s)" % [screen.buttons_shown()])
	screen.has_menu = true
	screen.set_state("the server is gone", true)
	_check(screen.buttons_shown() == ["Back", "Change server", "Retry"], "and Back when there is a menu")
	var retried := [false]
	screen.retry_pressed.connect(func() -> void: retried[0] = true)
	screen._retry.pressed.emit()
	_check(retried[0], "Retry asks Main to try again")
	screen.edit()
	_check(screen.editing and screen.buttons_shown() == ["Back", "Connect"] and screen.state_shown() == "",
		"Change server: the fields, Connect and Back")
	var got := []
	screen.submitted.connect(func(address: String, port: int, token: String, player_name: String) -> void:
		got.assign([address, port, token, player_name]))
	screen._address.text = ""
	screen._submit()
	_check(got.is_empty() and screen._error.text != "", "an empty address is refused in words (%s)" % screen._error.text)
	screen._address.text = "10.0.0.2"
	screen._port.text = "7778"
	screen._token.text = "secret"
	screen._name.text = "  Tester "
	screen._submit()
	_check(got == ["10.0.0.2", 7778, "secret", "Tester"], "filled in: submitted trimmed (%s)" % [got])
	screen.set_progress(0.3, "downloading v0.1.150: 34 of 112 MB")
	_check(screen.progressing and screen.buttons_shown() == ["Cancel"] and is_equal_approx(screen.progress_shown(), 0.3),
		"an update's progress: the bar at 0.3, Cancel alone (%s)" % [screen.buttons_shown()])
	screen.set_progress(-1.0, "unpacking v0.1.150")
	_check(screen.progress_shown() < 0.0 and screen.state_shown() == "unpacking v0.1.150", "unknown progress: the words, no bar")
	var cancelled := [false]
	screen.cancel_pressed.connect(func() -> void: cancelled[0] = true)
	screen._cancel.pressed.emit()
	_check(cancelled[0], "Cancel asks Main to stop it")
	screen.set_state("the download stopped", true)
	_check(not screen.progressing and "Cancel" not in screen.buttons_shown(), "a state after it: Cancel gone")
	screen.set_progress(0.9, "unpacking v0.1.150")
	screen.set_progress(-1.0, "")
	_check(not screen.progressing and "Cancel" not in screen.buttons_shown() and screen.progress_shown() < 0.0
			and screen.state_shown() == "unpacking v0.1.150",
		"progress over (maps' end call): the bar and Cancel go, the last words stay")
	screen.set_status("online, v0.1.150, 3 players")
	_check(screen.status_shown() == "online, v0.1.150, 3 players", "the server's status shown under the fields")
	var dot := " · "
	_check(Main.server_status_words({"ok": true, "version": "0.1.150", "players": 3, "accepting": true, "compatible": true})
			== "online%sv0.1.150%s3 players" % [dot, dot]
			and Main.server_status_words({"ok": true, "version": "0.1.151", "players": 1, "accepting": true, "compatible": false})
			== "online%sv0.1.151%s1 player%sout of date: updates when you join" % [dot, dot, dot]
			and Main.server_status_words({"ok": false, "why": "no answer"}) == "status unknown"
			and Main.server_status_words({"ok": false, "why": "bad address"}) == "bad address",
		"the status in words from maps' answer")
	screen.queue_free()


func _test_game_menu() -> void:
	print("== the game menu (no pause: the world goes on) ==")
	var menu := GameMenu.new()
	add_child(menu)
	_check(not menu.visible, "hidden until Esc")
	menu.open(true, "The Castle")
	_check(menu.visible and menu.close.has_focus() and menu.title_shown() == "The Castle", "open: the zone's name, Close focused")
	menu.open(true)
	_check(menu.title_shown() == "Menu", "no name: Menu")
	var closed := [false]
	menu.close_pressed.connect(func() -> void: closed[0] = true)
	menu.close.pressed.emit()
	_check(closed[0], "Close asks Main to close it")
	_check(menu.close.text == "Close" and menu.leave.text == "Leave" and menu.quit.text == "Quit", "nothing says pause or resume")
	menu.queue_free()


func _test_escape() -> void:
	await get_tree().process_frame
	print("== Esc: what is open closes first, then the pause ==")
	_check(_main.game_menu == null, "no game menu before the first Esc")
	_main.escape()
	_check(_main.game_menu != null and _main.game_menu.visible, "Esc with nothing open: the game menu")
	await get_tree().process_frame
	var rect: Rect2 = _main.game_menu.get_global_rect()
	var middle := get_viewport().get_visible_rect().get_center()
	_check(rect.get_center().distance_to(middle) < 4.0 and rect.size.y > 100.0,
		"in the middle of the screen (%s, middle %s)" % [rect, middle])
	_main.escape()
	_check(not _main.game_menu.visible, "Esc again: closed")
	_main.toggle_options()
	_check(_main.options_panel.visible, "O: the options open")
	_main.escape()
	_check(not _main.options_panel.visible and not _main.game_menu.visible, "Esc closes the options, not the menu")
	_main.escape()
	_check(_main.game_menu.visible, "then the menu")
	_main.game_menu.options.pressed.emit()
	_check(_main.options_panel.visible, "the menu's Options opens them")
	_main.escape()
	_main.escape()
	_check(not _main.options_panel.visible and not _main.game_menu.visible, "and two Escs close both")


func _test_options_choices() -> void:
	print("== the options' Window, Resolution, Controls and hints ==")
	var panel: OptionsPanel = _main.options_panel
	var kept: Array = [Net._settings_override, Net.player_id, Net.player_name, Net.controls, Net.hints, Net.window_size]
	Net._settings_override = preload("res://tests/test_ports.gd").scratch_path("ui_test.cfg")
	Net.save_settings("127.0.0.1", 17841, "", Net.player_name)  # A file to rewrite, as a client has.
	_check(panel.choices.has("window") and panel.choices.has("controls") and panel.choices.has("hints"),
		"a choice row each for the window, the controls and the controls list")
	(panel.choices["controls"]["buttons"]["wasd"] as Button).pressed.emit()
	_check(Net.controls == "wasd" and "controls=wasd" in FileAccess.get_file_as_string(Net._settings_override),
		"WASD picked: Net and settings.cfg follow")
	(panel.choices["controls"]["buttons"]["click"] as Button).pressed.emit()
	_check(Net.controls == "click" and "controls=click" in FileAccess.get_file_as_string(Net._settings_override),
		"and back to click")
	var told := [null]
	panel.hints_changed.connect(func(shown: bool) -> void: told[0] = shown)
	(panel.choices["hints"]["buttons"]["off"] as Button).pressed.emit()
	_check(told[0] == false and not Net.hints and "hints=off" in FileAccess.get_file_as_string(Net._settings_override),
		"the controls list hidden: Main told, Net and settings.cfg follow")
	(panel.choices["hints"]["buttons"]["on"] as Button).pressed.emit()
	_check(told[0] == true and Net.hints, "and shown again")
	var index := -1
	for i in panel.resolution.item_count:
		if panel.resolution.get_item_metadata(i) == Vector2i(1280, 720):
			index = i
	panel.resolution.item_selected.emit(index)
	_check(index >= 0 and Net.window_size == Vector2i(1280, 720)
			and "window_width=1280" in FileAccess.get_file_as_string(Net._settings_override),
		"1280 x 720 picked: the windowed size and settings.cfg follow")
	panel.toggle()
	_check(panel.resolution.get_item_metadata(panel.resolution.selected) == Vector2i(1280, 720)
			and (panel.choices["window"]["buttons"]["windowed"] as Button).button_pressed == not Net.fullscreen,
		"shown again: the choices say what is set")
	panel.toggle()
	DirAccess.remove_absolute(Net._settings_override)
	Net._settings_override = kept[0]
	Net.player_id = kept[1]
	Net.player_name = kept[2]
	Net.controls = kept[3]
	Net.hints = kept[4]
	Net.window_size = kept[5]


## A stack on the interface (619, ui's side): the count in the slot's corner,
## a shift-drag's one unit, the barter's shift-click, the pile's words.
func _test_stacks_ui() -> void:
	print("== stacks on the interface (619, ui's side): the corner count, one unit by shift, the pile's words ==")
	_check(PackPanel.count_words(5) == "5" and PackPanel.count_words(1) == "" and PackPanel.count_words(0) == "",
		"the corner badge: the number above one, nothing for one or none")
	# The armour slot (622, ui's side): the seventh box beside the hands, brass-edged and marked A, a drag's target.
	var pack_for_armour: PackPanel = _main.pack_panel
	if pack_for_armour != null:
		for mine: bool in [true, false]:
			var row: HBoxContainer = pack_for_armour._player_row if mine else pack_for_armour._other_row
			var armour_box: PackPanel.SlotBox = row.get_child(Items.ARMOUR)
			var marks: Array[String] = []
			for child in armour_box.get_children():
				if child is Label and child != armour_box.label and child != armour_box.count:
					marks.append((child as Label).text)
			_check(row.get_child_count() >= Items.CARRIED and armour_box.index == Items.ARMOUR and armour_box.theme_type_variation == &"HandSlot" and marks == ["A"],
				"%s row: the seventh box is the armour worn, edged like the hands, marked A" % ["the player's" if mine else "the other"])
		var right_box: PackPanel.SlotBox = pack_for_armour._player_row.get_child(Items.RIGHT_HAND)
		var armour_data := {"slots_of": _main._local_player(), "slot": 0, "count": 0}
		_check(_main._local_player() == null or (pack_for_armour._player_row.get_child(Items.ARMOUR) as PackPanel.SlotBox)._can_drop_data(Vector2.ZERO, armour_data)
				and right_box._can_drop_data(Vector2.ZERO, armour_data),
			"a drag lands on the armour box or a hand alike: the server decides and words a refusal (World.slot_refused)")
	_check(Main.pile_words(PackedStringArray(["herbs", "herbs", "herbs", "herbs", "herbs"])) == "5 herbs"
			and Main.pile_words(PackedStringArray(["herbs", "herbs", "dagger"])) == "2 herbs and 1 more"
			and Main.pile_words(PackedStringArray(["herbs", "dagger", "rope"])) == "herbs and 2 more"
			and Main.pile_words(PackedStringArray(["herbs", "herbs"]), 12) == "12 gold and 2 herbs",
		"the pile's words count the first kind: 5 herbs; 2 herbs and 1 more; 12 gold and 2 herbs")
	_check(BarterPanel.stack_words(3, 5) == "3 of 5 to give" and BarterPanel.stack_words(0, 5) == "" and BarterPanel.stack_words(1, 1) == "",
		"the barter hover's stack words: 3 of 5 to give; nothing for none selected or a lone thing")
	_check(BarterPanel.stack_units({"slot": 0, "uid": 401, "id": "herbs", "uids": [401, 402, 403], "count": 3}) == [401, 402, 403]
			and BarterPanel.stack_units({"slot": 0, "uid": 401, "id": "herbs"}) == [401],
		"a stack's units from the entry's uids; a lone thing's its uid")
	var panel: BarterPanel = _main.barter_panel
	var pack: PackPanel = _main.pack_panel
	if panel != null and pack != null:
		panel.open(null, "Snagfin")
		panel.show_barter({"shop": "", "gold": 12, "goods": [], "buys": {"herbs": {"gold": 2, "up_to": 10}}, "fenced": {},
			"pack": [{"slot": 0, "uid": 401, "id": "herbs", "uids": [401, 402, 403], "count": 3}, {"slot": 1, "uid": 404, "id": "dagger"}], "why": ""})
		_check(panel.pack_entry(402).get("slot", -1) == 0 and panel.pack_entry(403).get("slot", -1) == 0, "any unit of the stack finds its entry")
		_check(panel._select_mine(true, 0, true) and panel.give.keys() == [401], "a shift-click gives one unit")
		panel._hover_mine(true, 0)
		_check(panel.hover_shown() == "pays 2 gold, 1 of 3 to give", "the hover: pays 2 gold, 1 of 3 to give (%s)" % panel.hover_shown())
		_check(panel._select_mine(true, 0, true) and panel.give.keys() == [401, 402], "another shift-click: two")
		_check(panel._select_mine(true, 0, true) and panel.give.size() == 3 and panel._select_mine(true, 0, true) and panel.give.keys() == [401, 402],
			"all three given, a shift-click takes one back")
		_check(panel._select_mine(true, 0, false) and panel.give.is_empty(), "a plain click on a part-given stack unselects it all")
		_check(panel._select_mine(true, 0, false) and panel.give.size() == 3 and panel.gives_shown() == ["herbs", "herbs", "herbs"],
			"a plain click on an unselected stack gives it whole, a uid per unit")
		panel.show_barter({"shop": "", "gold": 12, "goods": [], "buys": {"herbs": {"gold": 2, "up_to": 2}}, "fenced": {},
			"pack": [{"slot": 0, "uid": 401, "id": "herbs", "uids": [401, 402, 403], "count": 3}], "why": ""})
		for uid: int in [401, 402, 403]:
			panel.give.erase(uid)
		_check(panel._select_mine(true, 0, false) and panel.give.size() == 2 and panel.hover_shown() == "the town has enough of that",
			"the town takes two: a plain click gives two and the hover says why not the third")
		panel.close()
		# A real stack in the host's pack: the badge reads its count, a shift-drag carries count 1.
		var player: GridEntity = _main._local_player()
		var free := player.slots.find("") if player != null and World.items != null else -1
		if free >= 0:
			var herbs: Array[int] = []
			for i in 3:
				herbs.append(World.items.mint("herbs", "gathered"))
				World.put_on_ground(herbs[i], player.tile)
			World.try_pick_up(player, player.tile)
			var slot := World.slot_of_unit(player, herbs[0])
			pack._refresh()
			_check(slot >= 0 and World.slot_count(player, slot) == 3 and pack.count_in(true, slot) == "3",
				"three herbs picked up: the slot's corner reads 3 (%s)" % pack.count_in(true, slot))
			var box: PackPanel.SlotBox = pack._player_row.get_child(slot)
			var whole: Variant = box.drag_payload()
			PackPanel.test_shift = true
			var one: Variant = box.drag_payload()
			PackPanel.test_shift = false
			_check(whole is Dictionary and int(whole.get("count", -1)) == 0 and one is Dictionary and int(one.get("count", -1)) == 1,
				"a drag carries the whole slot, a shift-drag one unit")
			var sent: Array = []
			var kept_transfer: Callable = pack.transfer
			pack.transfer = func(from: GridEntity, from_slot: int, to: GridEntity, to_slot: int, count: int) -> void:
				sent.append(count)
			pack.drop(player, slot, player, free if free != slot else player.slots.find(""), 1)
			pack.drop(player, slot, player, slot)
			pack.transfer = kept_transfer
			_check(sent == [1, 0], "the panel's drop passes the count on to the transfer (%s)" % [sent])
			while World.slot_count(player, slot) > 0:
				World.items.end(World.take_item(player, player, slot), "gone")
			pack._refresh()
			_check(pack.count_in(true, slot) == "", "emptied: no badge")
		else:
			print("  (no host player with a free slot here: the badge's live checks skipped)")


func _test_item_tip() -> void:
	print("== the item tip: a thing's name, kind, strength, marks, kills and story from its note ==")
	var dagger := ""
	for id: String in Items.ids():
		if str(Items.def(id).get("verb", {}).get("kind", "")) == "backstab":
			dagger = id
	_check(not dagger.is_empty(), "a dagger in the catalog (%s)" % dagger)
	var note := "Wren's dagger (quiet, %s), imp-bane
felled 12 imps
story: carried by Wren for 3 days; named at the ford" % World.KEPT_MARK
	var rows := ItemTip.lines_for(dagger, note)
	var styles: Array[String] = []
	for row in rows:
		styles.append(row["style"])
	_check(rows.size() >= 7 and rows[0]["text"] == "Wren's dagger" and rows[0]["style"] == "name"
			and rows[1]["text"] == Items.name_of(dagger),
		"a named thing: its name first, in brass, the catalog name under it (%s)" % [rows])
	_check("strength" in styles and "warn" in styles and "mark" in styles and "kills" in styles and "story" in styles,
		"a strength, the kept warning, the bane mark, the kills and the story each in their style (%s)" % [styles])
	_check(rows.back()["text"] == "carried by Wren for 3 days; named at the ford", "the story line without its mark")
	var plain := ItemTip.lines_for(dagger, "")
	_check(plain.size() >= 1 and plain[0]["text"] == Items.name_of(dagger) and plain[0]["style"] == "title"
			and plain.size() == 2 and "one hand" in plain[1]["text"] and "kg" in plain[1]["text"],
		"a plain thing: the catalog name and what it is (%s)" % [plain])
	# The armour slot (622, ui's side): the hover reads the kind's note.
	var mail := ItemTip.lines_for("mail_armour", "")
	var mail_texts: Array[String] = []
	for row in mail:
		mail_texts.append(row["text"])
	_check(mail.size() >= 3 and mail[0]["text"] == Items.name_of("mail_armour") and str(Items.def("mail_armour").get("about", "")) in mail_texts
			and mail_texts[mail_texts.find(str(Items.def("mail_armour")["about"]))].begins_with("Worn in the armour slot"),
		"armour: the catalog name, what it weighs, and the kind's own note from items.json about (%s)" % [mail_texts])
	var noted := ItemTip.lines_for("mail_armour", "mail shirt. %s" % Items.def("mail_armour")["about"])
	var noted_texts: Array[String] = []
	for row in noted:
		noted_texts.append(row["text"])
	_check(noted_texts == mail_texts and noted[0]["style"] == "title", "a slot note that still ends with the about (an older server): the tip reads it once, the title clean (%s)" % [noted_texts])
	var arrows := ItemTip.lines_for("arrows", "bundle of arrows, 6 of 10")
	_check(arrows.size() >= 2 and arrows[0]["style"] == "title" and arrows.back()["text"] == "6 of 10",
		"a condition after the comma is a mark (%s)" % [arrows])
	_check(ItemTip.lines_for("", "").is_empty(), "nothing for an empty slot")


func _test_talk_panel() -> void:
	print("== the talk panel: a line shows it, it fades, Tab pins, the channel ==")
	var talk: TalkPanel = _main.talk
	_check(not talk.visible and not talk.pinned, "hidden and unpinned at the start")
	talk.add_line("Wren", "The door's barred.")
	_check(talk.visible and talk.keeps_showing(), "a line shows it")
	# npc's 336 amended, ui's side: a resident's aside after the speech, dim; none for an empty key.
	talk.add_line("Aldous", "I've been meaning to thank you.", false, false, "his voice steady despite the rain")
	var row: RichTextLabel = talk._list.get_child(talk._list.get_child_count() - 1)
	_check(row.get_parsed_text() == "Aldous: I've been meaning to thank you." + TalkPanel.ASIDE_DASH + "his voice steady despite the rain"
		and talk.lines.back()[4] == "his voice steady despite the rain", "the aside follows the speech on its row, set off by a spaced dash")
	_check(TalkPanel.ASIDE == UiTheme.color("text_dim"), "dim")
	talk.add_line("Wren", "Nothing to say.")
	row = talk._list.get_child(talk._list.get_child_count() - 1)
	_check(row.get_parsed_text() == "Wren: Nothing to say." and talk.lines.back()[4] == "", "no aside, nothing after the speech")
	talk._shown_until = 0.0
	await get_tree().process_frame
	_check(not talk.visible, "and it goes once the line is old (the mouse away, nothing typed)")
	talk.toggle_pin()
	_check(talk.visible and talk.pinned, "Tab pins it")
	talk.toggle_pin()
	await get_tree().process_frame
	_check(not talk.visible, "and again lets it go")
	_main._chat_box.text = ""
	_main._chat_box.visible = true  # As _open_chat does once there is a player.
	await get_tree().process_frame
	_check(talk.visible and talk.channel_shown() == "say", "the chat box opens it, speaking aloud")
	_main._swap_chat_channel()
	await get_tree().process_frame
	_check(_main._chat_box.text.begins_with("/p ") and talk.channel_shown() == "party", "Tab in the box: party")
	_main._swap_chat_channel()
	await get_tree().process_frame
	_check(_main._chat_box.text == "" and talk.channel_shown() == "say", "and back")
	_main._close_chat()
	await get_tree().process_frame
	_check(not talk.visible, "closed: it goes")


func _test_context_and_place() -> void:
	print("== the context hint and the place under the compass ==")
	var chest: GridEntity = null
	for entity in World.get_entities():
		if entity is Chest and chest == null:
			chest = entity
	var hints_were: bool = Net.hints
	Net.hints = false
	_check(chest != null and _main.context_hint_for(chest) == "", "hints off (the default; Jeff, 2026-10-22): no hint over a chest")
	Net.hints = true
	_check(chest != null and _main.context_hint_for(chest) == "E  open", "a chest with hints=on: E open")
	_check(_main.context_hint_for(null) == "", "nothing under the cursor: nothing")
	Net.hints = hints_were
	var player: GridEntity = _main._local_player()
	var zone_name := str(_main.level.get("display_name", _main.level.get("name", "")))
	var places: Dictionary = _main.level.get("places", {})
	var was := places.duplicate()
	places["yard"] = {"cell": player.tile, "name": "The Yard", "kind": "other", "radius": 2}
	_main.level["places"] = places
	_check(_main.place_text(player) == "The Yard, %s" % zone_name, "standing in a place: its name, then the zone (%s)" % _main.place_text(player))
	places["far"] = {"cell": player.tile + Vector2i(40, 40), "name": "Far", "kind": "other", "radius": 1}
	_check(_main.place_text(player) == "The Yard, %s" % zone_name, "a place out of reach is not it")
	_main.level["places"] = was
	_check(_main.place_text(player) == zone_name or _main.place_text(player).ends_with(zone_name),
		"outside every place: the zone (%s)" % _main.place_text(player))
	_main.hint_panel.set_lines(_main.hint_lines())
	_check(_main.hint_panel.lines().size() > 10 and _main.hint_panel._columns.size() == 2
			and _main.hint_panel._columns[0].get_child_count() >= _main.hint_panel._columns[1].get_child_count(),
		"the controls list in two columns (%d lines)" % _main.hint_panel.lines().size())


func _test_talk_no_panel() -> void:
	print("== talk with no panel (536, ui's side): the standing offer on the HUD, Y, what is promised in the pack ==")
	_check(not _main.has_node("HUD/ConversePanel") and _main.get("converse") == null, "no conversation panel (436 retired)")
	_check(Main.standing_words("A loaf, 2 gold") == 'say "yes" to take it: A loaf, 2 gold' and Main.standing_words("") == "",
		"the HUD's words while an offer stands")
	_main._on_offers_message({"entity": "", "offers": [
		{"id": "a", "kind": "commission", "title": "Bring Bram home", "words": "He was carried off.", "accept": "take", "cost": 0},
		{"id": "z", "kind": "commission", "title": "Walk Tam home", "open": true}],
		"standing": {"id": "a", "title": "Bring Bram home"}})
	_check(_main.standing_title == "Bring Bram home" and _main.pack_panel.promised == ["Walk Tam home"]
		and _main.pack_panel._promised.visible and _main.pack_panel._promised.text == "Promised: Walk Tam home",
		"an offers message: the standing title kept, the open commissions as the pack's Promised line")
	_main._on_offers_message({"entity": "", "offers": []})
	# 573, ui's side: the pack's charges line from Player's replicated pair; nothing unblessed.
	_check(PackPanel.charges_words(23, 50) == "charges 23 of 50" and PackPanel.charges_words(0, 50) == "charges 0 of 50" and PackPanel.charges_words(0, 0) == "",
		"the charges line's words: charges 23 of 50; nothing without room")
	var own: GridEntity = _main._local_player()
	if own != null and _main.pack_panel != null:
		own.set("charges", 7)
		own.set("charge_room", 25)
		_main.pack_panel._refresh()
		_check(_main.pack_panel.charges_shown() == "charges 7 of 25", "the line reads the player's replicated charges (%s)" % _main.pack_panel.charges_shown())
		own.set("charges", 0)
		own.set("charge_room", 0)
		_main.pack_panel._refresh()
		_check(_main.pack_panel.charges_shown() == "", "unblessed: no line")
	_check(_main.standing_title.is_empty() and _main.pack_panel.promised.is_empty() and not _main.pack_panel._promised.visible,
		"without the key nothing stands, and nothing is promised")
	_check(Keys.DEFAULTS["yes"] == KEY_Y and Keys.WORDS.has("yes"), "Y says yes by default, in the Options' key rows")
	_check(Main.server_status_words({"ok": false, "why": "no answer"}) == "status unknown", "no answer is status unknown")
	var fonts := UiTheme.credits()
	_check(fonts["entries"].size() == 2 and UiTheme.credits in OptionsPanel.credit_providers(),
		"the fonts' credit (Alegreya, Alegreya Sans, OFL) is one of the Credits' providers")


func _test_sim_reads() -> void:
	print("== the day's sim read in play (decision 515): the wagon's words, the pile's hint ==")
	var map: WorldMapPanel = _main.world_map_panel
	var route := {"id": "t", "from_area": "a", "to_area": "b", "areas": ["a", "b"], "caravans": [{"area": "a", "fraction": 0.5}]}
	_check(map.caravan_words(route, route["caravans"][0]) == "the wagon from a, bound for b, in a",
		"a caravan's words from the wire alone (the ids when the map has no names)")
	_check(map.caravan_words(route, {"area": "b", "fraction": 0.9, "days": 2}) == "the wagon from a, bound for b, in b, 2 days out"
		and map.caravan_words(route, {"area": "b", "days": 1}).ends_with(", a day out"), "with maps' days: N days out, a day out")
	_check(map.caravan_words(route, {"area": "b", "days": 0.4}).ends_with(", less than a day out")
		and map.caravan_words(route, {"area": "b", "days": 1.37}).ends_with(", a day out")
		and map.caravan_words(route, {"area": "b", "days": 2.6}).ends_with(", 3 days out"), "maps' days are a float: rounded to whole days, under three quarters 'less than a day'")
	_check(Main.hidden_words_due(World.TALL_GRASS_COVER, Senses.STILL_TICKS, false, 0.0, 9)
		and not Main.hidden_words_due(0.0, Senses.STILL_TICKS, false, 0.0, 9)
		and not Main.hidden_words_due(World.TALL_GRASS_COVER, Senses.STILL_TICKS - 1, false, 0.0, 9)
		and not Main.hidden_words_due(World.TALL_GRASS_COVER, Senses.STILL_TICKS, false, 0.0, Senses.NOTICE_ALWAYS),
		"hidden in the grass: on cover, still Senses.STILL_TICKS, nobody adjacent")
	_check(not Main.hidden_words_due(World.TALL_GRASS_COVER, 99, true, Senses.DARK - 0.1, 9)
		and Main.hidden_words_due(World.TALL_GRASS_COVER, 99, true, 1.0, 9),
		"a carried light gives them away in the dark alone, not by day (enemy-ai's reading)")
	var sick: GridEntity = load(Main.RESIDENT).new()
	sick.person = "Oda"
	sick.trade = "cook"
	sick.ailing = "a fever"
	if _main._local_player() != null:
		var hints_kept: bool = Net.hints
		Net.hints = true
		_check(_main.context_hint_for(sick) == "LMB  interact   in bed with a fever", "the hint over someone in bed says it (515 amended; 560: interact; hints=on)")
		Net.hints = hints_kept
	sick.free()
	_check(Main.pile_words(PackedStringArray(["herbs"])) == "herbs" and Main.pile_words(PackedStringArray(["herbs", "dagger", "rope"])) == "herbs and 2 more"
		and Main.pile_words(PackedStringArray()) == "", "a pile's words: the first thing's short name, and how many more")
	# 555, ui's side: her bond read without a bar.
	_check(Main.bond_shown("fond") == "" and Main.bond_shown("devoted") == "devoted" and Main.bond_shown("sullen") == "sullen",
		"her step shows as its word, warm or cold; fond (the start) as nothing")
	_check(Main.bond_dropped("fond", "sullen") and Main.bond_dropped("close", "fond") and not Main.bond_dropped("sullen", "fond")
		and not Main.bond_dropped("", "sullen") and not Main.bond_dropped("fond", "fond"),
		"a drop is a colder step than last seen; warming, the same step or an unknown word is none")
	_check(Main.bond_words("Wren", "sullen") == "Wren hangs back" and Main.bond_words("Wren", "cooling") == "Wren is quiet"
		and Main.bond_words("Wren", "wary") == "Wren keeps her distance" and Main.bond_words("Wren", "apart") == "Wren walks apart"
		and Main.bond_words("Wren", "close") == "", "the hint's words per cold step; none for a warm one")
	var cut := Main.reason_short("you gave her " + "a long-named thing ".repeat(5))
	_check(Main.reason_short("you struck her") == "you struck her" and cut.length() <= 60 and cut.ends_with("…"), "a reason is cut to one row with an ellipsis")
	var pet: Companion = _main._own_companion()
	if pet != null and _main.pack_panel != null:
		var her := String(pet.name)
		var step_was := str(pet.bond_step)
		var why_was := str(pet.bond_why)
		pet.bond_step = "sullen"
		pet.bond_why = "you left her to fall alone"
		_main.pack_panel.open(pet)
		_check(_main.pack_panel.title_shown(false) == "%s's Pack" % her and _main.pack_panel.mood_shown() == ", sullen"
			and _main.pack_panel.mood_hover() == "you left her to fall alone", "her pack's title carries her step, the reason on hover")
		pet.bond_step = "fond"
		_main.pack_panel._refresh()
		_check(_main.pack_panel.mood_shown() == "", "at fond the title is plain")
		_main.pack_panel.open(null)
		pet.bond_step = "devoted"
		_main._refresh_world_map()
		var hers: Dictionary = {}
		for member: Dictionary in map.party:
			if str(member.get("name", "")) == her:
				hers = member
		_check(hers.get("mood", "") == "devoted" and WorldMapPanel.party_words(hers) == "%s, devoted" % her
			and hers.get("why", "") == "you left her to fall alone", "the map's party list reads her step too, warm ones included; the reason rides for the hover")
		_main._bond_seen[her] = "fond"
		pet.bond_step = "sullen"
		var lines_before: int = _main.talk.lines.size()
		_main._watch_bond()
		_check(_main._bond_hint == "%s hangs back" % her and _main.talk.lines.size() == lines_before + 1
			and _main.talk.lines[-1][2] == "%s hangs back: you left her to fall alone" % her, "her step drops: the HUD's hint and one party log line with the reason")
		_main._watch_bond()
		_check(_main.talk.lines.size() == lines_before + 1 and _main._bond_seen[her] == "sullen", "told once per drop; the step seen is kept")
		_main._bond_hint = ""
		_main._bond_seen[her] = "close"
		pet.bond_step = "fond"
		_main._watch_bond()
		_check(_main._bond_hint == "" and _main.talk.lines.size() == lines_before + 1 and _main._bond_seen[her] == "fond",
			"a drop to a warm step (close to fond) says nothing: no hint, no log line (companions' still, 2026-10-21)")
		pet.bond_step = step_was
		pet.bond_why = why_was
		_main._bond_seen.erase(her)
		_main._refresh_world_map()
	else:
		print("  (no companion in this world: her line's checks skipped)")


func _test_minimap_turn() -> void:
	print("== the minimap turns with the view, the arrow is the body's facing (decision 535) ==")
	var map: Minimap = _main.minimap
	var north := Vector2(World.north)
	map.north_on_screen = Vector2.UP
	var shown := map.view(Vector2(map.cells) / 2.0)
	var middle := Minimap.to_screen((shown["centre"] as Vector2) - Vector2(0.5, 0.5), shown)
	var ahead := Minimap.to_screen((shown["centre"] as Vector2) - Vector2(0.5, 0.5) + north * 3.0, shown)
	_check(is_zero_approx(float(shown["angle"])) and (ahead - middle).normalized().is_equal_approx(Vector2.UP) == (north == Vector2.UP),
		"north up: no turn, a cell to the north draws above the middle (%s)" % [(ahead - middle).normalized()])
	var ok := true
	for screen_north: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		map.north_on_screen = screen_north
		shown = map.view(Vector2(map.cells) / 2.0)
		middle = Minimap.to_screen((shown["centre"] as Vector2) - Vector2(0.5, 0.5), shown)
		ahead = Minimap.to_screen((shown["centre"] as Vector2) - Vector2(0.5, 0.5) + north * 3.0, shown)
		ok = ok and (ahead - middle).normalized().is_equal_approx(screen_north) and Minimap.on_screen(north, shown).is_equal_approx(screen_north)
	_check(ok, "at four turns a cell to the north draws where the view puts north, and a body facing north points the same way")
	map.north_on_screen = Vector2.RIGHT
	map.big = true
	_check(is_zero_approx(map.turn()) and is_zero_approx(float(map.view(Vector2(map.cells) / 2.0)["angle"])), "the big map stays north-up (535 amended, maps)")
	map.big = false
	map.north_on_screen = Vector2.UP
	var player: GridEntity = _main._local_player()
	if player != null:
		var you: Dictionary = {}
		for mark: Dictionary in _main._minimap_marks():
			if mark["kind"] == "you":
				you = mark
		_check(not you.is_empty() and you["facing"] == Vector2(player.facing), "the you mark's facing is the body's replicated facing, not the camera's")


func _test_screenshot_key() -> void:
	print("== the screenshot key (decision 538): the folder, its fallback, the file's name ==")
	var ports := preload("res://tests/test_ports.gd")
	var own := ports.scratch("screenshots")  # Never the shared user://screenshots (release's rule).
	Net.screenshot_dir = own
	_check(Main.screenshot_folder() == [own, ""] and DirAccess.dir_exists_absolute(own), "screenshot_dir= is used, made if missing")
	var blocked := ports.scratch("shots_block")
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	if file != null:
		file.store_string("a file where a folder is wanted")
		file.close()
	Net.screenshot_dir = blocked.path_join("inside")
	var fallen: Array = Main.screenshot_folder()
	_check(fallen[0] == Main.DEFAULT_SCREENSHOT_DIR and str(fallen[1]).contains("can't be written"),
		"a folder that can't be made falls back to the game's own and says so (%s)" % [fallen[1]])
	Net.screenshot_dir = ""
	_check(Main.screenshot_folder() == [Main.DEFAULT_SCREENSHOT_DIR, ""], "no setting: the game's own folder")
	_check(Main.screenshot_name("wilds", Vector2i(217, 195), 14.6, "20261019-113005") == "wilds_217-195_14h_20261019-113005.png",
		"the name: zone, cell, hour, clock; nobody's name or id")
	_check(Keys.DEFAULTS["screenshot"] == KEY_F12 and Keys.WORDS.has("screenshot"), "F12 by default, in the Options' key rows")
	# 538 amended: a joined client's World.zone is unnamed; the name is its loaded map's.
	var was_zone: String = World.zone.name
	var was_map: String = _main.map_name
	World.zone.name = ""
	_main.map_name = "wilds"
	_check(_main.zone_name_here() == "wilds", "a joined client (World's zone unnamed) names its loaded map in the file")
	World.zone.name = "castle"
	_check(_main.zone_name_here() == "castle", "a host names World's zone")
	World.zone.name = was_zone
	_main.map_name = was_map
	Net.screenshot_dir = ""  # The save itself is a windowed run's (--test-show=shot); headless has no picture to take.
	# Jeff's castle F12 (2026-10-22): one short line in the log, the path in the console.
	_check(Main.screenshot_words("wilds_128-16_17h_20261022-213005.png") == "screenshot saved: wilds_128-16_17h", "the log's line: the name without its stamp")
	# A town's read-out ("party" from "Town") goes to the big map's box, not the log.
	if _main.talk != null and _main.world_map_panel != null:
		var before: int = _main.talk.lines.size()
		_main._on_message("party", {"from": "Town", "text": "3 in town are on the dole (fed by the town, or hungry): its kitchen works for food first."})
		_main._refresh_world_map()
		_check(_main.talk.lines.size() == before and str(_main.world_map_panel.notes.get(_main.zone_name_here(), "")).begins_with("3 in town"),
			"the dole line: kept for the map's area box, not added to the talk log")
		_main.town_notes.clear()
		_main._on_message("party", {"from": "Server", "text": "You find yourself in the wilds."})
		_check(_main.talk.lines.size() == before + 1, "a Server line still goes to the log")


func _test_aim() -> void:
	print("== the archery aim (ui's side): the angle, the arc's point, the pips, the loose command ==")
	var origin := Vector2(10.0, 10.0)
	var angle := (Vector2(16.0, 6.0) - origin).angle()
	var point := Main.aim_point(origin, angle, 5.0)
	_check(absf((point - origin).length() - 5.0) < 0.001 and absf((point - origin).angle() - angle) < 0.001,
		"the aim's point lies on the arc at the mouse's angle, any angle (%s)" % [point])
	_check(Main.aim_point(origin, 0.0, 3.0) == Vector2(13.0, 10.0) and Main.aim_point(origin, PI * 0.5, 3.0).is_equal_approx(Vector2(10.0, 13.0)),
		"x as 0, the grid's y as the second component")
	var bow := Items.verb_of("bow")
	_check(Main.aim_pips(bow, 0, 5) == 2 and Main.aim_pips(bow, 1, 7) == 3 and Main.aim_pips(bow, 2, 9) == 4 and Main.aim_pips(bow, 3, 11) == 3
			and Main.aim_pips(bow, 4, 13) == 2 and Main.aim_pips(bow, 5, 15) == 1 and Main.aim_pips(bow, -1, 5) == 0 and Main.aim_pips({}, 2, 9) == 0,
		"pips: the shot's strength at the aim's reach (decision 669): 2, 3, 4 drawing up, 3, 2, 1 in the bands; none before the draw counts or without a bow")
	_check(Main.aim_fade(0) == 0.0 and absf(Main.aim_fade(100) - 0.5) < 0.001 and Main.aim_fade(400) == 1.0, "the arc fades in over its first fifth of a second")
	# The cone of flight (combat's design, ui's side): the far end's points and the eased half-angle.
	var ends := Client3D.cone_points(origin, 0.0, 5.0, deg_to_rad(25.0))
	_check(ends.size() == Client3D.AIM_SEGMENTS + 1 and ends[0].is_equal_approx(origin + Vector2.from_angle(deg_to_rad(-25.0)) * 5.0)
		and ends[ends.size() - 1].is_equal_approx(origin + Vector2.from_angle(deg_to_rad(25.0)) * 5.0)
		and ends[Client3D.AIM_SEGMENTS / 2].is_equal_approx(origin + Vector2(5.0, 0.0))
		and Array(ends).all(func(p: Vector2) -> bool: return absf(p.distance_to(origin) - 5.0) < 0.001),
		"the cone's far end: the step's radius from the archer, the spread either side of the aim, the marker's point in the middle")
	_check(Client3D.eased_spread(-1.0, 0.4, 0.016) == 0.4 and Client3D.eased_spread(0.4, -1.0, 0.016) == -1.0
		and absf(Client3D.eased_spread(0.4, 0.2, World.TICK_DT * 0.5) - 0.3) < 0.0001 and Client3D.eased_spread(0.4, 0.2, World.TICK_DT * 2.0) == 0.2,
		"the drawn half-angle: the sim's at once from none, else eased toward it over a tick, never past it")
	var player_body: GridEntity = _main._local_player()
	_check(player_body == null or Main.spread_now(player_body) >= -1.0, "the sim's spread by name, -1 for none (the arc alone)")
	# Combat's (c): the body a standing swing would strike, by name, for the ring at its feet.
	if player_body != null and World.has_method("stand_target"):
		var beside := Vector2i(player_body.tile) + Vector2i(1, 0)
		var was := World.get_entity_at(beside)
		if was != null:
			World.despawn(was)
		var imp: GridEntity = _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "StandImp", "tile": beside})
		_check(imp != null and Main.stand_target_now(player_body, Vector2(beside) + Vector2(0.3, 0.2)) == imp,
			"the stand key's swing toward the cursor: the imp beside is who it would strike (the command's own direction snap)")
		_check(Main.stand_target_now(player_body, Vector2(player_body.tile)) == null and Main.stand_target_now(player_body, Vector2(player_body.tile) + Vector2(-1, 0)) == null,
			"the cursor on your own cell, or a way with no one: nobody")
		_check(Main.stand_target_now(null, Vector2(beside)) == null and Main.stand_target_now(player_body, Vector2(NAN, NAN)) == null, "no player or no ground point: nobody, no error")
		if imp != null:
			World.despawn(imp)
		# Combat's check: the ring never marks another player (can_target reads
		# owner_peer, which a body takes from its spawn spec's "peer", on a
		# client's mirror as on the host).
		var other: GridEntity = _main._spawn({"script": "res://sim/player.gd", "shape": "capsule", "name": "StandOther", "tile": beside, "peer": 4242})
		_check(other != null and other.owner_peer == 4242 and player_body.owner_peer != 0
				and Main.stand_target_now(player_body, Vector2(beside) + Vector2(0.3, 0.2)) == null,
				"another player beside: their peer from the spawn spec, and no ring on them (players don't strike players)")
		if other != null:
			World.despawn(other)
	else:
		print("  (no local body or no World.stand_target here: the stand ring's target check skipped)")
	var args := Main.loose_args(angle, Vector2i(16, 6))
	_check(args.get("at") == [16, 6] and absf(float(args.get("angle")) - angle) < 0.000001, "loose carries the angle and the arc's cell (%s)" % [args])
	_check(Main.loose_args(NAN, Vector2i(2, 3)) == {"at": [2, 3]}, "no aim: the old cell alone")
	var own: GridEntity = _main._local_player()
	if own != null:
		_main.aim_drawn = true
		_main._update_aim(own, false)
		_check(not _main.aim_drawn and _main._aim_since == 0, "the bow let go: the aim is dropped")
		_check(Main.range_now(own) == 0, "no bow drawn: no range step")
		# The shot state's fixed aim point steers the angle (the mouse is off-screen in a shot).
		var aim_origin := Iso.local_to_grid(own.position)
		_main._aim_fixed = aim_origin + Vector2(-4.0, 6.0)
		_main._update_aim(own, true)
		_check(absf(_main.aim_angle - Vector2(-4.0, 6.0).angle()) < 0.001 and _main.aim_drawn, "a fixed aim point sets the angle (%.3f)" % _main.aim_angle)
		_main._aim_fixed = Vector2(NAN, NAN)
		_main._update_aim(own, false)
	# 617: the view's offset from the archer: the lean alone without a lead; lean and lead held to the most together.
	_check(Client3D.lead_offset(Vector2(3.0, 0.0), Vector3.ZERO) == Vector3(3.0, 0.0, 0.0), "no lead: the WASD lean alone, as ever")
	var led := Client3D.lead_offset(Vector2(3.0, 0.0), Vector3(4.0, 0.0, 0.0))
	_check(absf(led.length() - Client3D.AIM_LEAD_CELLS) < 0.001 and led.x > 0.0, "lean and lead the same way: held to the most (%s)" % [led])
	var across := Client3D.lead_offset(Vector2(0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	_check(across == Vector3.ZERO, "lean and lead opposed: they cancel")
	# Jeff (2026-10-22): the menu blocked the options screen. Now it steps aside and comes back.
	if _main.options_panel != null:
		var hud_was: bool = _main.get_node("HUD").visible
		_main._show_menu()
		_main._menu_options()
		_check(_main.options_panel.visible and _main.main_menu.visible and not _main.main_menu.front_shown(),
			"the main menu's Options: the options on top, the menu's front aside, its backdrop kept")
		_main.escape()
		_check(not _main.options_panel.visible and _main.main_menu.front_shown(), "Esc: the options close and the menu's front is back")
		_main.main_menu.visible = false
		_main.get_node("HUD").visible = hud_was
		var layer := _main.options_panel.get_parent() as CanvasLayer
		_check(layer != null and layer.get_parent() == _main and layer.layer > 1, "the options live on their own canvas layer over the HUD and the menu")
	# Jeff (2026-10-22): no HP number on the HUD.
	World.step()
	_main._on_world_ticked(World.tick)
	_check(not _main.hud.text.begins_with("HP"), "the HUD's line carries no HP number (%s)" % _main.hud.text)
	# Combat's ground telegraph (602, ui's side): the fill and the cells by name.
	_check(Client3D.telegraph_fill(100, 130, 100) == 0.0 and absf(Client3D.telegraph_fill(100, 130, 115) - 0.5) < 0.001
		and Client3D.telegraph_fill(100, 130, 140) == 1.0 and Client3D.telegraph_fill(100, 100, 100) == 1.0,
		"a telegraph fills from its start to its landing tick")
	var cone: Array = Main.telegraph_cells({"kind": "cone", "origin": [10, 10], "facing": [1, 0], "length": 4, "half_angle": 30})
	var has_class := ProjectSettings.get_global_class_list().any(func(e: Dictionary) -> bool: return str(e.get("class", "")) == "Telegraph")
	_check(cone.is_empty() == not has_class, "the cells come from combat's Telegraph when it is there (%d cells, class %s)" % [cone.size(), has_class])
	# Combat's stamina: "winded" on the state line while the replicated flag is true, read by name.
	var winded_body: GridEntity = load(Main.RESIDENT).new()
	_check(not Main.is_winded(winded_body) and not Main.is_winded(null), "no winded flag on a body (or no body): not winded")
	if "winded" in winded_body:
		winded_body.set("winded", true)
		_check(Main.is_winded(winded_body), "the flag set: winded")
	winded_body.free()


func _test_down_screen() -> void:
	print("== the down screen (587, ui's side): the words, the hold's fill, the state ==")
	_check(DownScreen.title_words(false) == "MORTALLY WOUNDED" and DownScreen.title_words(true) == "ALL HAVE FALLEN", "the title, and everyone's fall")
	_check(DownScreen.count_words(12, 0) == "12 s" and DownScreen.count_words(-3, 0) == "0 s" and DownScreen.count_words(12, 20) == "all come back in 20 s",
		"the count: the blood's seconds, or everyone's wait")
	_check(DownScreen.hold_fill(0.0) == 0.0 and absf(DownScreen.hold_fill(1.0) - 0.5) < 0.001 and absf(DownScreen.hold_fill(2.5) - 0.25) < 0.001,
		"the hold fills over each two-second step of the heart")
	var screen: DownScreen = _main.down_screen
	if screen == null:
		print("  (no down screen in this scene: its checks skipped)")
		return
	var holds: Array = []
	screen.slow_heart.connect(func(held: bool) -> void: holds.append(held))
	var bled := [0]
	screen.bleed_out.connect(func() -> void: bled[0] += 1)
	screen.show_state(true, 25, 120, false, 0)
	_check(screen.visible and screen._hold.disabled and screen._why.text == DownScreen.UNBLESSED_WHY and screen._title.text == "MORTALLY WOUNDED" and screen._count.text == "25 s",
		"downed and unblessed: the screen, the hold dim with its reason")
	screen.show_state(true, 25, 80, true, 0)
	_check(not screen._hold.disabled and not screen._why.visible, "blessed: the hold is theirs")
	screen._hold_down()
	_check(screen.is_held() and holds == [true], "the hold pressed: slow_heart held")
	screen._hold_up()
	_check(not screen.is_held() and holds == [true, false], "let go: slow_heart released")
	screen.show_state(true, 25, 40, true, 20)
	_check(screen._title.text == "ALL HAVE FALLEN" and screen._count.text == "all come back in 20 s", "everyone down: the title and the wait")
	screen._bleed.pressed.emit()
	_check(bled[0] == 1, "Bleed Out asks to go")
	screen.show_state(false, 0, 0, false, 0)
	_check(not screen.visible, "up again: the screen goes")
	_main._on_message("return", {"all_fallen": 20})
	_check(_main.all_fallen_left() == 20, "the return message's all_fallen starts the count (%d)" % _main.all_fallen_left())
	_main._on_message("return", {"all_fallen": 0})
	_check(_main.all_fallen_left() == 0, "all_fallen 0 calls it off")
	_main._return_told = {"by": "Aldous", "where": "temple", "seconds": 0, "near_death": true}
	_main._return_at = Time.get_ticks_msec() / 1000.0
	_check(_main.return_shown() == "Aldous brought you back from near death", "the at-once return's line")
	_main._return_told = {}


## The town status sheet (624, ui's side): the words from today's keys, N
## and the map's row, Esc, economy's rows by key.
## A talking monster's deals as buttons (629, ui's side).
func _test_deal_window() -> void:
	print("== a talking monster's deals as buttons (629, ui's side): E greets him, his offers open the window, a button sends the offer ==")
	var offers: Array = [{"id": "deal:7", "kind": "deal", "title": "Face the draugr", "words": "Return the gold.",
		"what": {"offering": 8, "least": 8, "most": 32, "steps": [8, 16, 32]}, "accept": "give", "cost": 8}]
	var steps: Array[int] = [8, 16, 32]
	var cost_alone: Array[int] = [5]
	_check(DealPanel.first_deal(offers) == offers[0] and DealPanel.first_deal([]).is_empty() and DealPanel.first_deal([{"id": "x", "words": "none"}]).is_empty()
			and DealPanel.steps_of(offers[0]) == steps and DealPanel.steps_of({"cost": 5}) == cost_alone and DealPanel.step_words(16) == "16 gold"
			and DealPanel.purse_words(20, steps) == "You have 20 gold." and DealPanel.purse_words(5, steps) == "You have 5 gold; he asks 8 at the least.",
		"the first deal with steps, its sums least first (its cost alone without steps), a button's words, the purse line short or not")
	var panel: DealPanel = _main.deal_panel
	if panel == null:
		_check(false, "the deal window exists")
		return
	panel.show_deals("the draugr", offers, 20, 0)
	var buttons := panel._buttons.get_children()
	_check(panel.visible and panel._title.text == "the draugr" and panel._words.text == "Return the gold." and buttons.size() == 3
			and not buttons[0].disabled and not buttons[1].disabled and buttons[2].disabled,
		"shown: his name, his words, a button a step, the ones a purse of 20 covers enabled (%d buttons)" % buttons.size())
	panel.set_purse(40)
	_check(not buttons[2].disabled, "the purse grown: the dearest button enabled")
	var sent: Array = []
	panel.offered.connect(func(id: String, amount: int) -> void: sent.append([id, amount]))
	(buttons[1] as Button).pressed.emit()
	_check(sent == [["deal:7", 16]], "a button offers the deal's id with its sum (%s)" % [sent])
	# 548 amended, ui's side: paid once, faced again for nothing.
	var again: Array = [{"id": "deal:7:again", "kind": "deal", "title": "Face the draugr again", "words": "Again, then.",
		"what": {"level": "normal", "steps": []}, "accept": "take", "cost": 0}]
	var free: Array[int] = [0]
	_check(DealPanel.first_deal(again) == again[0] and DealPanel.steps_of(again[0]) == free and DealPanel.steps_of({"id": "x"}).is_empty()
			and DealPanel.first_deal([{"id": "x", "words": "none", "cost": 0, "what": {"steps": [0]}}]) != {},
		"a deal with no steps and cost 0 is one free step; one with no cost given is none")
	panel.show_deals("the draugr", again, 0, 0)
	var free_buttons := panel._buttons.get_children()
	_check(panel.visible and free_buttons.size() == 1 and (free_buttons[0] as Button).text == "Face him again" and not free_buttons[0].disabled
			and panel._purse.text == "You have 0 gold.",
		"the free deal: one button, no sum, \"Face him again\", enabled with an empty purse (%d buttons)" % free_buttons.size())
	sent.clear()
	(free_buttons[0] as Button).pressed.emit()
	_check(sent == [["deal:7:again", 0]], "and it offers the deal's id with gold 0 (%s)" % [sent])
	panel.show_deals("the draugr", [], 20, 0)
	_check(not panel.visible and panel.entity_id == 0, "empty offers (a pact on): closed")
	_main.escape()
	# The live path on the host: a seated draugr beside the player, E on him, the least sum, the pact.
	var player: GridEntity = _main._local_player()
	if player == null or not Net.is_authority():
		print("  (no local player on the host: the live path skipped)")
		return
	var beside := Vector2i(-1, -1)
	for near: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_walkable(player.tile + near) and World.get_entity_at(player.tile + near) == null:
			beside = player.tile + near
			break
	if beside.x < 0:
		print("  (no free cell beside the player: the live path skipped)")
		return
	var draugr: GridEntity = _main._spawn({"script": "res://sim/draugr.gd", "shape": "capsule", "name": "DealDraugr", "tile": beside,
		"kind": "draugr", "props": Level.MONSTER_TYPES["draugr"].duplicate()})
	if draugr == null:
		_check(false, "a draugr spawned beside the player")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var least: int = int(Draugr.deals()[0]["gold"])
	World.add_gold(player.player_id, least - World.gold_of(player.player_id), "the test purse")
	_main.gold = least
	_check(_main.talks_peaceably(draugr), "seated, the draugr talks peaceably (npc's 648)")
	_main._open_talk(draugr)
	_check(panel.visible and panel.entity_id == draugr.get_instance_id() and panel._buttons.get_child_count() == Draugr.deals().size()
			and not (panel._buttons.get_child(0) as Button).disabled and (panel._buttons.get_child_count() < 2 or (panel._buttons.get_child(1) as Button).disabled),
		"E on him: his offers open the window on him, a button a deal, the least one enabled for a purse of %d (%s)" % [least, panel.visible])
	(panel._buttons.get_child(0) as Button).pressed.emit()
	_main._update_deal()
	_check(draugr.get("state") == Draugr.State.PACT and not draugr.peaceable and World.gold_of(player.player_id) == 0 and not panel.visible,
		"the least sum pressed: his pact begins, the gold his, he is no longer peaceable and the window closes (%s, %s)" % [draugr.get("state"), panel.visible])
	_main._open_talk(draugr)
	_check(not panel.visible, "E on him in a pact: the window stays closed")
	World.despawn(draugr)
	await get_tree().process_frame
	await get_tree().process_frame


## A note on a door, read (643, ui's side; npc's "notes" message).
## The zone arrival card (660, ui's side), its clock stepped by hand.
func _test_arrival_card() -> void:
	print("== the zone arrival card (660, ui's side): the dark in and out, the name's while, a restart mid-arrival ==")
	var card: ArrivalCard = _main.arrival_card
	if card == null:
		_check(false, "the arrival card exists")
		return
	card.set_process(false)  # The test's clock, not the frames'.
	_check(_main.zone_display_name() == str(_main.level.get("display_name", "")).strip_edges() and not _main.zone_display_name().contains("/"),
			"the name shown is the level's display name, as the map shows it (%s), never an id" % _main.zone_display_name())
	card.begin("The Wilds")
	_check(card.showing and card.visible and card.zone_name == "The Wilds" and card._dark == 0.0 and card._name.text == "The Wilds" and not card._line.visible,
			"begin: the card up, the dark from clear, the name set, no line without one")
	card.advance(0.1)
	var halfway := card._dark
	card.advance(0.15)
	_check(halfway > 0.3 and halfway < 0.6 and is_equal_approx(card._dark, ArrivalCard.DARK_ALPHA) and card.name_alpha() == 1.0 and card._dark_rect.color.a < 0.95,
			"the dark in over 0.2 s to %.2f, never black (%.2f at 0.1 s); the name with it" % [card._dark, halfway])
	card.advance(0.25)
	card.finish()
	card.advance(0.15)
	var lifting := card._dark
	card.advance(0.2)
	_check(lifting > 0.0 and lifting < ArrivalCard.DARK_ALPHA and card._dark == 0.0 and card.showing and card.name_alpha() == 1.0,
			"finish at 0.5 s: the dark lifts over 0.3 s (%.2f at 0.15 s), the name stays over the world" % lifting)
	card.advance(0.55)
	var held := card.name_alpha()
	card.advance(0.3)
	var leaving := card.name_alpha()
	card.advance(0.3)
	_check(held == 1.0 and leaving > 0.3 and leaving < 0.7 and not card.showing and not card.visible,
			"the name readable until 1.5 s from begin (%.2f at 1.4 s), fading over 0.4 s (%.2f at 1.7 s), the card gone by 2 s" % [held, leaving])
	card.begin("The Hills", "Where the goats go.")
	card.advance(0.1)
	var dark_before := card._dark
	card.begin("The Dwarven Halls")
	_check(is_equal_approx(card._dark, dark_before) and card.zone_name == "The Dwarven Halls" and card.showing and not card._line.visible,
			"begin while up: the dark goes on from where it is (%.2f), the name restarts, the old line goes" % dark_before)
	card.advance(0.1)
	_check(card._dark > dark_before, "and keeps coming in")
	card.finish()
	card.advance(2.5)
	_check(not card.showing, "then it ends as any")
	card.begin("The Wilds", "A line.")
	_check(card._line.visible and card._line.text == "A line.", "a line given shows under the name")
	card.advance(3.0)
	var long_build := card.name_alpha()
	card.finish()
	card.advance(0.2)
	var after_long := card.name_alpha()
	card.advance(0.5)
	_check(long_build == 1.0 and after_long == 1.0 and card.name_alpha() == 0.0 and not card.showing,
			"a long build: the name holds through it and leaves 0.3 s after finish (%.2f, %.2f)" % [long_build, after_long])
	_check(ArrivalCard.breath_at(0.0) > 0.69 and ArrivalCard.breath_at(0.0) < 0.71 and ArrivalCard.breath_at(ArrivalCard.BREATH_PERIOD / 4.0) > 0.89,
			"the rule breathes between 0.5 and 0.9")
	card.set_process(true)


## Room names mid-screen (665, ui's side): the level's rooms, the card's
## say, the player walking in.
func _test_room_names() -> void:
	print("== room names mid-screen (665, ui's side): level.json rooms, say() after the zone's name, in and out ==")
	var warnings: Array[String] = []
	var rooms := Level.rooms_from({"rooms": {"hall": {"name": "The Hall of Urns", "rect": [10, 10, 4, 3]},
		"crypts": {"name": "The Crypts", "rects": [[20, 10, 2, 2], [22, 12, 2, 2]], "cells": [[30, 30]]},
		"nameless": {"rect": [0, 0, 2, 2]}, "nowhere": {"name": "Nowhere"}, "flat": {"name": "Flat", "rect": [1, 1, 0, 3]}}}, warnings)
	_check(rooms.size() == 2 and rooms["hall"]["name"] == "The Hall of Urns" and (rooms["crypts"]["rects"] as Array).size() == 3 and warnings.size() == 4,
			"rooms read: a rect, several rects and cells; no name, no extent or a flat rect left out with a warning each (%d read, %d warnings)" % [rooms.size(), warnings.size()])
	var made := {"rooms": rooms}
	_check(Level.room_at(made, Vector2i(13, 12)) == "hall" and Level.room_at(made, Vector2i(14, 12)) == "" and Level.room_at(made, Vector2i(23, 13)) == "crypts"
			and Level.room_at(made, Vector2i(30, 30)) == "crypts" and Level.room_at(made, Vector2i(5, 5)) == "" and Level.room_at({}, Vector2i.ZERO) == "",
			"the room at a cell: inside its rect (the far edge outside), any of its rects or cells, none elsewhere")
	var card: ArrivalCard = _main.arrival_card
	var player: GridEntity = _main._local_player()
	if card == null or player == null:
		_check(false, "the arrival card and a local player exist")
		return
	card.set_process(false)
	card.say("")
	_check(not card.showing, "say(\"\") shows nothing")
	card.say("The Hall of Urns")
	card.advance(0.25)
	_check(card.showing and card.zone_name == "The Hall of Urns" and card._dark == 0.0 and card._dark_rect.color.a == 0.0 and card.name_alpha() == 1.0 and not card._line.visible,
			"say: the name mid-screen as a zone's, no dark, no line")
	card.say("The Hall of Urns")
	_check(card._next.is_empty() and card._since > 0.2, "the name showing already is not said again")
	card.advance(2.0)
	_check(not card.showing, "and leaves as a zone's name does (1.5 s hold, 0.4 s fade)")
	card.begin("The Ossuary")
	card.advance(0.3)
	card.say("The Hall of Urns")
	_check(card.zone_name == "The Ossuary" and card._next == "The Hall of Urns", "a room said during a crossing waits for the zone's name")
	card.finish()
	card.advance(1.4)
	_check(card.showing and card.zone_name == "The Ossuary", "the zone's name holds its while (%.2f)" % card._since)
	card.advance(0.5)
	_check(card.showing and card.zone_name == "The Hall of Urns" and card._dark == 0.0 and card._next.is_empty(), "then the room's name follows, no dark (%s)" % card.zone_name)
	card.begin("The Deep")
	card.say("The Crypts")
	card.begin("The Hall of Fallen Souls")
	_check(card.zone_name == "The Hall of Fallen Souls" and card._next.is_empty(), "a crossing drops a room name still waiting")
	card.finish()
	card.advance(3.0)
	_check(not card.showing, "and ends")
	# The player walking in: the level's rooms set round its cell.
	var here: Vector2i = player.tile
	var kept: Variant = _main.level.get("rooms")
	_main.level["rooms"] = Level.rooms_from({"rooms": {"here": {"name": "The Hall of Urns", "rect": [here.x, here.y, 1, 1]}}}, warnings)
	_main._room_here = ""
	_main._room_left_at.clear()
	_main._update_room()
	_check(card.showing and card.zone_name == "The Hall of Urns" and _main._room_here == "here", "stepping into a named room says its name (%s)" % card.zone_name)
	card.finish()
	card.advance(3.0)
	_main.level["rooms"] = {}
	_main._update_room()
	_check(_main._room_here.is_empty() and _main._room_left_at.has("here") and not card.showing, "stepping out says nothing and notes the leaving")
	_main.level["rooms"] = Level.rooms_from({"rooms": {"here": {"name": "The Hall of Urns", "rect": [here.x, here.y, 1, 1]}}}, warnings)
	_main._update_room()
	_check(not card.showing and _main._room_here == "here", "back within 10 s: nothing said (no nagging at a doorway)")
	_main._room_here = ""
	_main._room_left_at["here"] = Time.get_ticks_msec() - Main.ROOM_AGAIN_MSEC - 1
	_main._update_room()
	_check(card.showing and card.zone_name == "The Hall of Urns", "back after 10 s: said again")
	card.finish()
	card.advance(3.0)
	if kept == null:
		_main.level.erase("rooms")
	else:
		_main.level["rooms"] = kept
	_main._room_here = ""
	_main._room_left_at.clear()
	card.set_process(true)


## The admin panel (672): the console's shapes release's scripts read, the
## gate, the quest reset's card, the panel.
## Feel tuning's window (673, ui's side): a row a field, its kind's
## control, a change taken and marked, reset, save and load in a scratch
## folder, the arena's pick at a cell; nothing away from a local host.
func _test_tuning_panel() -> void:
	print("== the tuning panel (673, ui's side): rows, apply, reset, save, load, the arena ==")
	var panel: TuningPanel = _main.tuning_panel
	if panel == null:
		_check(false, "the tuning panel exists")
		return
	var mode := Net.mode
	var kept_dir := Tuning.save_dir
	Net.mode = Net.Mode.CLIENT
	panel.open()
	_check(not panel.visible, "a joined client: F7's panel does not open")
	Net.mode = Net.Mode.HOST
	Tuning.save_dir = preload("res://tests/test_ports.gd").scratch("tuning_saves")
	DirAccess.make_dir_recursive_absolute(Tuning.save_dir)
	for old in DirAccess.get_files_at(Tuning.save_dir):
		DirAccess.remove_absolute(Tuning.save_dir.path_join(old))
	_main.tuning_panel_toggled.emit()
	_check(panel.visible and panel._rows.size() == Tuning.fields().size(), "F7: open, a row a field (%d of %d)" % [panel._rows.size(), Tuning.fields().size()])
	var kinds := {}
	for path: String in panel._rows:
		var entry: Dictionary = panel._rows[path]
		kinds[entry["kind"]] = entry["control"] if entry["control"] != null else entry["value"]
	_check(kinds.get("float") is HSlider and kinds.get("int") is HSlider and kinds.get("bool") is CheckBox and kinds.get("ints") is LineEdit,
			"a slider a number, a checkbox a bool, a typed line a list (%s)" % [kinds.keys()])
	_check(TuningPanel.parse_typed("4, 8 12", "ints") == [4.0, 8.0, 12.0] and TuningPanel.parse_typed("x", "float") == null
			and TuningPanel.parse_typed("0.5", "float") == 0.5 and TuningPanel.shown([4, 8]) == "4, 8",
			"typed numbers and lists read and shown")
	var was := World.swing_base
	_check(panel.set_value("combat.swing_base", was + 2.0) and is_equal_approx(World.swing_base, was + 2.0) and panel.marked("combat.swing_base"),
			"a change takes at once and its row is marked (%s)" % World.swing_base)
	panel._typed("items.bow.steps", "4, 6, 8, 10, 12, 14")
	_check(Items.verb_of("bow").get("steps") == [4, 6, 8, 10, 12, 14] and panel.marked("items.bow.steps"), "a typed list takes (%s)" % [Items.verb_of("bow").get("steps")])
	panel._typed("combat.swing_base", "lots")
	_check(is_equal_approx(World.swing_base, was + 2.0), "a word typed for a number changes nothing")
	panel.reset("items.bow.steps")
	_check(not panel.marked("items.bow.steps") and panel.marked("combat.swing_base"), "a row's reset: that one back, the other kept")
	panel._filter.text = "swing_base"
	panel._show_rows()
	_check(panel.shown_rows() >= 1 and panel.shown_rows() < panel._rows.size(), "the filter narrows the rows (%d)" % panel.shown_rows())
	panel._filter.text = ""
	panel._show_rows()
	var saved := panel.save()
	_check(not saved.is_empty() and TuningPanel.saves().size() == 1, "save: one file in the save folder (%s)" % saved)
	panel.reset_all()
	_check(is_equal_approx(World.swing_base, was) and not panel.marked("combat.swing_base"), "reset all: the repo's values")
	_check(panel.load_save(TuningPanel.saves()[0]) == 1 and is_equal_approx(World.swing_base, was + 2.0) and panel.marked("combat.swing_base"),
			"load: the save's change back and marked")
	panel.reset_all()
	# 673 step 2: the view's feel among the camera fields, ui's, set live.
	Tuning.register_source("camera", _main._camera_value, _main._set_camera_value, Main.camera_fields)  # As Main does in a host.
	var camera_rows := Tuning.fields().filter(func(row: Dictionary) -> bool: return str(row["path"]).begins_with("camera."))
	var no_view := _main._client3d == null  # Without the 3D view a camera field has no value, so no kind.
	_check(camera_rows.any(func(row: Dictionary) -> bool: return row["path"] == "camera.inside_pitch" and row["owner"] == "ui" and (no_view or row["kind"] == "float"))
			and camera_rows.any(func(row: Dictionary) -> bool: return row["path"] == "camera.draw_pull_rate" and row["owner"] == "combat")
			and camera_rows.any(func(row: Dictionary) -> bool: return row["path"] == "camera.telegraph_flash_msec" and (no_view or row["kind"] == "int"))
			and camera_rows.size() == Main.CAMERA_FIELDS.size(), "the camera's feel in the panel, ui's (%d rows)" % camera_rows.size())
	if _main._client3d != null:
		_check(panel.set_value("camera.inside_pitch", 80.0) and is_equal_approx(_main._client3d.inside_pitch, 80.0), "a camera field set live (%s)" % _main._client3d.inside_pitch)
		panel.reset_all()
		_check(is_equal_approx(_main._client3d.inside_pitch, Client3D.INSIDE_PITCH), "and back")
	panel.pick("dummy")
	_check(panel.picking == "dummy", "the arena's dummy waits for a cell")
	_main.escape()
	_check(panel.picking.is_empty() and panel.visible, "Esc lets the pick go, the panel kept")
	panel.close()
	_check(not panel.visible, "closed")
	Tuning.save_dir = kept_dir
	Net.mode = mode


func _test_admin_panel() -> void:
	print("== the admin panel (672): one dispatcher, the gate, quests reset, the panel ==")
	# Release's scripts: stage.sh and deploy_box.ps1 read the protocol out of
	# "version" (sed 's/.*protocol \\([0-9a-f]*\\).*/'); deploy.sh needs "stop"
	# and "restart" to answer starting "restarting"; "players" leads with a count.
	var version: String = _main.admin_command("version")
	var protocol := RegEx.create_from_string("protocol ([0-9a-f]+)").search(version)
	_check(protocol != null and protocol.get_string(1) == Net.protocol(), "version: \"protocol <hex>\" as stage.sh and deploy_box read it (%s)" % version)
	var stopping: String = _main.admin_command("stop 600 update")
	_main.admin_command("restart cancel")
	var restarting: String = _main.admin_command("restart 600 test")
	var cancelled: String = _main.admin_command("restart cancel")
	_check(stopping.begins_with("restarting") and restarting.begins_with("restarting") and cancelled == "restart cancelled",
			"stop and restart answer starting \"restarting\", as deploy.sh tests (%s)" % stopping.left(30))
	var players: String = _main.admin_command("players")
	_check(RegEx.create_from_string("^\\d+ connected").search(players) != null, "players: its count line first (%s)" % players.get_slice("\n", 0))
	var help: String = _main.admin_command("help")
	var lines := AdminPanel.help_from(help)
	_check(lines.size() == Main.CONSOLE_HELP.size() and lines.all(func(each: String) -> bool: return each.contains(":"))
			and lines.any(func(each: String) -> bool: return each.begins_with("go <zone>"))
			and lines.any(func(each: String) -> bool: return each.begins_with("quests reset")),
			"help: one line a command, \"name args: what it does\", go and quests reset among them (%d)" % lines.size())
	_check(_main.admin_command("go wilds").contains("name the player") and _main.admin_command("quests reset").contains("name the player"),
			"from the console, go and quests reset ask for the player")
	var me: Player = _main._local_player()
	if me != null:
		var all_reset: String = _main.admin_command("quests reset", me)
		var giver_reset: String = _main.admin_command("quests reset Nobody Here", me)
		var gone: String = _main.admin_command("go no_such_map", me)
		_check(all_reset.contains("quests reset (") and giver_reset.begins_with("quests reset: no quest giver Nobody Here")
				and gone.contains("no_such_map"),
				"the panel's own player: all reset (%s), a giver not here named, go to no map refused (%s)" % [all_reset, gone])
	# The gate: the host's own player, or an id on the list; nobody else.
	var kept_admins: PackedStringArray = Net.admins
	Net.admins = PackedStringArray()
	_check(Main.admin_peer_allowed(Net.local_id, "") and not Main.admin_peer_allowed(4242, "someone") and not Main.admin_peer_allowed(4242, ""),
			"no list: only the host's own player")
	Net.admins = PackedStringArray(["someone"])
	_check(Main.admin_peer_allowed(4242, "someone") and not Main.admin_peer_allowed(4243, "else"), "on the list: allowed; anyone else not")
	Net.admins = kept_admins
	# The quest reset's card: only that player's asks go.
	var card := {"asks": [{"id": "a1", "by": "p1"}, {"id": "a2", "by": "p2"}, {"id": "a3", "by": "p1"}], "standing": {"p1": {"trust": 3}}}
	var dropped := Main.card_without(card, "p1")
	_check(dropped == (["a1", "a3"] as Array[String]) and (card["asks"] as Array).size() == 1 and card["standing"].has("p1"),
			"a giver's card: that player's asks dropped (%s), the other's kept, his trust of them kept" % [dropped])
	# The panel: F10 only for an admin; its line, history, confirm.
	var panel: AdminPanel = _main.admin_panel
	if panel == null:
		_check(false, "the admin panel exists")
		return
	_check(_main.admin_allowed() == (_main._local_player() != null), "the host with a player of its own may open it")
	var sent: Array[String] = []
	var catch := func(line: String) -> void: sent.append(line)
	panel.ran.connect(catch)
	panel.help_lines = []
	_main.open_admin()
	_check(panel.visible and sent == (["help"] as Array[String]) and panel.zone == _main.zone_name_here(), "F10: open, the help asked for, the zone known (%s)" % [sent])
	panel.on_reply({"line": "help", "text": help})
	_check(panel._help.item_count == lines.size(), "the help reply fills the list (%d)" % panel._help.item_count)
	panel._filter.text = "quests"
	panel._show_help()
	_check(panel._help.item_count == 1, "the filter narrows it (%d)" % panel._help.item_count)
	_check(panel._help.get_item_text(0) == AdminPanel.command_of(str(panel._help.get_item_metadata(0))) and not panel._help.get_item_text(0).contains(": ")
			and panel._help.get_item_tooltip(0).contains(": ") and AdminPanel.command_of("go <zone> [player]: you (or him) to a zone") == "go <zone> [player]",
			"the list shows a command and its arguments, the whole line its tooltip (%s)" % panel._help.get_item_text(0))
	panel.run("players")
	panel.run("zones")
	panel.run("zones")
	_check(panel.history == (["players", "zones"] as Array[String]), "the typed lines kept, a repeat once (%s)" % [panel.history])
	sent.clear()
	panel.zone = "test_zone"
	panel._reset_this_room()
	_check(sent.is_empty() and panel._reset_room.text.contains("again"), "reset this room: pressed once, it asks again")
	panel._reset_this_room()
	_check(sent == (["zone reset test_zone"] as Array[String]), "pressed again: run (%s)" % [sent])
	panel.ran.disconnect(catch)
	panel.close()
	_check(not panel.visible, "closed")


func _test_door_note() -> void:
	print("== a note on the door (643, ui's side): npc's notes by zone, E on or facing the cell reads it, Esc or moving off puts it back ==")
	var sheet: NoteSheet = _main.note_sheet
	var player: GridEntity = _main._local_player()
	if sheet == null or player == null:
		_check(false, "the note sheet and a local player exist")
		return
	var zone: String = _main.zone_name_here()
	var here: Vector2i = player.tile
	var ahead: Vector2i = player.tile + player.facing
	var text := "Away in the hills. Back when I can."
	_main._on_message("notes", {"zone": "elsewhere/nowhere", "notes": [{"tile": [here.x, here.y], "text": "Not here."}]})
	_check(_main.note_at(here).is_empty() and _main.note_cell_by(player) == _main.NONE, "another zone's notes are not read here")
	_main._on_message("notes", {"zone": zone, "notes": [{"tile": [ahead.x, ahead.y], "text": text}, {"tile": [0, 0], "text": ""}]})
	_check(_main.note_at(ahead) == text and _main.note_at(Vector2i(0, 0)).is_empty() and _main.note_cell_by(player) == ahead,
			"the zone's notes by cell (an empty text is no note); the cell faced has one (%s)" % [_main.note_cell_by(player)])
	_main._tap_e(player)
	_check(sheet.visible and sheet.tile == ahead and sheet.text == text and sheet._words.text == text and sheet._title.text == NoteSheet.TITLE,
			"E facing the note: the sheet shows its text under its title (%s)" % sheet.visible)
	_main._update_note()
	_check(sheet.visible, "still facing it: the sheet stays")
	_main.escape()
	_check(not sheet.visible and sheet.text.is_empty(), "Esc puts the note back")
	_main._on_message("notes", {"zone": zone, "notes": [{"tile": [here.x, here.y], "text": text}]})
	_check(_main.note_at(ahead).is_empty() and _main.note_cell_by(player) == here, "the list replaced whole: the note is on the player's own cell now")
	_main._tap_e(player)
	_check(sheet.visible and sheet.tile == here, "E on the cell reads it")
	_main._on_message("notes", {"zone": zone, "notes": []})
	_main._update_note()
	_check(not sheet.visible and _main.note_at(here).is_empty() and not _main.zone_notes.has(zone), "an empty list clears the zone's notes and closes the sheet")
	_main._on_message("notes", {"zone": zone, "notes": [{"tile": [here.x + 5, here.y + 5], "text": text}]})
	_main._tap_e(player)
	_check(not sheet.visible, "a note five cells off is not read from here")
	_main._on_message("notes", {"zone": zone, "notes": []})
	_check(_main._note_hover != null and not _main._note_hover.visible and _main._note_hover.text == NoteSheet.HOVER_WORD,
			"the hover word at the cursor reads \"%s\", hidden off a note's cell" % NoteSheet.HOVER_WORD)


func _test_town_sheet() -> void:
	print("== the town status sheet (624, ui's side): today's facts in words, N, the map's row, economy's rows by key ==")
	_check(TownSheet.title_words("Umbrage", "village") == "Umbrage, a village" and TownSheet.title_words("Umbrage", "") == "Umbrage"
			and TownSheet.title_words("Oakford", "inn town") == "Oakford, an inn town",
		"the heading: the name and its stage, bare before the stages")
	_check(TownSheet.held_words("the Blood Rot") == "Held by the Blood Rot." and TownSheet.held_words("") == "", "who holds it, in the map's words; nothing for nobody")
	_check(TownSheet.people_words(["farmer", "farmer", "hunter", "priest"]) == "4 people: 2 farmers, a hunter, a priest."
			and TownSheet.people_words(["innkeeper"]) == "1 person: an innkeeper." and TownSheet.people_words([]) == "No one is about."
			and TownSheet.people_words(null) == "You haven't seen who lives here.",
		"the people from the bodies seen, counted by trade; none about; away words from elsewhere")
	_check(TownSheet.buildings_words({"well": {"state": "planned"}, "forge": {"state": "standing"}, "temple": {"state": "planned", "progress": 0.5},
			"walls": {"state": "damaged"}, "inn": {"state": "planned", "progress": 0.1}, "kitchen": {"state": "standing"}})
			== "Standing: the forge, the kitchen. Building: the inn, begun, the temple, half built. Damaged: the walls. Planned: the well."
			and TownSheet.buildings_words({}) == "" and TownSheet.progress_words(0.9) == "nearly done",
		"the buildings: standing, building with a word of progress, damaged, planned")
	_check(TownSheet.when_words("summer", 14) == "Summer, day 14." and TownSheet.when_words("", 3) == "Day 3.", "the season and the day")
	_check(TownSheet.economy_lines({}).is_empty() and TownSheet.economy_lines({"why": "you don't know that town"}) == ["You don't know that town"],
		"economy's rows: none before its message; a why alone")
	var rows := TownSheet.economy_lines({"town": "wilds/held", "name": "Umbrage", "mood": "uneasy", "treasury": 150,
		"officials": [{"name": "Hob", "trade": "priest", "paid": true}, {"name": "Tam", "trade": "guard", "paid": false}],
		"dole": 3, "hungry": 2, "sick": 1, "needs": [{"id": "wood", "short": 0.8, "bring": 20}, {"id": "herbs", "short": 0.2, "bring": 4}],
		"strain": {"days": 4, "of": 10, "why": "hunger"},
		"sought": [{"trade": "smith"}, {"trade": "healer"}], "next_stage": {"stage": "village", "needs": [{"what": "people", "have": 5, "need": 8}, {"what": "priest", "have": 0, "need": 1}, {"what": "gold", "have": 110, "need": 150}]}})
	_check(rows == ["Umbrage is uneasy.", "Treasury: 150 gold.", "Officials: Hob the priest, Tam the guard (unpaid).", "3 fed by the town, 2 hungry, 1 sick.",
			"Needs: wood, badly (bring 20); herbs, a little (bring 4).", "Umbrage seeks a smith and a healer.", "To be a village: 3 more people, a priest and 40 more gold.",
			"Strained 4 days of 10: hunger, the store short of food."],
		"economy's rows by key: the mood, the treasury, the officials with unpaid, fed and hungry, needs worst first, the sought, the next stage, the strain (%s)" % [rows])
	_check(TownSheet.strain_words({"days": 0, "of": 10, "why": ""}) == "" and TownSheet.strain_words({"days": 3, "of": 10, "why": ""}) == "Strained 3 days of 10."
			and TownSheet.strain_words({"days": 1, "of": 10, "why": "too few people (3 of 8)"}) == "Strained 1 day of 10: too few people (3 of 8)."
			and TownSheet.strain_words({"days": 7, "of": 10, "why": "the forge out of use"}) == "Strained 7 days of 10: the forge out of use."
			and TownSheet.economy_lines({"town": "wilds/held", "name": "Umbrage", "strain": {"days": 0, "of": 10, "why": ""}}).is_empty(),
		"the strain line (649, ui's side): none unstrained, the days alone without a reason (captives), economy's reason as it names it")
	_check(TownSheet.strain_words({"days": 0, "of": 10, "why": "", "settling": {"days": 3, "of": 7}}) == "Settling, 3 of 7 days calm."
			and TownSheet.strain_words({"days": 0, "of": 10, "why": "", "settling": {"days": 0, "of": 7}}) == "Settling, 0 of 7 days calm."
			and TownSheet.strain_words({"days": 1, "of": 10, "why": "hunger", "settling": {"days": 0, "of": 7}}) == "Strained 1 day of 10: hunger, the store short of food. Settling, 0 of 7 days calm."
			and TownSheet.economy_lines({"town": "wilds/held", "name": "Held", "strain": {"days": 0, "of": 10, "why": "", "settling": {"days": 6, "of": 7}}}) == ["Settling, 6 of 7 days calm."]
			and TownSheet.strain_words({"days": 0, "of": 10, "why": ""}) == "",
		"after a fall (649 amended (3), ui's side): the calm days of the wait to rise, after the strain sentence on a strained day, nothing without the key")
	_check(TownSheet.join_and(["a smith"]) == "a smith" and TownSheet.join_and(["a", "b", "c"]) == "a, b and c"
			and TownSheet.need_words({"what": "standing:walls", "have": 0, "need": 1}) == "the walls standing" and TownSheet.need_words({"what": "guard", "have": 0, "need": 2}) == "2 guards",
		"the joins and a next stage's need in words")
	_check(Keys.DEFAULTS["town"] == KEY_N and Keys.WORDS.has("town"), "N opens the sheet by default, in the Options' key rows")
	var sheet: TownSheet = _main.town_panel
	if sheet == null:
		print("  (no town sheet in this scene: its checks skipped)")
		return
	var zone: String = _main.zone_name_here()
	var id := "%s/oakford" % zone
	var states_was: Dictionary = _main.town_states.duplicate()
	var stages_was: Dictionary = _main.town_stages.duplicate()
	_main.town_states[id] = {"forge": {"state": "standing"}, "temple": {"state": "planned", "progress": 0.5}}
	_main.town_stages[id] = "hamlet"
	_main.toggle_town()
	var lines := sheet.lines_shown()
	_check(sheet.visible and sheet.town == id and lines[0] == "Oakford, a hamlet", "N: the sheet for the town whose ground the player stands on, its name and stage (%s)" % lines[0])
	var asked_at: int = _main._town_sheet_asked.get(id, -1)
	_check(asked_at >= 0 and _main.town_sheets.has(id) and str(_main.town_sheets[id].get("why", "")) == "you don't know that town"
			and "You don't know that town" in lines,
		"opening it asks economy for its rows (the host answers itself): a town the sim has no record of gets its why line (%s)" % [lines])
	_main.open_town(id)
	_check(int(_main._town_sheet_asked.get(id, -1)) == asked_at, "opened again at once: not asked again within TOWN_SHEET_ASK_MSEC")
	lines = sheet.lines_shown()
	var residents := 0
	for entity in World.entities():
		if entity is Resident and entity.spawned:
			residents += 1
	_check((residents == 0 and "No one is about." in lines) or (residents > 0 and lines[1].begins_with("%d p" % residents)),
		"the people counted from the bodies seen on this ground (%d: %s)" % [residents, lines[1]])
	_check("Standing: the forge. Building: the temple, half built." in lines and lines[lines.size() - 1].ends_with("day %d." % Townsfolk.day_of(World.steps)),
		"the buildings in words, the season and day last (%s)" % [lines])
	_main.escape()
	_check(not sheet.visible, "Esc closes it")
	_main.open_town("%s/nowhere" % zone)
	_check(sheet.visible and sheet.lines_shown()[0] == "No town" and TownSheet.none_words() in sheet.lines_shown(), "an untold town: No town")
	_main.town_states["elsewhere/mill"] = {"kitchen": {"state": "standing"}}
	_main.world_map_panel.towns = _main.town_states
	_main.world_map_panel.town_clicked.emit("elsewhere/mill")
	lines = sheet.lines_shown()
	_check(sheet.visible and sheet.town == "elsewhere/mill" and lines[0] == "Mill" and TownSheet.away_words() in lines,
		"the map's town row opens its sheet; from elsewhere the people are unseen (%s)" % [lines])
	_main._on_message("town_sheet", {"town": "elsewhere/mill", "name": "Mill", "treasury": 40, "mood": "safe"})
	lines = sheet.lines_shown()
	_check("Mill is safe." in lines and "Treasury: 40 gold." in lines, "economy's message for it fills its rows at once (%s)" % [lines])
	_main.toggle_town()
	_check(not sheet.visible, "N again closes it")
	_main.town_states = states_was
	_main.town_stages = stages_was
	_main.town_sheets.erase("elsewhere/mill")
	_main.town_sheets.erase(id)
	_main.town_sheets.erase("%s/nowhere" % zone)
	_main._town_sheet_asked.clear()
	_main.world_map_panel.towns = _main.town_states


func _test_card_page() -> void:
	print("== her card page (618, ui's side): the words, the chart, the state read, C and Esc ==")
	_check(CardPage.held_words({"id": "draugr", "words": "the draugr's blessing", "teacher": "the draugr"}) == "I hold the draugr's blessing; the draugr taught it to me."
		and CardPage.held_words({"id": "x", "words": "the rot ward"}) == "I hold the rot ward." and CardPage.held_words({"id": "x"}) == "",
		"a learned thing in her voice: the words and the teacher, never the id")
	_check(CardPage.first_person("You lean to strength: in a fight you trust your arm.") == "I lean to strength: in a fight I trust my arm."
		and CardPage.first_person("You are as handy one way in a fight as another.") == "I am as handy one way in a fight as another.",
		"the words said to her, said by her")
	var table: Dictionary = CompanionCard.focus_rules().get("words", {})
	_check(CardPage.lean_words("stealth") == CardPage.first_person(str(table.get("stealth"))) and CardPage.lean_words("") == CardPage.first_person(str(table.get("")))
		and CardPage.lean_words("stealth").begins_with("I lean to") and CardPage.lean_words("").begins_with("I am"),
		"her lean's sentence and the even hand's come from the focus words her own voice uses (%s)" % CardPage.lean_words("stealth"))
	_check(CardPage.AXES[0][1] == "Fighting" and CardPage.AXES[1][1] == "Magic" and CardPage.AXES[2][1] == "Stealth", "the chart's corners are the sim's three: Fighting, Magic, Stealth")
	_check(CardPage.purse_words({}) == "" and CardPage.purse_words({"companion_gold": {"companion": "Wren", "gold": 12}}) == "I carry 12 gold for you. Only you may take it back."
		and CardPage.purse_words({"companion_gold": {"companion": "Wren", "gold": 0}}) == "My purse is empty.", "her purse's words once the key is there; none before")
	var points := CardPage.chart_points({"fight": 30, "magic": 60, "stealth": 90}, Vector2.ZERO, 100.0)
	_check(points.size() == 3 and points[0].is_equal_approx(Vector2(0, -50)) and absf(points[1].length() - 100.0) < 0.01 and absf(points[2].length() - 100.0) < 0.01,
		"the chart's points: a share's way out along its axis, full at CHART_FULL and no further")
	_check(CardPage.her_name({"focus": {"companion": "Nix", "fight": 25, "magic": 45, "stealth": 30}}, "") == "Nix" and CardPage.her_name({}, "Pip") == "Pip"
		and CardPage.her_name({}, "") == "", "her name: the body's, else the message's, else none")
	var page: CardPage = _main.card_page
	if page == null:
		print("  (no card page in this scene: its checks skipped)")
		return
	var state_was: Dictionary = _main.world_state
	var pet: Companion = _main._own_companion()
	var body_name := String(pet.name) if pet != null else ""
	_main.world_state = {}
	_main.toggle_card()
	if pet == null:
		_check(page.visible and page.title_shown() == "Your companion" and page._alone.visible, "opened with nobody: the page says no one travels with you")
	else:
		_check(page.visible and page.title_shown() == body_name and page.learned_shown() == PackedStringArray([CardPage.nothing_learned_words()])
			and page.lean_shown() == CardPage.unknown_bent_words(), "opened before the server has told anything: her body's name, nothing learned, her bent unseen")
	_main._on_message("world", {"full": false, "capabilities": {"companion": "Wren", "held": [{"id": "draugr", "words": "the draugr's blessing", "teacher": "the draugr"}]},
		"focus": {"companion": "Wren", "fight": 40, "magic": 20, "stealth": 40}})
	_check(page.title_shown() == (body_name if pet != null else "Wren") and page.learned_shown() == PackedStringArray(["I hold the draugr's blessing; the draugr taught it to me."])
		and page.lean_shown() == CardPage.lean_words("") and page._chart.focus == {"fight": 40, "magic": 20, "stealth": 40} and page.purse_shown() == "",
		"the world message read while open: her name (the body's first), the held mark's line, the even hand, no purse row")
	_main._on_message("world", {"full": false, "focus": {"companion": "Wren", "fight": 30, "magic": 20, "stealth": 50}})
	_check(page.lean_shown() == CardPage.lean_words("stealth") and page._chart.lean == "stealth", "her focus moving to a lean: the sentence and the chart's mark follow")
	# Her purse: the key companions' 614 will send; the page reads it once WorldNews.merge keeps it (theirs), the row absent till then.
	page.show_state({"focus": {"companion": "Wren", "fight": 30, "magic": 20, "stealth": 50}, "companion_gold": {"companion": "Wren", "gold": 12}}, body_name)
	_check(page.purse_shown() == "I carry 12 gold for you. Only you may take it back.", "companion_gold in the state is her purse row")
	_check(page.visible and page.title_shown() == (body_name if pet != null else "Wren"), "the page stays as it was otherwise")
	# How she feels about you: her bond's tier word (Companion.bond_step, 555) and its reason, from her node.
	_check(CardPage.feels_words("devoted") == "Devoted." and CardPage.feels_words("wary") == "Wary." and CardPage.feels_words("") == "",
		"the tier word as the party line says it; nothing for no step")
	_check(page.feels_shown() == "" and not page._feels_heading.visible, "no step given: no feelings row")
	page.show_state({"focus": {"companion": "Wren", "fight": 30, "magic": 20, "stealth": 50}}, body_name if pet != null else "Wren", "devoted", "you stood by her in the barrow")
	_check(page.feels_shown() == "Devoted." and page.feels_why_shown() == "you stood by her in the barrow" and page._feels_heading.visible,
		"her step and its reason: How she feels about you")
	page.show_state({"focus": {"companion": "Wren", "fight": 30, "magic": 20, "stealth": 50}}, body_name if pet != null else "Wren", "wary", "")
	_check(page.feels_shown() == "Wary." and page.feels_why_shown() == "" and not page._feels_why.visible, "a step with no reason: the word alone")
	if pet != null:
		var step_was: String = pet.bond_step
		var why_was: String = pet.bond_why
		pet.bond_step = "close"
		pet.bond_why = "you fed her when she was hungry"
		_main._refresh_card()
		_check(page.feels_shown() == "Close." and page.feels_why_shown() == "you fed her when she was hungry", "opened on her body: her node's step and reason")
		pet.bond_step = step_was
		pet.bond_why = why_was
	_main.escape()
	_check(not page.visible, "Esc closes it")
	if pet != null and Net.is_authority():
		# The host's own path: the sim sets her focus and tells the client, the page reads it.
		var record: PlayerRecord = _main._records.get(pet.keeper_id)
		if record != null:
			pet.focus = {"fight": 20.0, "magic": 50.0, "stealth": 30.0}
			_main._tell_focus(record, pet)
			_main.toggle_card()
			_check(page.title_shown() == String(pet.name) and page._chart.focus == {"fight": 20, "magic": 50, "stealth": 30} and page.lean_shown() == CardPage.lean_words("magic"),
				"the host's sim telling her focus: the page shows her body's name and the magic lean")
			_main.toggle_card()
	_main.world_state = state_was


func _test_revive_reads() -> void:
	print("== downed and brought back, read on the HUD (544, ui's side) ==")
	_check(Main.downed_words(12) == "You are down: 12 s" and Main.downed_words(-3) == "You are down: 0 s", "the countdown's words")
	_check(Main.channel_words("Wren", 3) == "bringing Wren back: 3 s", "the channeler's words, with the name the client shows")
	# 396 amended, ui's side: the dead player's line, who brings them back and in how long.
	_check(Main.return_words("Hob", "healers_hut", 58) == "Hob is bringing you back to the healer's hut: 58 s"
		and Main.return_words("Ned", "temple", -1) == "Ned is bringing you back to the temple soon"
		and Main.return_words("", "", 2) == "coming back: 2 s" and Main.return_words("", "", -1) == "coming back soon",
		"the return's words: the keeper, the place, the seconds or soon; the old respawn's coming back")
	_main._return_told = {"by": "Hob", "where": "healers_hut", "seconds": 10}
	_main._return_at = Time.get_ticks_msec() / 1000.0 - 3.2
	_check(_main.return_shown() == "Hob is bringing you back to the healer's hut: 7 s", "the countdown runs on the client's clock (%s)" % _main.return_shown())
	_main._return_at = Time.get_ticks_msec() / 1000.0 - 12.0
	_check(_main.return_shown() == "Hob is bringing you back to the healer's hut soon", "past the seconds: soon")
	_main._return_told = {}
	_check(_main.return_shown() == "", "no message: nothing")
	_check(is_zero_approx(Main.channel_fraction(100, 140, 100)) and is_equal_approx(Main.channel_fraction(100, 140, 120), 0.5)
		and is_equal_approx(Main.channel_fraction(100, 140, 150), 1.0) and is_equal_approx(Main.channel_fraction(100, 100, 100), 1.0),
		"the ring's course: from first seen to the end, clamped")


func _test_counter_panel() -> void:
	print("== the counter screen: the work offered, being worked, waiting, refusals ==")
	var panel: CounterPanel = _main.counter_panel
	_check(panel != null and not panel.visible, "there, hidden")
	panel.show_counter({"kind": "temple", "why": "the fee is 6 gold",
		"jobs": [{"slot": 0, "uid": 1, "id": "dagger", "effect": "bless", "price": 6, "ok": true},
			{"slot": 1, "uid": 2, "id": "hammer", "effect": "reforge", "to_id": "sword", "price": 12, "materials": {"ore": 2},
				"ok": false, "why": "the town lacks 2 ore"}],
		"working": [{"uid": 3, "id": "bow", "effect": "bless", "left": 900, "left_seconds": 90}],
		"waiting": [{"uid": 4, "id": "shield", "effect": "bless"}]},
		func(slot: int) -> String: return ["Wren's dagger", "hammer"][slot])
	var rows := panel.rows_shown()
	_check(rows.size() == 6 and rows[0] == "Wren's dagger: blessed [Order]"
			and rows[1] == "hammer: reforged into a %s (the town lacks 2 ore)" % Items.name_of("sword")
			and rows[3].begins_with("%s, being blessed; ready in about 2 minute" % Items.name_of("bow"))
			and rows[5] == "%s, blessed [Collect]" % Items.name_of("shield"),
		"a row per job with Order or its why, the work in hand with its time, the waiting with Collect (%s)" % [rows])
	_check(panel.why_shown() == "the fee is 6 gold", "the last refusal under it all")
	var ordered := []
	panel.order_pressed.connect(func(slot: int, effect: String, to_id: String) -> void: ordered.assign([slot, effect, to_id]))
	(panel._jobs.get_child(0).get_node("Button") as Button).pressed.emit()
	_check(ordered == [0, "bless", ""], "Order: the slot and the effect (%s)" % [ordered])
	var collected := [0]
	panel.collect_pressed.connect(func(uid: int) -> void: collected[0] = uid)
	(panel._waiting.get_child(1).get_node("Button") as Button).pressed.emit()
	_check(collected[0] == 4, "Collect: the thing's uid")
	panel.show_counter({"kind": "shop", "jobs": [], "working": [], "waiting": [], "why": ""}, Callable())
	_check(panel.rows_shown() == ["Nothing you carry can be worked here."] and panel.why_shown() == "",
		"nothing to do: said so")


func _test_world_map() -> void:
	print("== the world map: the areas laid out, the ways, the player's area, M and Esc ==")
	var panel: WorldMapPanel = _main.world_map_panel
	_check(panel != null and not panel.visible and panel.world == null, "there, hidden, not built yet")
	_main.open_world_map()
	var boxes: Dictionary = panel.boxes()
	_check(panel.visible and panel.world != null and boxes.has("castle") and boxes.has("wilds"),
		"opened: built from the levels (%d areas)" % boxes.size())
	var apart := true
	var names: Array = boxes.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (boxes[names[i]] as Rect2).intersects(boxes[names[j]]):
				apart = false
	_check(apart, "no two areas' boxes overlap")
	var hidden_ways := panel.world.ways.filter(func(way: Dictionary) -> bool: return bool(way.get("hidden", false)))
	_check(not hidden_ways.is_empty() and panel.ways_drawn().size() == panel.world.ways.size() - hidden_ways.size()
		and panel.ways_drawn().all(func(way: Dictionary) -> bool: return not bool(way.get("hidden", false))),
		"a hidden link (the barrow's, 608) is drawn nowhere on the known world (589 amended; %d hidden of %d)" % [hidden_ways.size(), panel.world.ways.size()])
	_check(WorldMapPanel.end_mark({"kind": "edge"}) == "" and WorldMapPanel.end_mark({"kind": "link", "cue": "down", "closed": false, "hidden": false}) == "mouth"
		and WorldMapPanel.end_mark({"kind": "link", "cue": "up", "closed": false, "hidden": false}) == "ring"
		and WorldMapPanel.end_mark({"kind": "link", "cue": "sealed", "closed": true, "hidden": false}) == "sealed"
		and WorldMapPanel.end_mark({"kind": "link", "cue": "none", "closed": true, "hidden": false}) == "sealed"
		and WorldMapPanel.end_mark({"kind": "link", "cue": "arch", "closed": false, "hidden": false}) == "dot",
		"a link's end mark on the known world by its cue: a dark mouth down, a light ring up, dim when sealed, the dot otherwise (589, ui's side)")
	_check(panel.ways_drawn().any(func(way: Dictionary) -> bool: return WorldMapPanel.end_mark(way) == "mouth"),
		"the barrow's way down ends in a mouth")
	_check(panel.own_area == World.zone.name, "the player's area is the zone (%s)" % panel.own_area)
	_check(panel.faction_look("goblins")["name"] == "the Blood Rot" and panel.faction_look("nobody")["name"] == "nobody",
		"a faction's name and colour from levels/factions.json")
	panel.set_world_state({"holdings": {"wilds/camp": ["goblins", 3]}, "known_areas": ["wilds"], "known_places": ["wilds/camp"],
		"party": [{"name": "Wren", "area": "castle", "kind": "companion"}]}, [{"name": "Tam", "area": panel.own_area, "kind": "player"}])
	_check(panel.holdings.has("wilds/camp") and panel.known_areas.has("wilds") and panel.party.size() == 2,
		"maps' world_state read: holdings, known, the party here and elsewhere")
	# The guide (551, ui's side): what she knows the way to, the marks' words, the ask box.
	panel.set_world_state({"guide": {"companion": "Wren", "places": ["wilds/camp"], "areas": ["castle"]}}, [])
	_check(panel.knows_way("wilds/camp") and panel.knows_way("castle") and not panel.knows_way("wilds/well") and not panel.knows_way(""),
		"what she knows the way to, from world_state's guide")
	_check(WorldMapPanel.knows_words("Wren") == "Wren knows the way" and WorldMapPanel.ask_words("Wren").begins_with("ask Wren to lead you there")
		and WorldMapPanel.leads_words("Wren") == "> Wren leads you here", "the mark's words, the ask box's, the led row's")
	_check(Main.led_words("Wren", "the Barrow") == "Following Wren to the Barrow - move to take the lead"
		and Main.led_words("Wren", "") == "Following Wren - move to take the lead", "the HUD's words while led, with and without the place")
	_check(panel.place_words("castle") == str(panel.world.areas["castle"].get("display_name", "castle"))
		and panel.place_words("nowhere/x") == "nowhere/x" and panel.place_words("") == "", "a place or area's shown name from the map")
	var asked: Array = []
	panel.guide_asked.connect(func(to: String) -> void: asked.append(to))
	panel.show_ask("wilds/camp")
	_check(panel.ask_pending() == "wilds/camp", "the ask box stands beside a place she knows")
	panel.confirm_ask()
	_check(asked == ["wilds/camp"] and panel.ask_pending() == "", "Enter: the ask goes out as the guide command's place, the box gone")
	panel.show_ask("wilds/well")
	_check(panel.ask_pending() == "", "no box for a place she does not know")
	panel.show_ask("wilds/camp")
	panel.close()
	_check(panel.ask_pending() == "", "closing the map closes the box")
	_main.open_world_map()
	panel.set_world_state({}, [])
	_main.escape()
	_check(not panel.visible, "Esc closes it")
	_main.press_m()
	_check(_main.minimap.big and not panel.visible, "M: the zone's big map")
	_main.press_m()
	_check(not _main.minimap.big and panel.visible, "M again: the world map in its place")
	_main.press_m()
	_check(not panel.visible and not _main.minimap.big, "M again: closed")


func _test_access() -> void:
	print("== accessibility: the interface size, the text size, the colour set ==")
	var panel: OptionsPanel = _main.options_panel
	var kept: Array = [Net._settings_override, Net.player_id, Net.player_name, Net.ui_scale, Net.text_scale, Net.colours]
	Net._settings_override = preload("res://tests/test_ports.gd").scratch_path("ui_test_access.cfg")
	Net.save_settings("127.0.0.1", 17841, "", Net.player_name)
	_check(panel.choices.has("ui_scale") and panel.choices.has("text_scale") and panel.choices.has("colours"),
		"a choice row each for the interface size, the text size and the colours")
	var body_was := UiTheme.theme().default_font_size
	var title_was := UiTheme.theme().get_font_size("font_size", "Title")
	(panel.choices["text_scale"]["buttons"]["1.50"] as Button).pressed.emit()
	_check(is_equal_approx(Net.text_scale, 1.5) and UiTheme.theme().default_font_size == roundi(body_was * 1.5)
			and UiTheme.theme().get_font_size("font_size", "Title") == roundi(title_was * 1.5)
			and UiTheme.size("body") == roundi(body_was * 1.5)
			and "text_scale=1.50" in FileAccess.get_file_as_string(Net._settings_override),
		"Largest text: the theme's sizes half again, settings.cfg follows")
	(panel.choices["text_scale"]["buttons"]["1.00"] as Button).pressed.emit()
	_check(UiTheme.theme().default_font_size == body_was and UiTheme.theme().get_font_size("font_size", "Title") == title_was,
		"and back to the .tres's own")
	(panel.choices["ui_scale"]["buttons"]["1.25"] as Button).pressed.emit()
	_check(is_equal_approx(Net.ui_scale, 1.25) and "ui_scale=1.25" in FileAccess.get_file_as_string(Net._settings_override),
		"Larger interface: Net and settings.cfg follow (the root scales when there is a window)")
	(panel.choices["ui_scale"]["buttons"]["1.00"] as Button).pressed.emit()
	var friend_was := UiTheme.color("friend")
	(panel.choices["colours"]["buttons"]["distinct"] as Button).pressed.emit()
	_check(Net.colours == "distinct" and UiTheme.color("friend") != friend_was
			and UiTheme.color("friend").is_equal_approx(Color.html("#7ab8ec"))
			and "colours=distinct" in FileAccess.get_file_as_string(Net._settings_override),
		"Distinct colours: the theme's friend colour swapped, settings.cfg follows")
	var normal: Dictionary = UiTheme.COLOUR_SETS["normal"]
	var distinct: Dictionary = UiTheme.COLOUR_SETS["distinct"]
	var apart := true
	for a: String in distinct:
		for b: String in distinct:
			if a < b and absf(Color.html(distinct[a]).get_luminance() - Color.html(distinct[b]).get_luminance()) < 0.08:
				apart = false
	_check(normal.keys() == distinct.keys() and apart, "the Distinct set differs in lightness between every pair, not hue alone")
	(panel.choices["colours"]["buttons"]["normal"] as Button).pressed.emit()
	_check(UiTheme.color("friend").is_equal_approx(friend_was), "and back")
	# The low-horizon camera trial (decision 623): a Video row, camera=low in settings.cfg.
	var low_was := Net.camera_low
	var told: Array = []
	var hear := func(low: bool) -> void: told.append(low)
	Net.camera_low_changed.connect(hear)
	_check(panel.choices.has("camera"), "a Video row for the low-horizon camera trial")
	(panel.choices["camera"]["buttons"]["on"] as Button).pressed.emit()
	_check(Net.camera_low and told == [true] and "camera=low" in FileAccess.get_file_as_string(Net._settings_override),
		"On: Net.camera_low, the view told once, settings.cfg camera=low")
	(panel.choices["camera"]["buttons"]["on"] as Button).pressed.emit()
	_check(told == [true], "pressed again: not told again")
	(panel.choices["camera"]["buttons"]["off"] as Button).pressed.emit()
	_check(not Net.camera_low and told == [true, false] and "camera=high" in FileAccess.get_file_as_string(Net._settings_override),
		"Off: told, and settings.cfg camera=high")
	Net.camera_low_changed.disconnect(hear)
	Net.set_camera_low(low_was, false)
	DirAccess.remove_absolute(Net._settings_override)
	Net._settings_override = kept[0]
	Net.player_id = kept[1]
	Net.player_name = kept[2]
	Net.set_ui_scale(kept[3], false)
	Net.set_text_scale(kept[4], false)
	Net.set_colours(kept[5], false)


func _test_keys() -> void:
	print("== the keys: today's defaults, a rebinding swap, settings round trip, the Options rows ==")
	var today := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"open": KEY_E, "pack": KEY_I, "pick_up": KEY_F, "drop": KEY_G, "throw": KEY_T, "talk": KEY_ENTER,
		"talk_log": KEY_TAB, "map": KEY_M, "lantern": KEY_L, "reset": KEY_R, "options": KEY_O, "hints": KEY_H,
		"debug": KEY_F3, "fullscreen": KEY_F11, "builder": KEY_K, "phrase_1": KEY_1, "phrase_2": KEY_2,
		"phrase_3": KEY_3, "phrase_4": KEY_4, "stand": KEY_SHIFT, "signature": KEY_CTRL, "bandage": KEY_B, "screenshot": KEY_F12, "yes": KEY_Y,
		"card": KEY_C, "town": KEY_N}
	var same := Keys.DEFAULTS.size() == today.size()
	for action: String in today:
		same = same and int(Keys.DEFAULTS.get(action, -1)) == int(today[action])
	_check(same, "every default key is the key the game has always used (%d actions)" % today.size())
	Keys.reset()
	var press := InputEventKey.new()
	press.keycode = KEY_E
	press.pressed = true
	_check(Keys.pressed(press, "open") and not Keys.pressed(press, "pack"), "Keys.pressed: E opens, not the pack")
	var enter := InputEventKey.new()
	enter.keycode = KEY_KP_ENTER
	enter.pressed = true
	_check(Keys.pressed(enter, "talk"), "the keypad's Enter counts as Enter")
	Keys.bind("open", KEY_I)
	_check(Keys.code("open") == KEY_I and Keys.code("pack") == KEY_E, "binding I to open swaps the pack to E: no key twice")
	Keys.bind("open", KEY_ESCAPE)
	_check(Keys.code("open") == KEY_I, "Esc is never bound")
	var lines := Keys.lines()
	_check("key_open=I" in lines and "key_pack=E" in lines and lines.size() == 2, "settings lines for the two changed (%s)" % [lines])
	Keys.reset()
	Keys.read({"key_open": "I", "key_pack": "E", "key_map": "nonsense"})
	_check(Keys.code("open") == KEY_I and Keys.code("pack") == KEY_E and Keys.code("map") == KEY_M, "read back; nonsense left as it was")
	Keys.reset()
	# 453 amended: the walk reads its keys through the table. The controls
	# list's walk line belongs to the WASD scheme (the click scheme's lines
	# name the tilt and turn keys).
	var scheme := Net.controls
	Net.controls = "wasd"
	_check(Keys.walk_names() == "WASD" and _main.hint_lines().has("WASD\twalk"), "the walk's keys by default: WASD, named so in the controls list")
	Input.parse_input_event(_key_event(KEY_Z, true, KEY_W))  # W's place on an AZERTY keyboard sends Z.
	Input.flush_buffered_events()
	_check(Keys.walk_held() == "w", "a walk key at its default is read by its physical place too (AZERTY's Z walks forward)")
	Keys.bind("forward", KEY_UP)
	_check(Keys.walk_held() == "", "rebound, it is read by its keycode alone")
	Input.parse_input_event(_key_event(KEY_Z, false, KEY_W))
	Input.parse_input_event(_key_event(KEY_UP, true))
	Input.flush_buffered_events()
	_check(Keys.walk_held() == "w" and Keys.walk_names() == "Up A S D" and _main.hint_lines().has("Up A S D\twalk")
			and "key_forward=Up" in Keys.lines(), "Up bound to forward: held, it walks forward; the list says Up A S D; saved as key_forward=Up")
	Net.controls = "click"
	_check(_main._client3d == null or _main.hint_lines().has("Up / S\ttilt"), "the click scheme's tilt line names it too")
	Input.parse_input_event(_key_event(KEY_UP, false))
	Input.flush_buffered_events()
	Keys.reset()
	Net.controls = scheme
	_check(Keys.walk_held() == "" and Keys.walk_names() == "WASD", "let go and reset: nothing held, WASD again")
	_check(_main.hint_lines().has("E\topen a chest, crate, cart, door; your companion's pack") and _main._item_action_of(KEY_G) == "drop"
			and _main._phrase_of(KEY_3) == 3 and _main._phrase_of(KEY_9) == 0, "Main reads the table: the hints' keys, the item keys, the phrases")
	var panel: OptionsPanel = _main.options_panel
	var kept: Array = [Net._settings_override, Net.player_id, Net.player_name]
	Net._settings_override = preload("res://tests/test_ports.gd").scratch_path("ui_test_keys.cfg")
	Net.save_settings("127.0.0.1", 17841, "", Net.player_name)
	_check(panel.key_buttons.size() == Keys.WORDS.size() and panel.key_buttons["open"].text == "E", "a key row per action, showing its key")
	panel.visible = true
	panel.begin_rebind("open")
	_check(panel.key_buttons["open"].text == "press a key", "pressed: it waits for a key")
	var q := InputEventKey.new()
	q.keycode = KEY_Q
	q.pressed = true
	panel._input(q)
	_check(Keys.code("open") == KEY_Q and panel.key_buttons["open"].text == "Q" and panel.rebinding == ""
			and "key_open=Q" in FileAccess.get_file_as_string(Net._settings_override),
		"Q pressed: open is Q, shown, saved")
	panel.visible = false
	Keys.reset()
	Net.save_view_settings()
	_check("key_open" not in FileAccess.get_file_as_string(Net._settings_override), "reset: no key lines saved")
	DirAccess.remove_absolute(Net._settings_override)
	Net._settings_override = kept[0]
	Net.player_id = kept[1]
	Net.player_name = kept[2]


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## A key event as the keyboard would send it: [param keycode] pressed or
## released, from the key at [param physical] (the same key when not given).
static func _key_event(keycode: Key, pressed: bool, physical: Key = KEY_NONE) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical if physical != KEY_NONE else keycode
	event.pressed = pressed
	return event


## 560, ui's side: the click that interacts, the bubble's bar, the barter window.
func _test_barter() -> void:
	print("== the resident click and the barter window (560, ui's side) ==")
	_check(BarterPanel.sum_words(["sword"], ["hide"], 10) == "+sword -hide +10g" and BarterPanel.sum_words([], ["hide"], 20) == "-hide +20g"
		and BarterPanel.sum_words(["sword"], [], -10) == "+sword -10g" and BarterPanel.sum_words([], [], 0) == "",
		"the sum's words, Jeff's form: +what you take, -what you give, the gold signed from your side")
	_check(BarterPanel.button_words("+sword -hide +10g") == "+sword -hide +10g = Confirm" and BarterPanel.button_words("") == "Confirm",
		"the button reads the sum then = Confirm; Confirm alone with nothing picked")
	_check(BarterPanel.hover_words(true, 10, 0, false) == "takes 10 gold" and BarterPanel.hover_words(false, 0, 20, false) == "pays 20 gold"
		and BarterPanel.hover_words(false, 0, 5, true) == "pays 5 gold, fenced" and BarterPanel.hover_words(false, 0, 0, false) == "won't buy",
		"the hover: takes N gold over theirs; pays N gold, pays N gold fenced, or won't buy over yours")
	_check(BarterPanel.shortfall_words(-15, 12) == "you need 3 more gold" and BarterPanel.shortfall_words(-5, 12) == "" and BarterPanel.shortfall_words(10, 0) == "",
		"the shortfall when the purse can't cover what is owed")
	var panel: BarterPanel = _main.barter_panel
	var pack: PackPanel = _main.pack_panel
	if panel == null or pack == null:
		print("  (no barter panel in this scene: its checks skipped)")
		return
	var asked: Array = []
	panel.trade_asked.connect(func(_shop: GridEntity, give: Array, take: Array, gold_balance: int) -> void: asked.append([give, take, gold_balance]))
	var refusals: Array = []
	panel.refused.connect(func(why: String) -> void: refusals.append(why))
	var sample := {"shop": "", "town": "Umbrage", "gold": 12,
		"goods": [{"uid": 101, "id": "sword", "price": 10}, {"uid": 102, "id": "bandaging_kit", "price": 1}],
		"buys": {"hide": {"gold": 20, "up_to": 1}, "dagger": {"gold": 6, "up_to": 1}}, "fenced": {203: 3},
		"pack": [{"slot": 0, "uid": 201, "id": "hide"}, {"slot": 1, "uid": 202, "id": "dagger"}, {"slot": 2, "uid": 204, "id": "hide"},
			{"slot": 3, "uid": 203, "id": "dagger"}, {"slot": 4, "uid": 205, "id": "food_sack"}], "why": ""}
	panel.open(null, "Snagfin")
	panel.show_barter(sample)
	_check(panel.is_open() and panel.title_shown() == "Snagfin's shop" and panel.button_shown() == "Confirm", "opened for the merchant: the title, Confirm alone")
	panel.toggle_take(101)
	panel.toggle_give(201)
	_check(panel.button_shown() == "+sword -hide +10g = Confirm" and panel.balance_of([201], [101]) == 10 and pack.selected.has(0),
		"a sword taken and a hide given: +sword -hide +10g = Confirm, the hide's box framed (%s)" % panel.button_shown())
	panel.toggle_give(204)
	_check(not panel.give.has(204) and panel.hover_shown() == "the town has enough of that", "a second hide past up_to stays unpicked and says why")
	_check(panel.pays_for(203) == 3 and panel.is_fenced(203) and panel.pays_for(205) == 0, "grave goods pay the fenced half; a thing the town won't buy pays nothing")
	panel.toggle_give(205)
	_check(not panel.give.has(205) and panel.hover_shown() == "won't buy", "won't buy: unpicked, said")
	panel._hover_mine(true, 3)
	_check(panel.hover_shown() == "pays 3 gold, fenced", "hover over the grave dagger: pays 3 gold, fenced")
	panel._hover_theirs(102)
	_check(panel.hover_shown() == "takes 1 gold", "hover over theirs: takes 1 gold")
	panel.toggle_take(102)
	panel.toggle_give(201)
	_check(panel.button_shown() == "+sword +bandages -11g = Confirm" and panel._button.disabled == false, "two taken, nothing given: -11g, within the purse (%s)" % panel.button_shown())
	panel.show_barter({"shop": "", "gold": 5, "goods": sample["goods"], "buys": sample["buys"], "fenced": {}, "pack": sample["pack"], "why": ""})
	_check(panel._button.disabled and panel._foot.text == "you need 6 more gold", "the purse down to 5: you need 6 more gold, Confirm dim")
	panel.toggle_take(102)
	panel._confirm()
	_check(asked == [[[], [101], -10]], "Confirm asks the trade: give none, take the sword, -10 (%s)" % [asked])
	panel.show_barter({"shop": "", "gold": 5, "goods": [], "buys": {}, "fenced": {}, "pack": [], "why": "the prices have moved"})
	_check(panel.why_shown() == "the prices have moved" and refusals == ["the prices have moved"] and panel.take.is_empty(),
		"a refusal: why shown and said; a sword no longer on the shelf is dropped from the pick")
	panel.close()
	_check(not panel.is_open() and pack.selected.is_empty() and panel.button_shown() == "Confirm", "closed: nothing picked, no frames")
	# The bar under a greeting resident's bubble: without a bubble it closes at once.
	var oda: GridEntity = load(Main.RESIDENT).new()
	oda.person = "Oda"
	oda.trade = "cook"
	if _main._local_player() != null:
		var hints_on: bool = Net.hints
		Net.hints = true
		_check(_main.context_hint_for(oda) == "LMB  interact", "the hint over a townsperson with hints=on: LMB  interact")
		Net.hints = false
		_check(_main.context_hint_for(oda) == "", "hints off: nothing over a townsperson (Jeff, 2026-10-22)")
		Net.hints = hints_on
	# A joined client's bar (Jeff on v0.1.168: "barter must not be in the game yet, it just says talk"):
	# a resident's trade and person are set on the server after the spawn and the spec carries neither,
	# so a client's bar reads them only if Resident replicates them from its spawn on (npc's fix).
	var sync := oda.get_node_or_null("Sync") as MultiplayerSynchronizer
	var config: SceneReplicationConfig = sync.replication_config if sync != null else null
	_check(config != null and config.has_property(NodePath(".:trade")) and config.property_get_spawn(NodePath(".:trade"))
		and config.has_property(NodePath(".:person")) and config.property_get_spawn(NodePath(".:person")),
		"a resident's trade and person replicate from the spawn on, so a joined client's bar can read them (the medicine man's Barter)")
	oda.trade = "medicine_man"
	_check(_main._barters(oda), "the medicine man barters (his care and his goods)")
	oda.trade = ""
	_check(not _main._barters(oda), "a body with no trade told (a joined client before the fix): Talk only, the bug Jeff saw")
	oda.trade = "cook"
	_main._open_bar(oda)
	_check(_main._bar_name.text == "Oda" and _main._bar_barter.visible, "the bar names them; Barter for a maker (a cook, 562)")
	oda.trade = "farmer"
	_check(not _main._barters(oda), "no Barter for a farmer")
	oda.trade = "medicine_man"
	_check(_main._barters(oda), "Barter for the medicine man")
	oda.trade = "merchant"
	_main._open_bar(oda)
	_check(_main._bar_barter.visible == (_main._shop_counter_near(oda) != null), "the merchant's Barter needs a counter near")
	# 562: a maker's barter is keyed on the person, the message's "resident".
	_check(BarterPanel.for_path({"resident": "/a/b", "shop": ""}, "/a/b") and not BarterPanel.for_path({"resident": "/a/b", "shop": ""}, "/a/c")
		and BarterPanel.for_path({"shop": "/x"}, "/x") and not BarterPanel.for_path({"shop": "/x"}, "/y") and BarterPanel.for_path({}, "/z"),
		"a barter message is for its resident, else its shop, else anyone")
	_check(BarterPanel.title_words("Oda", true) == "Oda's goods" and BarterPanel.title_words("Snagfin", false) == "Snagfin's shop" and BarterPanel.title_words("", false) == "The shop",
		"the title: a maker's goods in person, the shop at the counter")
	_check(BarterPanel.empty_words({"goods": [], "buys": {}}) == "nothing to trade" and BarterPanel.empty_words({"goods": [], "buys": {"herb": {"gold": 2, "up_to": 3}}}) == "nothing for sale",
		"an empty shelf: nothing to trade, or nothing for sale when they still buy")
	oda.trade = "cook"
	panel.open(oda, "Oda")
	_check(panel.title_shown() == "Oda's goods", "opened with the cook in person: Oda's goods")
	panel.close()
	# The healer's care (economy): a service row in the window, "retain" on Confirm.
	_check(BarterPanel.care_words({"gold": 10, "in_care": true, "by": "herbs"}) == "In his care (for the herbs)"
		and BarterPanel.care_words({"gold": 10, "in_care": true, "by": "quest"}) == "In his care (his errand)"
		and BarterPanel.care_words({"gold": 10, "in_care": true}) == "In his care" and BarterPanel.care_words(null) == "",
		"the care line's words: the way in (584 amended); none without the key")
	_check(BarterPanel.care_offer_words("gold", 10) == "Pay 10 gold" and BarterPanel.care_offer_words("herbs", 5) == "Give herbs (5 to go)"
		and BarterPanel.care_offer_words("antlers", 5, 3) == "Give antlers (2 to go)" and BarterPanel.care_offer_words("herbs", 5, 5) == "Give herbs (0 to go)",
		"the three ways in, as buttons: gold whole, herbs and antlers by instalments with what is left to go (584 amended (2))")
	_check(BarterPanel.care_given({"herbs": 5, "given": {"herbs": 3}}, "herbs") == 3 and BarterPanel.care_given({"herbs": 5, "given": {"herbs": 3}}, "antlers") == 0
		and BarterPanel.care_given({"herbs": 5}, "herbs") == 0 and BarterPanel.care_given(null, "herbs") == 0,
		"the tally from care's given, 0 without it (a client before npc's side)")
	var cared: Array = []
	panel.care_asked.connect(func(who: GridEntity, pay: String) -> void: cared.append([who, pay]))
	oda.trade = "medicine_man"
	panel.open(oda, "Hob")
	panel.show_barter({"gold": 12, "goods": [], "buys": {}, "fenced": {}, "pack": [{"slot": 0, "uid": 301, "id": "herbs"}], "why": "",
		"care": {"gold": 10, "herbs": 5, "antlers": 0, "in_care": false, "by": ""}})
	_check(panel.care_shown() == "Pay 10 gold / Give herbs (5 to go)" and not panel._care["gold"].disabled and not panel._care["herbs"].disabled
		and not panel._care["antlers"].visible, "the healer's window offers the ways in: gold within the purse, herbs with one in the pack (an instalment), no antlers offered")
	panel.show_barter({"gold": 12, "goods": [], "buys": {}, "fenced": {}, "pack": [{"slot": 0, "uid": 301, "id": "herbs"}], "why": "",
		"care": {"gold": 10, "herbs": 5, "antlers": 5, "in_care": false, "by": "", "given": {"herbs": 3, "antlers": 0}}})
	_check(panel.care_shown() == "Pay 10 gold / Give herbs (2 to go) / Give antlers (5 to go)" and not panel._care["herbs"].disabled and panel._care["antlers"].disabled,
		"three herbs handed: two to go, the antlers untouched and dim with none in the pack")
	panel._ask_care("gold")
	_check(cared == [[oda, "gold"]], "the gold button asks for his care, paid")
	panel.show_barter({"gold": 5, "goods": [], "buys": {}, "fenced": {}, "pack": [], "why": "", "care": {"gold": 10, "herbs": 5, "antlers": 5, "in_care": false, "by": ""}})
	_check(panel._care["gold"].disabled and panel._care["herbs"].disabled and panel._care["antlers"].disabled, "a short purse and an empty pack: all three dim")
	panel.show_barter({"gold": 2, "goods": [], "buys": {}, "fenced": {}, "pack": [], "why": "", "care": {"gold": 10, "herbs": 5, "antlers": 5, "in_care": true, "by": "gold"}})
	_check(panel.care_shown() == "In his care (paid)" and not panel._care["gold"].visible, "held: In his care (paid), no buttons")
	panel.close()
	_check(panel.care_shown() == "", "closed: no care row")
	_main._update_bar()
	_check(not _main._bar.visible, "no bubble to sit under: the bar goes")
	_check(not _main._bubble_clicked(), "a click with no bubble under the mouse opens nothing")
	# Jeff on v0.1.165: a click on a player opened the chat window with their name. Now nothing opens.
	var own_body: GridEntity = _main._local_player()
	if own_body != null and _main._chat_box != null:
		_main._close_chat()
		_main._open_talk(own_body)
		_check(not _main._chat_box.visible, "reaching a player by a click opens no chat window")
	oda.free()
