extends Node
## The in-game update (decision 430), with no network: GitHub's answer read
## for the client zip; a release zip unpacked beside a pretend game a few
## files a frame, saying how far, the zip removed after; a file that is not
## a zip, or a zip with no psykinetic.exe, refused with nothing left behind;
## a cancel halfway leaves nothing either; update.ps1's arguments carry
## -Stage; and update.ps1 -Stage (a dry run, -NoStart, Windows only) copies
## the staged folder over the game, keeping settings.cfg, and removes it.
## Run it with tests/run.ps1 or tests/run.sh.

var _failures := 0
var _folder := ""


func _ready() -> void:
	World.set_process(false)
	_folder = ProjectSettings.globalize_path(preload("res://tests/test_ports.gd").scratch("files/"))
	SelfUpdate.Download._remove_tree(_folder)
	DirAccess.make_dir_recursive_absolute(_folder)
	_test_answer()
	await _test_unpack()
	await _test_refused()
	await _test_cancel()
	_test_script()
	SelfUpdate.Download._remove_tree(_folder)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_answer() -> void:
	print("== GitHub's answer ==")
	var release := {"tag_name": "v0.1.150", "assets": [
		{"name": "psykinetic-server-0.1.150.zip", "browser_download_url": "https://example/server.zip"},
		{"name": "psykinetic-client-0.1.150.zip", "browser_download_url": "https://example/client.zip"}]}
	_check(SelfUpdate.asset_url(release) == "https://example/client.zip", "the client zip's link, not the server's")
	_check(SelfUpdate.asset_url({"assets": []}) == "" and SelfUpdate.asset_url(null) == "", "none in a release without one, or no answer")
	_check(SelfUpdate.release_url("0.1.150").ends_with("/releases/tags/v0.1.150"), "the server's own version is asked for, not the latest")


func _test_unpack() -> void:
	print("== unpacking a release ==")
	var game := _folder.path_join("game")
	DirAccess.make_dir_recursive_absolute(game)
	var names: Array[String] = ["psykinetic.exe", "psykinetic.pck", "version.txt", "settings.cfg"]
	for i in 20:
		names.append("art/fonts/f%d.ttf" % i)
	var zip := _zip(game.path_join("in.zip"), names)
	var download := _download()
	var seen: Array[float] = []
	download.progress.connect(func(fraction: float, _text: String) -> void: seen.append(fraction))
	var watched := _watch(download)
	download.begin_from_zip("0.1.150", game, zip)
	var result: Array = await _until_done(download, watched)
	_check(result == [true, ""], "unpacked (%s)" % [result])
	var stage := game.path_join(SelfUpdate.STAGE)
	_check(download.stage_path == stage and FileAccess.file_exists(stage.path_join("psykinetic.exe"))
		and FileAccess.get_file_as_string(stage.path_join("art/fonts/f19.ttf")) == "art/fonts/f19.ttf",
		"every file in the update folder beside the game, as it was")
	_check(seen.size() >= 3 and seen[-1] == 1.0 and seen.slice(0, -1).all(func(f: float) -> bool: return f < 1.0),
		"a few files a frame, saying how far, then done (%s)" % [seen])
	_check(not FileAccess.file_exists(zip), "the zip removed after")
	download.free()


func _test_refused() -> void:
	print("== a bad download ==")
	var game := _folder.path_join("bad")
	DirAccess.make_dir_recursive_absolute(game)
	var junk := game.path_join("junk.zip")
	var file := FileAccess.open(junk, FileAccess.WRITE)
	file.store_string("not a zip at all")
	file.close()
	var download := _download()
	var watched := _watch(download)
	download.begin_from_zip("0.1.150", game, junk)
	var result: Array = await _until_done(download, watched)
	_check(not result[0] and "not a zip" in result[1] and not DirAccess.dir_exists_absolute(game.path_join(SelfUpdate.STAGE)),
		"not a zip: refused, nothing unpacked (%s)" % [result])
	download.free()
	var names: Array[String] = ["readme.txt"]
	var zip := _zip(game.path_join("no_exe.zip"), names)
	download = _download()
	watched = _watch(download)
	download.begin_from_zip("0.1.150", game, zip)
	result = await _until_done(download, watched)
	_check(not result[0] and "psykinetic.exe" in result[1] and not FileAccess.file_exists(zip),
		"a zip with no psykinetic.exe: refused, the zip removed (%s)" % [result])
	download.free()


