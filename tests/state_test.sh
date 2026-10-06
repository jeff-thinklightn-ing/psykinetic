#!/usr/bin/env sh
# Snapshot test: a host run pushes a crate and writes --state; a second run
# must load the crate where it was left; a corrupt file must start fresh.
# Exit code 0 = all assertions passed, 1 = any failed.
# Godot is taken from $GODOT_PATH, or `godot` on PATH.
set -u

GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe)
		console="${GODOT%.exe}_console.exe"
		if [ -f "$console" ]; then GODOT="$console"; fi
		;;
esac

cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
STATE="$DIR/world.json"

run_host() {
	name="$1"
	shift
	"$GODOT" --headless --path . --host --no-companions --port=17781 "--state=$STATE" "$@" </dev/null >"$DIR/$name.log" 2>"$DIR/$name.err"
}

failures=0
check() {
	if [ "$1" = "$2" ]; then
		echo "  PASS  $3"
	else
		echo "  FAIL  $3 (got $1, want $2)"
		failures=$((failures + 1))
	fi
}
count() { grep -cE "$1" "$2" 2>/dev/null || true; }

# 1. Fresh start: the host walks three tiles west, pushing Crate1 to (7, 2).
run_host first --test-move=-3,0 --test-exit-after=5
check "$(count 'no snapshot at' "$DIR/first.log")" 1 "first run finds no snapshot and starts fresh"
check "$(count 'tiles: .*Crate1=\(7, 2\)' "$DIR/first.log")" 1 "first run ends with Crate1 pushed to (7, 2)"
check "$([ -s "$STATE" ] && echo yes || echo no)" yes "snapshot file was written"
check "$(count '"version": 1' "$STATE")" 1 "snapshot carries version 1"
# Keys are sorted, so an entry runs from its "name" to its "type"; the tile
# is pretty-printed as "tile": [ then 7, then 2 on their own lines.
crate_tile=$(sed -n '/"name": "Crate1"/,/"type": "pushable"/p' "$STATE" | grep -A2 '"tile"' | grep -cE '^[[:space:]]*7,$' || true)
check "$crate_tile" 1 "snapshot has Crate1 at [7, 2]"
check "$(count '"script": "res://sim/player.gd"' "$STATE")" 0 "players are not among the entities"
check "$(count '"player_id": "dev-host"' "$STATE")" 1 "snapshot holds the dev host's player record"
check "$(count '"script": "res://sim/(monster|pushable).gd"' "$STATE")" 9 "snapshot holds the 9 level entities"

# 2. Restart: entities come from the snapshot, so Crate1 is still at (7, 2).
run_host second --test-exit-after=2
check "$(count '\[state\] loaded 9 entities and 1 player records' "$DIR/second.log")" 1 "second run loads 9 entities and 1 player record from the snapshot"
check "$(count '\[net\] Player \(dev-host\) joined as Player1 at \(8, 2\) \(back\)' "$DIR/second.log")" 1 "the host comes back where it left off, as Player1"
check "$(count 'tiles: .*Crate1=\(7, 2\)' "$DIR/second.log")" 1 "second run has Crate1 where the first left it"

# 3. Corrupt file: start fresh, and overwrite it with a good one on exit.
echo 'this is not json' >"$STATE"
run_host third --test-exit-after=2
check "$(count 'does not parse.*starting fresh' "$DIR/third.log")" 1 "a corrupt snapshot is logged and ignored"
check "$(count 'tiles: .*Crate1=\(8, 2\)' "$DIR/third.log")" 1 "and the room is generated fresh (Crate1 back at (8, 2))"
check "$(count 'tiles: .*Player1=\(11, 2\)' "$DIR/third.log")" 1 "with the host at a start tile"
check "$(count '"version": 1' "$STATE")" 1 "the corrupt file was replaced by a good snapshot on exit"
check "$(cat "$DIR"/*.err 2>/dev/null | wc -l | tr -d ' ')" 0 "no run printed errors"

echo
if [ "$failures" -gt 0 ]; then
	echo "RESULT: FAIL ($failures failed) (logs in $DIR)"
	exit 1
fi
echo "RESULT: PASS (logs in $DIR)"
exit 0
