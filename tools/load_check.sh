#!/usr/bin/env bash
# Load a take's changed scripts for real before it queues (278 amended (7), the gate's
# load_check kind, 394 amended (46); enemy-ai's probe, 11-12):
#   bash tools/load_check.sh               the .gd files changed against origin/main
#                                          (committed, staged, unstaged and new ones)
#   bash tools/load_check.sh a.gd b.gd     these
# One headless Godot, through the gate as load_check (beside anything but a bench, one at
# a time, seconds long), loads each with the project's autoloads in (tools/load_check.gd)
# and prints "LOAD ok|FAIL <file>", the engine's SCRIPT ERROR lines, and one
# "LOAD_CHECK: PASS|FAIL" line; exit 0, 1 on a failure, 2 when it could not check.
#
# What it gives that `--check-only --script` doesn't: a verdict a file at a time. Check-only
# runs without the autoloads, so it fails sound scripts too: "Identifier not found: Net" for
# any autoload use, and false Parse Errors such as main's tests/monster_test.gd's "Invalid
# index type "Draugr"" (11-13: a copy of it loads here, and fails check-only). Its exit and
# its lines can't tell a sound file from a broken one without a diff against main's own
# output, and trees skipped it as noise (npc) or read a real error as the known false one
# (enemy-ai). The real errors it then let through, each of which waited its turn in the gate
# and idled a test's whole limit: a lambda's var clashing with its function's (terrain's
# view_land_test, 11-10), a := whose type can't be inferred from an untyped call (npc,
# companions, enemy-ai, 11-12), a script failing through its super class's; all three fail
# here, named. Run it after an import whenever a pull brought a new class_name (the class
# cache is per checkout). tests/land.sh --checks names it.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
case "${1:-}" in -h|--help) sed -n '2,23p' "$0"; exit 0 ;; esac
tree="${PSYKINETIC_TREE:-$(basename "$PWD")}"
if [ $# -gt 0 ]; then
	files="$(printf '%s\n' "$@")"
else
	files="$({ git diff --name-only origin/main...HEAD -- '*.gd'; git diff --name-only HEAD -- '*.gd'
		git ls-files --others --exclude-standard -- '*.gd'; } | sort -u)"
fi
args=()
for file in $files; do
	file="${file#./}"
	file="${file#res://}"
	case "$file" in *.gd) ;; *) echo "load_check: $file: not a .gd script"; exit 2 ;; esac
	[ -f "$file" ] || continue  # Deleted in the take.
	args+=("res://$file")
done
if [ ${#args[@]} -eq 0 ]; then
	echo "LOAD_CHECK: PASS (no changed scripts)"; exit 0
fi
if [ ! -f .godot/global_script_class_cache.cfg ]; then
	echo "load_check: this checkout is not imported (.godot has no class cache): import it first"; exit 2
fi
GODOT="${GODOT_PATH:-godot}"
# The gate starts the command from python: a bare "timeout" there is Windows' own.
TIMEOUT="$(command -v /usr/bin/timeout || command -v timeout)"
# Its own user data: nothing it loads reads or writes the shared overlay (CLAUDE.md).
data="$(mktemp -d -t load_check.XXXXXX)"
log="$data/godot.log"
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
APPDATA="$(winpath "$data")" XDG_DATA_HOME="$data" sh tools/heavy_job.sh run "$tree" load_check -- \
	"$TIMEOUT" 240 "$GODOT" --headless --audio-driver Dummy --path . --log-file "$(winpath "$log")" \
	--script res://tools/load_check.gd -- "${args[@]}" </dev/null >/dev/null 2>&1
status=$?
grep -aE "^LOAD |^SCRIPT ERROR|^ERROR: Failed to load script|^   at: " "$log" 2>/dev/null | tr -d '\r'
verdict="$(grep -a "^LOAD_CHECK: " "$log" 2>/dev/null | tr -d '\r' | tail -1)"
rm -rf "$data"
if [ -z "$verdict" ]; then
	echo "LOAD_CHECK: FAIL (Godot gave no verdict, exit $status: $([ $status = 124 ] && echo "timed out after 240 s" || echo "see the lines above"))"
	exit 2
fi
echo "$verdict"
[ $status = 0 ] && case "$verdict" in "LOAD_CHECK: PASS"*) exit 0 ;; esac
exit 1