func _test_cancel() -> void:
	print("== cancelled ==")
	var game := _folder.path_join("cancel")
	DirAccess.make_dir_recursive_absolute(game)
	var names: Array[String] = ["psykinetic.exe"]
	for i in 40:
		names.append("data/d%d.bin" % i)
	var download := _download()
	var watched := _watch(download)
	download.begin_from_zip("0.1.150", game, _zip(game.path_join("in.zip"), names))
	await get_tree().process_frame
	_check(download.busy(), "still unpacking after a frame")
	download.cancel()
	var result: Array = await _until_done(download, watched)
	_check(not result[0] and "cancelled" in result[1] and not DirAccess.dir_exists_absolute(game.path_join(SelfUpdate.STAGE)),
		"a cancel halfway leaves nothing beside the game (%s)" % [result])
	download.free()


func _test_script() -> void:
	print("== update.ps1 ==")
	var args := SelfUpdate.script_args("C:/game", "C:/game/update_stage")
	_check(args[-2] == "-Stage" and args[-1] == "C:/game/update_stage" and "C:/game/update.ps1" in args, "update.ps1 is told where the update is (%s)" % [args])
	_check(not "-Stage" in SelfUpdate.script_args("C:/game"), "and launch.bat's way has no -Stage")
	if OS.get_name() != "Windows":
		print("  (not Windows: update.ps1's dry run skipped)")
		return
	var game := _folder.path_join("ps")
	var stage := game.path_join(SelfUpdate.STAGE)
	DirAccess.make_dir_recursive_absolute(stage.path_join("art"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://client/update.ps1"), game.path_join("update.ps1"))
	_write(game.path_join("settings.cfg"), "mine")
	_write(game.path_join("version.txt"), "0.1.149")
	_write(stage.path_join("psykinetic.exe"), "new exe")
	_write(stage.path_join("version.txt"), "0.1.150")
	_write(stage.path_join("settings.cfg"), "theirs")
	_write(stage.path_join("art/a.png"), "png")
	var out: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", game.path_join("update.ps1"),
		"-Stage", stage, "-NoStart"], out, true)
	var log := FileAccess.get_file_as_string(game.path_join("update.log"))
	_check(code == 0 and "installed the staged update" in log, "update.ps1 -Stage installs it (exit %d; %s)" % [code, log.strip_edges()])
	_check(FileAccess.get_file_as_string(game.path_join("version.txt")) == "0.1.150" and FileAccess.file_exists(game.path_join("art/a.png"))
		and FileAccess.get_file_as_string(game.path_join("psykinetic.exe")) == "new exe", "the staged files copied over the game")
	_check(FileAccess.get_file_as_string(game.path_join("settings.cfg")) == "mine", "the player's settings.cfg kept")
	_check(not DirAccess.dir_exists_absolute(stage) and "not starting the game" in log, "the staged folder removed; nothing started (-NoStart)")


func _download() -> SelfUpdate.Download:
	var download := SelfUpdate.Download.new()
	add_child(download)
	return download


## [ok, why] once [param download] has finished: watch before it begins
## (a refusal can finish it at once), then _until_done.
func _watch(download: SelfUpdate.Download) -> Array:
	var result: Array = []
	download.finished.connect(func(ok: bool, why: String) -> void: result.assign([ok, why]))
	return result


func _until_done(download: SelfUpdate.Download, result: Array) -> Array:
	var frames := 0
	while result.is_empty() and frames < 600:
		await get_tree().process_frame
		frames += 1
	return result if not result.is_empty() else [false, "never finished (%s)" % download.busy()]


## A zip at [param path] of [param names], each file holding its own name.
func _zip(path: String, names: Array[String]) -> String:
	var packer := ZIPPacker.new()
	packer.open(path)
	for name in names:
		packer.start_file(name)
		packer.write_file(name.to_utf8_buffer())
		packer.close_file()
	packer.close()
	return path


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
