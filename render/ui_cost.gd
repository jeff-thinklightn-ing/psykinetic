class_name UiCost
extends RefCounted
## What the interface's per-frame work costs (ui's measure for perf): each
## panel adds the microseconds its frame work took under a name (add), Main
## counts the frames, and report() says the average per frame and the share
## of frames each ran on. Printed at a test's exit with --test-ui-cost; the
## tally itself is a few calls a frame.

static var spent: Dictionary = {}
static var runs: Dictionary = {}
static var frames := 0


static func add(name: String, usec: int) -> void:
	spent[name] = int(spent.get(name, 0)) + usec
	runs[name] = int(runs.get(name, 0)) + 1


static func frame() -> void:
	frames += 1


## "[ui cost] 1200 frames: hud 0.031 ms/frame (every frame), pack 0.210 ms/frame (every frame) ..."
static func report() -> String:
	if frames == 0:
		return "[ui cost] no frames"
	var parts: Array[String] = []
	var names: Array = spent.keys()
	names.sort()
	var total := 0
	for name: String in names:
		total += int(spent[name])
		var share := float(runs[name]) / frames
		parts.append("%s %.3f ms/frame (%s)" % [name, int(spent[name]) / 1000.0 / frames,
			"every frame" if share > 0.95 else "%d%% of frames" % roundi(share * 100.0)])
	return "[ui cost] %d frames: %s; all %.3f ms/frame" % [frames, ", ".join(parts), total / 1000.0 / frames]
