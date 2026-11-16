#!/usr/bin/env bash
# tools/print_names.py (279 amended (3), 284 amended (2)): no server print names a companion, an
# entity that may be her by node name or label, or a whole player id, and the prints that still
# name a player stay within tools/print_names_budget.txt. On a scratch copy of the server's code
# (main.gd, sim/, net/) and the budget; never the checkout's own files. Godot-free.
set -u
cd "$(dirname "$0")/.."
here="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); sed "s/^/      | /" "$tmp/out.txt" 2>/dev/null | tail -8; fi; }
work="$tmp/root"
mkdir -p "$work/tools"
cp "$here/tools/print_names.py" "$here/tools/print_names_budget.txt" "$work/tools/"
cp "$here/main.gd" "$work/"
cp -r "$here/sim" "$here/net" "$work/"
PN() { PRINT_NAMES_ROOT="$work" python -B "$work/tools/print_names.py" "$@" >"$tmp/out.txt" 2>&1; }
cp "$work/main.gd" "$tmp/main.gd.good"
cp "$work/sim/companion.gd" "$tmp/companion.gd.good"
# A take adds <code> as a function's body at the end of main.gd (or sim/companion.gd).
add() { printf '\n\nfunc _print_names_row() -> void:\n%s\n' "$2" >>"$work/$1"; }
fails_with() { [ "$1" = 1 ] && grep -q "$2" "$tmp/out.txt"; echo $?; }
reset() { cp "$tmp/main.gd.good" "$work/main.gd"; cp "$tmp/companion.gd.good" "$work/sim/companion.gd"; }

echo "== the server's code as it stands =="
PN; check $? "no print names a companion or carries a player id; the player-name lines within their budget"
PN --counts; check $(diff <(grep -v '^#' "$work/tools/print_names_budget.txt" | tr -d '\r') <(tr -d '\r' <"$tmp/out.txt") >/dev/null; echo $?) "--counts prints the budget as it stands"

echo "== a companion's name, an entity's, an id: each named =="
add main.gd $'\tprint("[bond] %s rests" % record.companion["name"])'
PN; check $(fails_with $? "names a companion") "her card's name in a print fails"
reset
add main.gd $'\tprint("[guide] %s stops" % [\n\t\tCompanion._name_of(pet)])'
PN; check $(fails_with $? "names a companion") "her name on the print's second line fails (each call joined across its lines)"
reset
add main.gd $'\tprint("[free] round %s" % other.name)'
PN; check $(fails_with $? "names an entity by node name") "an entity that may be her by node name fails"
reset
add main.gd $'\tprint("[free] round %s" % [Companion.log_name(other)])'
PN; check $? "the same through Companion.log_name passes"
reset
add main.gd $'\tpush_warning("cannot place %s" % body.label)'
PN; check $(fails_with $? "names an entity by node name") "a label in a push_warning fails"
reset
add sim/companion.gd $'\tprint("[mind] %s: a held line let go" % name)'
PN; check $(fails_with $? "names an entity by node name") "her own bare name in sim/companion.gd fails"
reset
add main.gd $'\tprint("[crypt] %s has been told %s" % [player_id, fact_id])'
PN; check $(fails_with $? "whole player id") "a whole player id fails"
reset
add main.gd $'\tprint("[crypt] a player %s has been told %s" % [Companion.tag(player_id), fact_id])'
PN; check $? "the id inside Companion.tag passes"
reset
add main.gd $'\tprint("[bond] %s: %d" % [pet_tag(record.player_id), Standing.score(record.companion, record.player_id)])'
PN; check $? "an id read by Standing.score (a number printed) passes"

echo "== not read: a test run's line, a comment, a line's own words =="
add main.gd $'\tprint("[test] a companion %s is at %s" % [Companion._name_of(pet), tile])'
PN; check $? "a [test] line passes (test runs only)"
reset
add main.gd $'\t# print("%s" % player_id)\n\tprint("the player_id and pet.name are words here (%s)" % [tile])'
PN; check $? "a print in a comment, and the words inside a line's text, are not read"
reset

echo "== the budget only falls =="
add main.gd $'\tprint("[zone] %s came" % record.name)'
PN; check $(fails_with $? "over its line") "a new line naming a player is over main.gd's line"
reset
python - "$work/main.gd" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
a = 'print("[zone] %s went from %s to %s" % [record.name, from_name, to_map])'
assert s.count(a) == 1
open(p, "w", encoding="utf-8", newline="").write(s.replace(a, 'print("[zone] a player went from %s to %s" % [from_name, to_map])'))
EOF
PN; check $(fails_with $? "under its line") "a line that names a player taken out: under main.gd's line, lower it in the same commit"
reset

[ "$failed" = 0 ] && echo "print_names_test: PASS" || echo "print_names_test: FAIL ($failed)"
[ "$failed" = 0 ]
