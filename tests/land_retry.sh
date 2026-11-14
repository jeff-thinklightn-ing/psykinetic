# Sourced by tests/land.sh (278 amended (8), the coordinator's approval, 2026-11-13): a landing's
# tool parts run through tool_part, the Godot parts through land.sh's own part(), never this.
#
# A tool part that failed on the temp folder (its log says a file or git object could not be
# written: "Permission denied", "unable to write file", "Access is denied") and printed no failed
# check of its own ("  FAIL  ..." at a line's start) runs once more, LAND_RETRY_WAIT seconds later;
# the rerun's exit is the part's. (48)'s landing on 11-13 lost its turn so: changelog_resolve_test
# and voice_inventory_test both died in one second writing .git/objects in their %TEMP% scratch
# repos, after every Godot part had passed, and both passed run alone at once.
#
# A retry prints "retried: <name> (temp folder: <the line>)", keeps the first log as
# <name>.first.log beside the rerun's (keep_failure copies both), and leaves <name>.retried in
# $LOGS for the result line (land_retried). Once only: a second failure fails the landing.

LAND_RETRY_WAIT="${LAND_RETRY_WAIT:-5}"
LAND_TEMP_FAULT='Permission denied|unable to write file|Access is denied'

tool_part() {
	name="$1"
	shift
	t0=$(date +%s)
	"$@" >"$LOGS/$name.log" 2>&1
	code=$?
	if [ "$code" -ne 0 ] && ! grep -qE '^ *FAIL( |$)' "$LOGS/$name.log" && grep -qE "$LAND_TEMP_FAULT" "$LOGS/$name.log"; then
		why="$(grep -m1 -E "$LAND_TEMP_FAULT" "$LOGS/$name.log" | tr -d '\r' | cut -c1-160)"
		mv "$LOGS/$name.log" "$LOGS/$name.first.log"
		echo "retried: $name (temp folder: $why)" | tee "$LOGS/$name.retried"
		sleep "$LAND_RETRY_WAIT"
		"$@" >"$LOGS/$name.log" 2>&1
		code=$?
	fi
	took=$(( $(date +%s) - t0 ))
	echo "$code $took" >"$LOGS/$name.status"
	echo "$([ "$code" -eq 0 ] && echo PASS || echo FAIL)  $name ${took}s"
}

# The result line's note: "; retried: a b (temp folder)" when any tool part was retried, else "".
land_retried() {
	set -- $(for each in "$LOGS"/*.retried; do [ -f "$each" ] && basename "$each" .retried; done)
	[ $# -gt 0 ] && echo "; retried: $* (temp folder)"
	return 0
}
