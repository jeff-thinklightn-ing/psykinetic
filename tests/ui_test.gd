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
	_test_menu()
	_test_connect_screen()
	_test_game_menu()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await _test_escape()
	_test_options_choices()
	_test_item_tip()
	await _test_talk_panel()
	_test_context_and_place()
	_test_talk_no_panel()
	_test_sim_reads()
	_test_minimap_turn()
	_test_revive_reads()
	_test_screenshot_key()
	_test_aim()
	_test_counter_panel()
	_test_world_map()
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
	_check(Main.aim_pips(3, [3, 5, 7, 9]) == 4 and Main.aim_pips(9, [3, 5, 7, 9]) == 1 and Main.aim_pips(4, [3, 5, 7, 9]) == 0 and Main.aim_pips(5, []) == 0,
		"pips: four at the shortest step, one at the longest, none off the steps or without them")
	_check(Main.aim_fade(0) == 0.0 and absf(Main.aim_fade(100) - 0.5) < 0.001 and Main.aim_fade(400) == 1.0, "the arc fades in over its first fifth of a second")
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
		"phrase_3": KEY_3, "phrase_4": KEY_4, "stand": KEY_SHIFT, "signature": KEY_CTRL, "bandage": KEY_B, "screenshot": KEY_F12, "yes": KEY_Y}
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
	var sample := {"shop": "", "town": "Held", "gold": 12,
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
	_check(BarterPanel.care_offer_words("gold", 10) == "Pay 10 gold" and BarterPanel.care_offer_words("herbs", 5) == "Give 5 herbs"
		and BarterPanel.care_offer_words("antlers", 5) == "Give 5 antlers", "the three ways in, as buttons")
	var cared: Array = []
	panel.care_asked.connect(func(who: GridEntity, pay: String) -> void: cared.append([who, pay]))
	oda.trade = "medicine_man"
	panel.open(oda, "Hob")
	panel.show_barter({"gold": 12, "goods": [], "buys": {}, "fenced": {}, "pack": [{"slot": 0, "uid": 301, "id": "herbs"}], "why": "",
		"care": {"gold": 10, "herbs": 5, "antlers": 0, "in_care": false, "by": ""}})
	_check(panel.care_shown() == "Pay 10 gold / Give 5 herbs" and not panel._care["gold"].disabled and panel._care["herbs"].disabled
		and not panel._care["antlers"].visible, "the healer's window offers the ways in with a price: gold within the purse, herbs short (one of five), no antlers offered")
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
