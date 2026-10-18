class_name SelfUpdate
extends RefCounted
## The client updating itself (decision 241): turned away as "client out of
## date" by a server of a newer build, an exported game starts update.ps1
## beside it, which waits for the game to quit, installs the latest release
## and starts the game again. Never on "server out of date", and never twice
## within MIN_GAP_SEC, by a marker file beside the game, so a release that
## still does not match the server cannot loop. In game (decision 430) the
## game fetches the server's own release itself, showing how far it has got
## (Download), unpacks it beside it, and update.ps1 -Stage only waits for it
## to quit and copies that over; launch.bat's update.ps1 is as before.

const MIN_GAP_SEC := 600
const MARKER := "update_marker.txt"
const SCRIPT := "update.ps1"
const REPO := "jeff-thinklightn-ing/psykinetic"
## Beside the game: the downloaded zip, and the folder it is unpacked into
## for update.ps1 -Stage.
const ZIP := "update_download.zip"
const STAGE := "update_stage"
## The release's client zip: psykinetic-client-<version>.zip.
const ASSET_PREFIX := "psykinetic-client-"


## The folder of an exported game ("" for one run from the editor or a
## checkout, which never updates itself).
static func game_dir() -> String:
	return OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ""


## Why the game in [param dir] should not update itself now that a server of
## [param server_version] turned it away for [param reason], or "" if it
## should. [param now] is the unix time.
static func refusal(reason: String, server_version: String, dir: String, now: int) -> String:
	if reason != "client out of date":
		return "the server is the one behind" if reason == "server out of date" else reason
	if not Net.newer_version(server_version, Net.claimed_version()):
		return "the server's v%s is not newer than this v%s" % [server_version, Net.claimed_version()]
	if dir.is_empty():
		return "not an exported game"
	if not FileAccess.file_exists(dir.path_join(SCRIPT)):
		return "no %s beside the game" % SCRIPT
	var marker := dir.path_join(MARKER)
	if FileAccess.file_exists(marker):
		var since := now - FileAccess.get_modified_time(marker)
		if since < MIN_GAP_SEC:
			return "it updated %d s ago, and does at most once in %d s" % [since, MIN_GAP_SEC]
	return ""


## Writes the marker and starts update.ps1 from [param dir]; the caller then
## quits. False, starting nothing, if the marker cannot be written (without
## it nothing stops a loop) or PowerShell cannot be started. With
## [param stage] (a folder Download unpacked), update.ps1 copies that over
## the game instead of fetching the latest itself.
static func start(dir: String, stage := "") -> bool:
	var marker := FileAccess.open(dir.path_join(MARKER), FileAccess.WRITE)
	if marker == null:
		return false
	marker.store_line("v%s updated itself at %s" % [Net.version, Time.get_datetime_string_from_system()])
	marker.close()
	return OS.create_process("powershell.exe", script_args(dir, stage)) > 0


## update.ps1's command line, with -Stage when [param stage] is given.
static func script_args(dir: String, stage := "") -> PackedStringArray:
	var args := PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
		"-File", dir.path_join(SCRIPT)])
	if not stage.is_empty():
		args.append_array(["-Stage", stage])
	return args


## Where GitHub says what release v[param version] holds.
static func release_url(version: String) -> String:
	return "https://api.github.com/repos/%s/releases/tags/v%s" % [REPO, version]


## The client zip's download link in GitHub's [param release] answer, "" if
## it has none.
static func asset_url(release: Variant) -> String:
	if not release is Dictionary:
		return ""
	for asset: Variant in release.get("assets", []):
		if asset is Dictionary:
			var name := str(asset.get("name", ""))
			if name.begins_with(ASSET_PREFIX) and name.ends_with(".zip"):
				return str(asset.get("browser_download_url", ""))
	return ""


