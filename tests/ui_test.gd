extends Node
## The core screens (ui's step 2): the main menu's buttons, the connect
## screen's fields, states and buttons, the pause panel, Esc's order
## (what is open closes first, then the pause), and the options' Window,
## Resolution, Controls and hints choices writing to Net and settings.cfg.
## Run it with tests/run.ps1 or run.sh. Prints PASS/FAIL per assertion and
## quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17840)  # Its own, beside the other tests'.
	_test_menu()
	_test_connect_screen()
	_test_pause_panel()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await _test_escape()
	_test_options_choices()
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
	screen.queue_free()


func _test_pause_panel() -> void:
	print("== the pause panel ==")
	var pause := PausePanel.new()
	add_child(pause)
	_check(not pause.visible, "hidden until Esc")
	pause.open(true)
	_check(pause.visible and pause.resume.has_focus(), "open: shown, Resume focused")
	var resumed := [false]
	pause.resume_pressed.connect(func() -> void: resumed[0] = true)
	pause.resume.pressed.emit()
	_check(resumed[0], "Resume asks Main to close it")
	pause.queue_free()


func _test_escape() -> void:
	await get_tree().process_frame
	print("== Esc: what is open closes first, then the pause ==")
	_check(_main.pause_panel == null, "no pause panel before the first Esc")
	_main.escape()
	_check(_main.pause_panel != null and _main.pause_panel.visible, "Esc with nothing open: the pause")
	await get_tree().process_frame
	var rect: Rect2 = _main.pause_panel.get_global_rect()
	var middle := get_viewport().get_visible_rect().get_center()
	_check(rect.get_center().distance_to(middle) < 4.0 and rect.size.y > 100.0,
		"in the middle of the screen (%s, middle %s)" % [rect, middle])
	_main.escape()
	_check(not _main.pause_panel.visible, "Esc again: resumed")
	_main.toggle_options()
	_check(_main.options_panel.visible, "O: the options open")
	_main.escape()
	_check(not _main.options_panel.visible and not _main.pause_panel.visible, "Esc closes the options, not the pause")
	_main.escape()
	_check(_main.pause_panel.visible, "then the pause")
	_main.pause_panel.options.pressed.emit()
	_check(_main.options_panel.visible, "the pause's Options opens them")
	_main.escape()
	_main.escape()
	_check(not _main.options_panel.visible and not _main.pause_panel.visible, "and two Escs close both")


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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
