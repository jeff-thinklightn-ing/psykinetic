extends RefCounted
## The mind log's and transcripts' file writes, off the tick (decision 785).
## A line is queued (already scrubbed: 781) and one thread of its own appends
## it; a rotation (the mind log past its size) and the transcripts' daily
## prune go on the same thread, in order. The thread touches only its queue
## and its files: plain strings and FileAccess/DirAccess, never a node or the
## world. flush() waits till the queue is empty (readers, tests); stop()
## drains it and ends the thread (Main's quit, a deploy's restart).
## Preloaded where used (no class_name).

static var _mutex := Mutex.new()
static var _semaphore := Semaphore.new()
static var _queue: Array[Dictionary] = []
static var _thread: Thread = null
## Jobs queued and not yet done (flush waits on it).
static var _pending := 0
## Lines written by the thread, for tests.
static var lines_written := 0


## Appends [param line] to [param path] on the writer thread; first, a file
## of [param rotate_at] bytes or more (0: never) becomes <path>.1.
static func append(path: String, line: String, rotate_at := 0) -> void:
	_push({"op": "append", "path": path, "line": line, "rotate_at": rotate_at})


## Runs [param job] on the writer thread, in order with the lines: a static
## function's Callable that touches files only (Transcript.prune, bound).
static func run(job: Callable) -> void:
	_push({"op": "run", "job": job})


static func _push(job: Dictionary) -> void:
	_mutex.lock()
	_queue.append(job)
	_pending += 1
	_mutex.unlock()
	if _thread == null:
		_thread = Thread.new()
		_thread.start(_run, Thread.PRIORITY_LOW)
	_semaphore.post()


## Waits till every queued job is done.
static func flush() -> void:
	if _thread == null:
		return
	while true:
		_mutex.lock()
		var left := _pending
		_mutex.unlock()
		if left == 0:
			return
		OS.delay_usec(200)


## Drains the queue and ends the thread; the next job starts a new one.
static func stop() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_queue.append({"op": "stop"})
	_mutex.unlock()
	_semaphore.post()
	_thread.wait_to_finish()
	_thread = null


static func _run() -> void:
	while true:
		_semaphore.wait()
		_mutex.lock()
		var job: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_mutex.unlock()
		if job.is_empty():
			continue
		match str(job["op"]):
			"stop":
				return
			"append":
				_append(str(job["path"]), str(job["line"]), int(job["rotate_at"]))
			"run":
				(job["job"] as Callable).call()
		_mutex.lock()
		_pending -= 1
		_mutex.unlock()


static func _append(path: String, line: String, rotate_at: int) -> void:
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
			else FileAccess.open(path, FileAccess.WRITE)
	if file != null and rotate_at > 0 and file.get_length() >= rotate_at:
		file.close()
		var old := path + ".1"
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
		if DirAccess.rename_absolute(path, old) != OK:
			printerr("[log] cannot rotate %s" % path)
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("[log] cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.seek_end()
	file.store_line(line)
	file.close()
	_mutex.lock()
	lines_written += 1
	_mutex.unlock()

