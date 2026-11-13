#!/usr/bin/env bash
# Each font has its imported .fontdata before the landing's Godot parts start (the coordinator's
# row, 11-13: perf-sha's landing at 05:00 failed server_boot_test after the import before it
# segfaulted on the fonts and left their .fontdata unmade; the export then logged "Cannot open
# file ...fontdata" errors). A font's .import file names its .fontdata (path="res://.godot/
# imported/...fontdata"); one missing gets one more import, never a loop, and if it is still
# missing the part fails, naming it.
#   bash tools/fonts_imported.sh [project root, default .]
# Godot is $GODOT_PATH (its _console.exe beside it on Windows), or `godot` on PATH. tests/land.sh
# runs it as its font_import part under the take it already holds.
set -u
. "$(dirname "$0")/../tests/godot_log.sh"  # Its log in build/logs (decision 664).
root="${1:-.}"
GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*.exe)
		console="${GODOT%.exe}_console.exe"
		if [ -f "$console" ]; then GODOT="$console"; fi
		;;
esac

# The fonts (their res paths, without .import) whose .fontdata is missing or empty.
missing() {
	find "$root" -path "$root/.godot" -prune -o -type f \( -name '*.ttf.import' -o -name '*.otf.import' \
		-o -name '*.woff.import' -o -name '*.woff2.import' \) -print | sort | while IFS= read -r file; do
		data="$(tr -d '\r' <"$file" | sed -n 's#^path="res://\(.*\.fontdata\)"$#\1#p' | head -1)"
		[ -n "$data" ] || continue
		[ -s "$root/$data" ] || { font="${file#"$root"/}"; echo "${font%.import}"; }
	done
}

lost="$(missing)"
if [ -z "$lost" ]; then
	echo "PASS  every font has its .fontdata"
	exit 0
fi
printf '%s\n' "$lost" | while IFS= read -r font; do echo "re-imported: $font had no .fontdata"; done
(cd "$root" && timeout 900 "$GODOT" --log-file "$(godot_log font_import)" --headless --audio-driver Dummy --path . --import </dev/null >/dev/null 2>&1)
echo "the import exited $?"
still="$(missing)"
if [ -n "$still" ]; then
	printf '%s\n' "$still" | while IFS= read -r font; do echo "FAIL  $font: still no .fontdata after one re-import"; done
	exit 1
fi
echo "PASS  one re-import made each one's .fontdata"
