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
	_test_converse_panel()
	_test_counter_panel()
	_test_world_map()
	_test_access()
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
	_check(chest != null and _main.context_hint_for(chest) == "E  open", "a chest: E open")
	_check(_main.context_hint_for(null) == "", "nothing under the cursor: nothing")
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


func _test_converse_panel() -> void:
	print("== the conversation panel: who speaks, the exchange, the offers, the asks ==")
	var panel: ConversePanel = _main.converse
	_check(panel != null and not panel.visible, "there, hidden")
	panel.open(null, "Mara [cook]")
	_check(panel.visible and panel._name.text == "Mara [cook]", "opened on a label when the body has no person")
	panel.add_line("Player", "Any work for me?", false)
	panel.set_thinking(true)
	_check(panel.thinking and panel._dots.text.begins_with("thinking"), "a line sent: thinking")
	panel.add_line("Mara", "Bring Bram home.", true)
	_check(not panel.thinking and panel._lines.get_child_count() == 2, "their answer: the exchange, thinking over")
	panel.show_offers([
		{"id": "a", "kind": "commission", "title": "Bring Bram home", "words": "He was carried off.", "accept": "take", "cost": 0},
		{"id": "b", "kind": "shop", "title": "A loaf, 2 gold", "words": "Baked today.", "accept": "buy", "cost": 2},
		{"id": "c", "kind": "rumour", "title": "What Tam said", "words": "The mine is cursed.", "accept": "", "cost": 0},
		{"id": "d", "kind": "plea", "title": "A loan of 10", "words": "Lend me ten gold.", "accept": "lend", "cost": 10}],
		[{"id": "z", "kind": "commission", "title": "Walk Tam home", "open": true}])
	_check(panel.offers_shown() == ["Bring Bram home [Take it on]", "A loaf, 2 gold [Buy]", "What Tam said", "A loan of 10 [Lend]"],
		"the offers: a title, the accept's words, none for a rumour (%s)" % [panel.offers_shown()])
	_check(panel._owed.visible and panel._owed.text == "You owe them: Walk Tam home", "an open commission as what the player owes")
	var got := []
	panel.offer_accepted.connect(func(id: String, gold: int) -> void: got.assign([id, gold]))
	(panel._offer_rows.get_child(0).get_node("Accept") as Button).pressed.emit()
	_check(got == ["a", 0], "Take it on: the offer's id (%s)" % [got])
	(panel._offer_rows.get_child(3).get_node("Accept") as Button).pressed.emit()
	_check(got == ["d", 10], "Lend: the id and the gold asked, up to the loan (%s)" % [got])
	var asked := [""]
	panel.ask_pressed.connect(func(line: String) -> void: asked[0] = line)
	(panel._asks.get_child(2) as Button).pressed.emit()
	_check(asked[0] == "What's the news?" and panel.thinking, "a quick ask: its line sent, thinking")
	_main.escape()
	_check(not panel.visible, "Esc closes it")
	_check(Main.server_status_words({"ok": false, "why": "no answer"}) == "status unknown", "no answer is status unknown")
	var fonts := UiTheme.credits()
	_check(fonts["entries"].size() == 2 and UiTheme.credits in OptionsPanel.credit_providers(),
		"the fonts' credit (Alegreya, Alegreya Sans, OFL) is one of the Credits' providers")


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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
