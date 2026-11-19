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
cp "$work/sim/world.gd" "$tmp/world.gd.good"
# A take adds <code> as a function's body at the end of main.gd (or sim/companion.gd).
add() { printf '\n\nfunc _print_names_row() -> void:\n%s\n' "$2" >>"$work/$1"; }
fails_with() { [ "$1" = 1 ] && grep -q "$2" "$tmp/out.txt"; echo $?; }
reset() { cp "$tmp/main.gd.good" "$work/main.gd"; cp "$tmp/companion.gd.good" "$work/sim/companion.gd"; cp "$tmp/world.gd.good" "$work/sim/world.gd"; }

echo "== the server's code as it stands =="
PN; check $? "no print names a companion or carries a player id; the player-name lines within their budget"
PN --counts; check $(diff <(grep -v '^#' "$work/tools/print_names_budget.txt" | sed 's/ *#.*//' | tr -d '\r') <(tr -d '\r' <"$tmp/out.txt") >/dev/null; echo $?) "--counts prints the budget as it stands"

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

echo "== World._log's lines: printed through the mask (279 amended (4)) =="
add sim/world.gd $'\t_log("push: %s -> %s blocked" % [mover.name, body.name])'
PN; check $? "an entity's node name in a World._log line passes (World.masked puts her as her tag)"
reset
add main.gd $'\tWorld._log("guard: %s takes it" % target.name)'
PN; check $? "and in a World._log line from main.gd"
reset
add sim/world.gd $'\t_log("named: %s took it" % player_id)'
PN; check $(fails_with $? "whole player id") "a whole player id in a World._log line still fails"
reset
add sim/companion.gd $'\t_log({"kind": "voice", "companion": _name_of(self)})'
PN; check $? "her own _log in sim/companion.gd (her mind log, never the journal) is not read"
reset
python - "$work/sim/world.gd" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
a = 'print("[tick %d] %s" % [tick, masked(message)])'
assert s.count(a) == 1
open(p, "w", encoding="utf-8", newline="").write(s.replace(a, 'print("[tick %d] %s" % [tick, message])'))
EOF
PN; check $(fails_with $? "World._log prints its message only through masked") "World._log printing its message unmasked fails"
reset
add main.gd $'\tprint("[fight] %s" % World.last_log)'
PN; check $(fails_with $? "World._log prints its message only through masked") "a second printer of the message (last_log) fails"
reset

echo "== a companion or a player id handed to a printer (284 amended (2)'s leftover) =="
# A take adds a printer of main.gd's own and a caller handing it <arg>.
relay() { printf '\n\nfunc _relay_row(by: String, what := "") -> void:\n\tprint("[row] %%s: %%s" %% [%s, what])\n\n\nfunc _relay_caller() -> void:\n\t_relay_row(%s, "x")\n' "${2:-by}" "$1" >>"$work/main.gd"; }
add main.gd $'\tWorld.stockpile.deposit("umbrage", "gold", 2, "folk:%s" % id, "a sale")'
PN; check $(fails_with $? "companion_arg lines, over") "her folk id handed to stockpile.deposit (its print shows by raw) is over main.gd's companion_arg line"
reset
relay '"companion:%s" % pet_id'
PN; check $(fails_with $? "companion_arg lines, over") "her id handed to a printer of main.gd's own: over its companion_arg line"
grep -q "main.gd: 1 relay_print lines, over its line of 0" "$tmp/out.txt"; check $? "and the printer that shows it raw is over main.gd's relay_print line"
reset
relay 'str(who["name"])'
PN; check $(fails_with $? "companion_arg lines, over") "a card's name (who[\"name\"]) handed the same way: over"
reset
relay 'Companion.tag(pet_id)'
PN; check $? "her id inside Companion.tag passes"
reset
relay '"companion:%s" % pet_id' '"#" if by != "" else "someone"'
PN; check $? "a printer that only tests the parameter (by != \"\") does not show it: passes"
reset
relay '"sale:%s" % player_id'
PN; check $(fails_with $? "id_arg lines, over") "a whole player id handed to a printer is over main.gd's id_arg line"
reset
relay 'str(_players.get(_peer_of(player_id)))'
PN; check $? "a player id only looked up inside a call (no id handed on) passes"
reset
relay 'str(_peer_ids.get(peer, ""))'
PN; check $(fails_with $? "id_arg lines, over") "the peer-to-id table's id handed on is over"
reset
cp "$work/sim/stockpile.gd" "$tmp/stockpile.gd.good"
python - "$work/sim/stockpile.gd" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
a = '[by if by != "" else "someone", amount,'
b = 'what, place, from if from != "" else "nowhere said", now()])'
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, '[Companion.tag(by) if by != "" else "someone", amount,')
s = s.replace(b, 'what, place, World.masked(from) if from != "" else "nowhere said", now()])')
open(p, "w", encoding="utf-8", newline="").write(s)
EOF
PN; check $(fails_with $? "sim/stockpile.gd: 0 relay_print lines, under its line of 1") "stockpile.deposit's print through tags: under stockpile.gd's relay_print line, lower it in the same commit"
grep -q "sim/economy.gd: [0-9]* companion_arg lines, under its line" "$tmp/out.txt"; check $? "and economy.gd's companion_arg count falls with it (the handed sites into deposit)"
cp "$tmp/stockpile.gd.good" "$work/sim/stockpile.gd"
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