## The server's release fetched and unpacked beside the game, a step a
## frame, saying how far it has got: progress(fraction, text), fraction -1
## while it cannot tell; then finished(ok, why), why "" when the folder at
## stage_path is ready for start(dir, stage_path). Main makes it a child
## and frees it after. Nothing of the game's is replaced: a failure or a
## cancel removes the zip and the folder.
class Download:
	extends Node
	signal progress(fraction: float, text: String)
	signal finished(ok: bool, why: String)

	## Files unpacked a frame.
	const FILES_A_FRAME := 8
	const MB := 1048576.0

	var version := ""
	var dir := ""
	var stage_path := ""
	var zip_path := ""
	## Where the release's answer is asked (release_url unless set first).
	var url := ""
	var _http: HTTPRequest
	## "", "asking", "downloading" or "unpacking".
	var _state := ""
	var _zip: ZIPReader
	var _files: PackedStringArray = []
	var _next := 0

	## Fetches v[param with_version] for the game in [param with_dir].
	func begin(with_version: String, with_dir: String) -> void:
		_setup(with_version, with_dir)
		if url.is_empty():
			url = SelfUpdate.release_url(version)
		_http = HTTPRequest.new()
		_http.timeout = 20.0
		_http.max_redirects = 8
		add_child(_http)
		_http.request_completed.connect(_on_release)
		_state = "asking"
		progress.emit(-1.0, "finding v%s" % version)
		if _http.request(url, ["User-Agent: psykinetic-updater", "Accept: application/vnd.github+json"]) != OK:
			_fail("could not ask GitHub for v%s" % version)

	## Unpacks the zip at [param path] as if it had just been downloaded
	## (tests; no network).
	func begin_from_zip(with_version: String, with_dir: String, path: String) -> void:
		_setup(with_version, with_dir)
		zip_path = path
		_unpack()

	## Whether it is still going.
	func busy() -> bool:
		return not _state.is_empty()

	func cancel() -> void:
		if busy():
			_fail("the update was cancelled")

	func _setup(with_version: String, with_dir: String) -> void:
		version = with_version
		dir = with_dir
		stage_path = dir.path_join(SelfUpdate.STAGE)
		zip_path = dir.path_join(SelfUpdate.ZIP)

	func _on_release(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if _state != "asking":
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_fail("GitHub has no v%s (%s)" % [version, "HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "no connection"])
			return
		var link := SelfUpdate.asset_url(JSON.parse_string(body.get_string_from_utf8()))
		if link.is_empty():
			_fail("v%s has no client zip" % version)
			return
		_http.request_completed.disconnect(_on_release)
		_http.request_completed.connect(_on_zip)
		_http.timeout = 600.0
		_http.download_file = zip_path
		_state = "downloading"
		if _http.request(link, ["User-Agent: psykinetic-updater"]) != OK:
			_fail("could not start downloading v%s" % version)

	func _on_zip(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		if _state != "downloading":
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_fail("the download of v%s failed (%s)" % [version, "HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "result %d" % result])
			return
		_unpack()

	func _unpack() -> void:
		_zip = ZIPReader.new()
		if _zip.open(zip_path) != OK:
			_zip = null
			_fail("the download of v%s is not a zip" % version)
			return
		_files = _zip.get_files()
		if not "psykinetic.exe" in _files:
			_fail("the download of v%s has no psykinetic.exe" % version)
			return
		_remove_tree(stage_path)
		DirAccess.make_dir_recursive_absolute(stage_path)
		_next = 0
		_state = "unpacking"

	func _process(_delta: float) -> void:
		if _state == "downloading":
			var total := _http.get_body_size()
			var done := _http.get_downloaded_bytes()
			progress.emit(float(done) / total if total > 0 else -1.0, "downloading v%s: %d of %s MB" % [
				version, roundi(done / MB), str(roundi(total / MB)) if total > 0 else "?"])
		elif _state == "unpacking":
			for i in FILES_A_FRAME:
				if _next >= _files.size():
					_done()
					return
				var name := _files[_next]
				_next += 1
				var target := stage_path.path_join(name)
				if name.ends_with("/"):
					DirAccess.make_dir_recursive_absolute(target)
					continue
				DirAccess.make_dir_recursive_absolute(target.get_base_dir())
				var out := FileAccess.open(target, FileAccess.WRITE)
				if out == null:
					_fail("could not write %s (no room?)" % target)
					return
				out.store_buffer(_zip.read_file(name))
				out.close()
			progress.emit(float(_next) / _files.size(), "unpacking v%s" % version)

	func _done() -> void:
		_close()
		DirAccess.remove_absolute(zip_path)
		_state = ""
		progress.emit(1.0, "v%s is ready" % version)
		finished.emit(true, "")

	func _fail(why: String) -> void:
		if _http != null:
			_http.cancel_request()
		_close()
		DirAccess.remove_absolute(zip_path)
		_remove_tree(stage_path)
		_state = ""
		finished.emit(false, why)

	func _close() -> void:
		if _zip != null:
			_zip.close()
			_zip = null

	static func _remove_tree(path: String) -> void:
		var folder := DirAccess.open(path)
		if folder == null:
			return
		for sub in folder.get_directories():
			_remove_tree(path.path_join(sub))
		for file in folder.get_files():
			DirAccess.remove_absolute(path.path_join(file))
		DirAccess.remove_absolute(path)
