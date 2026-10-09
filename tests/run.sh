#!/usr/bin/env bash
# Runs the headless sim tests, one scene after another.
# Exit code 0 = every assertion in every scene passed, 1 = any failed.
# Godot is taken from $GODOT_PATH, or `godot` on PATH.
set -u

GODOT="${GODOT_PATH:-godot}"

# The Windows GUI build detaches from the console (no output, no exit code);
# use the console build that ships next to it when there is one.
case "$GODOT" in
	*_console.exe) ;;
	*.exe)
		console="${GODOT%.exe}_console.exe"
		if [ -f "$console" ]; then GODOT="$console"; fi
		;;
esac

# A scene that has not finished in this many seconds (a parse error leaves
# Godot running, waiting) is killed and fails the run.
TIMEOUT="${TEST_TIMEOUT:-300}"

cd "$(dirname "$0")/.."
code=0
for scene in tests/push_test.tscn tests/respawn_test.tscn tests/companion_test.tscn tests/spawn_test.tscn tests/mirror_test.tscn tests/edge_test.tscn tests/controls_test.tscn tests/view_test.tscn tests/level_test.tscn; do
	echo "### $scene"
	# A script error aborts a test function without failing an assertion, so
	# treat any engine error as a failure too.
	timeout --kill-after=10 "$TIMEOUT" "$GODOT" --headless --path . --scene "$scene" </dev/null 2>&1 | tee /tmp/psykinetic-run.log
	status="${PIPESTATUS[0]:-0}"
	if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
		echo "FAIL  $scene did not finish within ${TIMEOUT}s (a parse error, or a hang): killed"
	fi
	[ "$status" -eq 0 ] || code=1
	grep -q "SCRIPT ERROR\|^ERROR:" /tmp/psykinetic-run.log && code=1
done
exit $code
