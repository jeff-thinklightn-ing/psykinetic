#!/usr/bin/env bash
# tools/remote_shot_clash.sh (828 amended (3)): which of a runner clone's
# untracked files a checkout of the run's commit would overwrite, and which of
# those the run may remove (generated kinds) or must stop on. No laptop needed.
set -u
cd "$(dirname "$0")/.."
. tools/remote_shot_clash.sh
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = "$2" ]; then echo "  PASS  $3"; else echo "  FAIL  $3: got [$1], wanted [$2]"; failed=$((failed + 1)); fi
}
printf '%s\n' tests/tour/tours/fish_click.gd tests/tour/tours/fish_click.gd.uid art/a.png art/a.png.import levels/wilds.json README.md > "$tmp/tracked"
# Untracked on the laptop: maps' 11-12 case, an image's import, one the commit doesn't track, and a real file.
printf '%s\n' tests/tour/tours/fish_click.gd.uid art/a.png.import art/b.png.import levels/wilds.json > "$tmp/untracked"
got="$(clashes "$tmp/tracked" "$tmp/untracked" | tr '\n' ';')"
check "$got" "remove art/a.png.import;stop levels/wilds.json;remove tests/tour/tours/fish_click.gd.uid;" \
	"a generated file the commit tracks is removed, any other it tracks stops the run, one it doesn't track is left alone"
printf '%s\n' tests/tour/tours/fish_click.gd.uid > "$tmp/untracked"
got="$(clashes "$tmp/tracked" "$tmp/untracked" | tr '\n' ';')"
check "$got" "remove tests/tour/tours/fish_click.gd.uid;" "maps' case alone: the .uid removed, nothing to stop on"
: > "$tmp/untracked"
got="$(clashes "$tmp/tracked" "$tmp/untracked")"
check "$got" "" "nothing untracked: nothing done"
printf '%s\n' notes.txt art/b.png.import > "$tmp/untracked"
got="$(clashes "$tmp/tracked" "$tmp/untracked")"
check "$got" "" "untracked files the commit doesn't track: left alone (the checkout never touches them)"
echo
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
