#!/usr/bin/env bash
# Saturn's slot taken over from a landing gone on this PC (878 amended (1)), refused at once to a
# live one, given back on a lost connection, and prepare's exit kept (878 amended (2)):
# tools/remote_tests.sh slot and prepare, its saturn side run here (PSYKINETIC_REMOTE_HERE: a scratch folder as its HOME), with a
# scratch land lock (PSYKINETIC_LAND_LOCK) and a scratch gate (HEAVY_JOBS_DIR). No ssh, no Godot.
# Each case writes a holder into the slot, then asks for it as tree "slottest".
set -u
cd "$(dirname "$0")/.." || exit 1
tmp="$(mktemp -d -t remote_slot.XXXXXX)"
sleeper=""
trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$tmp"' EXIT
home="$tmp/saturn"
lock="$tmp/land.lock"
gate="$tmp/gate"
mkdir -p "$home/land/physics" "$home/land/slottest" "$gate/running" "$gate/queue"
export PSYKINETIC_REMOTE_HERE="$home" PSYKINETIC_LAND_LOCK="$lock" HEAVY_JOBS_DIR="$gate"
export PSYKINETIC_TREE=slottest PSYKINETIC_REMOTE_SLOT_WAIT=3
sha="$(git rev-parse HEAD)"
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi; }

# The slot held by [holder line], last touched [seconds] ago.
held_by() {
	rm -rf "$home/land/.busy"
	mkdir -p "$home/land/.busy"
	echo "$1" >"$home/land/.busy/holder"
	touch -d "@$(( $(date +%s) - $2 ))" "$home/land/.busy"
}
# The land lock held by [tree], last beaten [seconds] ago; none with no tree.
lock_by() {
	rm -rf "$lock"
	[ -n "${1:-}" ] || return 0
	mkdir -p "$lock"
	echo "$1" >"$lock/owner"
	echo "a landing" >"$lock/what"
	echo $(( $(date +%s) - $2 )) >"$lock/taken"
	echo $(( $(date +%s) - $2 )) >"$lock/since"
}
# A running gate take for [tree] of [kind] (suite_remote), waiting on the land lock with
# [lock_wait] (878 amended (2)), or none.
take_by() {
	rm -f "$gate/running/"*.json
	[ -n "${1:-}" ] || return 0
	now=$(date +%s)
	kind="${2:-suite_remote}"
	extra=""
	[ -n "${3:-}" ] && extra=', "lock_wait": true'
	printf '{"tree": "%s", "kind": "%s", "pid": null, "queued": %s, "started": %s, "ram_gb": 1.6, "gpu": false, "watched": false%s}\n' \
		"$1" "$kind" "$now" "$now" "$extra" >"$gate/running/$1-$kind-1.json"
}
ask() {
	# 300 s, not 60 (878 amended (3)): the slot's leftover check walks /proc for each tree, milliseconds
	# on saturn and 17 s a walk on this PC under load (705 msys processes, 11-16); 60 s cut a waiting
	# row short (exit 124) on main.
	out="$(timeout 300 bash tools/remote_tests.sh slot 2>&1)"; code=$?
	holder="$(cat "$home/land/.busy/holder" 2>/dev/null)"
}
cleared() { grep -c "" "$home/land/.slot_clears.log" 2>/dev/null || echo 0; }

echo "== another tree's slot, its landing gone here =="
held_by "physics 2b928b9f7" 300; lock_by; take_by
ask
check $([ $code = 0 ] && [ "$holder" = "slottest $sha" ]; echo $?) "no lock, no gate take, 5 min untouched, nothing running: taken over at once ($code: $out)"
check $(grep -q "taken over by slottest $sha from 'physics 2b928b9f7' (3[0-9][0-9] s untouched): its landing gone on the PC (no land-lock beat in 150 s and no landing's suite_remote take), nothing running under ~/land/physics" "$home/land/.slot_clears.log"; echo $?) \
	"logged in ~/land/.slot_clears.log: $(tail -1 "$home/land/.slot_clears.log" 2>/dev/null)"
before=$(cleared)

held_by "physics 2b928b9f7" 300; lock_by physics 200; take_by
ask
check $([ $code = 0 ] && [ "$holder" = "slottest $sha" ]; echo $?) "its lock held but unbeaten 200 s, no gate take: taken over ($code)"

echo "== refused at once: either sign of life is enough (878 amended (2)) =="
refused() { printf '%s' "$out" | grep -q "saturn's slot is held by 'physics 2b928b9f7' ([0-9]* s), a landing live on the PC (its land-lock beat or its suite_remote take): refused at once; requeue (878 amended (2))"; }
held_by "physics 2b928b9f7" 300; lock_by physics 30; take_by
t0=$(date +%s); ask; took=$(( $(date +%s) - t0 ))
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ] && refused && [ $took -lt 3 ]; echo $?) "its lock beaten 30 s ago: refused at once, named, the slot kept ($code, ${took}s: $(printf '%s' "$out" | tail -1))"
held_by "physics 2b928b9f7" 300; lock_by physics 200; take_by physics
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ] && refused; echo $?) "its lock unbeaten but its suite_remote take running (between its take and its lock): refused at once ($code)"
held_by "physics 2b928b9f7" 300; lock_by; take_by physics
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ] && refused; echo $?) "no lock, its suite_remote take running: refused at once ($code)"

echo "== no sign of life: a scene's take, or a take still waiting on the lock (878 amended (2)) =="
held_by "physics 2b928b9f7" 300; lock_by; take_by physics scene
ask
check $([ $code = 0 ] && [ "$holder" = "slottest $sha" ]; echo $?) "its tree holds only a scene take (ui's load_check, 11-14): taken over ($code: $(printf '%s' "$out" | tail -1))"
held_by "physics 2b928b9f7" 300; lock_by; take_by physics suite_remote wait
ask
check $([ $code = 0 ] && [ "$holder" = "slottest $sha" ]; echo $?) "its tree's suite_remote take waits on the land lock (a requeue after the dead landing): taken over ($code)"

echo "== waits: saturn's own checks =="
held_by "physics 2b928b9f7" 60; lock_by; take_by
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ]; echo $?) "touched 60 s ago (under 2 min): waits ($code)"
held_by "physics 2b928b9f7" 300; lock_by; take_by
( cd "$home/land/physics" && exec sleep 600 ) &  # Outlives ask's 300 s; killed below.
sleeper=$!
until readlink "/proc/$sleeper/cwd" 2>/dev/null | grep -q "land/physics"; do :; done
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ]; echo $?) "a process running under ~/land/physics: waits, and it is not stopped ($code)"
check $(kill -0 "$sleeper" 2>/dev/null; echo $?) "that process still alive"
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""

echo "== this tree's own earlier take =="
held_by "slottest 0123abcd" 300; lock_by slottest 10; take_by slottest
ask
check $([ $code = 0 ] && [ "$holder" = "slottest $sha" ]; echo $?) "its own earlier sha, this take holding the land lock: taken over ($code: $out)"
check $(tail -1 "$home/land/.slot_clears.log" | grep -q "from 'slottest 0123abcd' .*(this tree's earlier take; this take holds the land lock)"; echo $?) "logged as such"
held_by "slottest 0123abcd" 300; lock_by builder 10; take_by slottest
ask
check $([ $code = 1 ] && [ "$holder" = "slottest 0123abcd" ]; echo $?) "its own earlier sha, the lock another tree's: waits ($code)"

echo "== nothing said, nothing taken over =="
held_by "physics 2b928b9f7" 300; lock_by physics 200; take_by
echo "not a time" >"$lock/since"
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ]; echo $?) "the lock unreadable: no live list sent, waits ($code)"
lock_by; take_by
count=$(cleared)
check $([ "$count" = 5 ]; echo $?) "five takeovers logged in all ($count)"

echo "== prepare through a real command line, as ssh hands it over (878 amended (2)) =="
# A small repo of its own (remote_tests.sh and the gate beside it) and a saturn with a clone of it
# and a stand-in Godot: the import fails when import_fails is there, else sleeps FAKE_IMPORT_SLEEP.
mini="$tmp/mini"
home2="$tmp/saturn2"
mkdir -p "$mini/tools" "$home2/land" "$home2/godot"
cp tools/remote_tests.sh tools/heavy_job.py "$mini/tools/"
git -C "$mini" init -q
git -C "$mini" add tools
git -C "$mini" -c user.name=slottest -c user.email=slottest@example.invalid commit -q -m mini
minisha="$(git -C "$mini" rev-parse HEAD)"
git clone -q "$mini" "$home2/psykinetic"
printf '#!/bin/sh\n[ -f "$HOME/import_fails" ] && { echo "SCRIPT ERROR: a stand-in failure"; exit 1; }\nsleep "${FAKE_IMPORT_SLEEP:-0}"\nexit 0\n' >"$home2/godot/Godot_v4.7.2-stable_linux.x86_64"
chmod +x "$home2/godot/Godot_v4.7.2-stable_linux.x86_64"
held2() {
	rm -rf "$home2/land/.busy"
	[ -n "${1:-}" ] || return 0
	mkdir -p "$home2/land/.busy"
	echo "$1" >"$home2/land/.busy/holder"
	touch -d "@$(( $(date +%s) - $2 ))" "$home2/land/.busy"
}
prep() {
	out="$(cd "$mini" && PSYKINETIC_REMOTE_HERE="$home2" timeout 120 bash tools/remote_tests.sh prepare 2>&1)"; code=$?
	holder="$(cat "$home2/land/.busy/holder" 2>/dev/null)"
}
held2; lock_by slottest 5; take_by slottest
prep
check $([ $code = 0 ] && [ "$holder" = "slottest $minisha" ] && printf '%s' "$out" | grep -q "checked out and imported"; echo $?) "a free slot: prepared, exit 0 ($code: $(printf '%s' "$out" | grep '^remote' | tail -1))"
touch "$home2/import_fails"
prep
check $([ $code != 0 ] && printf '%s' "$out" | grep -q "remote: the import failed"; echo $?) "a failed import: exit non-zero ($code: $(printf '%s' "$out" | grep '^remote' | tail -1))"
rm -f "$home2/import_fails"
held2 "physics 2b928b9f7" 300; lock_by slottest 5; take_by physics
prep
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ] && printf '%s' "$out" | grep -q "refused at once; requeue"; echo $?) "a refused slot: exit 1, the holder named and kept ($code: $(printf '%s' "$out" | grep '^remote' | tail -1))"
held2 "slottest 0123abcd" 300; lock_by slottest 5; take_by slottest
prep
check $([ $code = 0 ] && [ "$holder" = "slottest $minisha" ] && tail -1 "$home2/land/.slot_clears.log" 2>/dev/null | grep -q "this tree's earlier take; this take holds the land lock"; echo $?) \
	"mine=1 arrives through the line: this tree's earlier sha taken over ($code: $(tail -1 "$home2/land/.slot_clears.log" 2>/dev/null))"
lock_by; take_by

echo "== the connection lost: the slot given back, only its own (878 amended (2)) =="
bash tools/remote_tests.sh script >"$tmp/saturn.sh"
# stderr closed: the watcher's line can't be written, as when the PC's side is gone.
held2
( cd "$mini" && HOME="$home2" FAKE_IMPORT_SLEEP=16 exec bash "$tmp/saturn.sh" prepare slottest "$minisha" 12 "live=,;mine=1" >/dev/null 2>&- ) &
lost=$!
sleep 4
during="$(cat "$home2/land/.busy/holder" 2>/dev/null)"
sleep 10
after="$(cat "$home2/land/.busy/holder" 2>/dev/null)"
check $([ "$during" = "slottest $minisha" ] && [ -z "$after" ] && [ ! -d "$home2/land/.busy" ]; echo $?) "its own holder given back within the watcher's ten seconds (held '$during', then '$after')"
wait "$lost" 2>/dev/null
held2
( cd "$mini" && HOME="$home2" FAKE_IMPORT_SLEEP=16 exec bash "$tmp/saturn.sh" prepare slottest "$minisha" 12 "live=,;mine=1" >/dev/null 2>&- ) &
lost=$!
sleep 4
echo "physics 2b928b9f7" >"$home2/land/.busy/holder"
sleep 10
after="$(cat "$home2/land/.busy/holder" 2>/dev/null)"
check $([ "$after" = "physics 2b928b9f7" ]; echo $?) "the holder another landing's by then: left alone ('$after')"
wait "$lost" 2>/dev/null
held2

echo "== a fresh checkout's scene times (90 amended (2)) =="
mine_file="$home/land/slottest/.godot/test_durations.txt"
rm -rf "$home/land/slottest/.godot" "$home/land/physics/.godot"
out="$(timeout 60 bash tools/remote_tests.sh seed 2>/dev/null)"  # stdout: what land.sh greps (here ps -o errs)
check $([ "$out" = "durations: none (each scene's cap the 300 s floor)" ] && [ ! -e "$mine_file" ]; echo $?) "none anywhere: no file, said ($out)"
mkdir -p "$home/land/physics/.godot" "$home/land/builder/.godot"
printf '262 tests/view_test.tscn\n' >"$home/land/builder/.godot/test_durations.txt"
touch -d "@$(( $(date +%s) - 600 ))" "$home/land/builder/.godot/test_durations.txt"
printf '271 tests/view_test.tscn\n' >"$home/land/physics/.godot/test_durations.txt"
out="$(timeout 60 bash tools/remote_tests.sh seed 2>/dev/null)"  # stdout: what land.sh greps (here ps -o errs)
check $([ "$out" = "durations: seeded from physics" ] && [ "$(cat "$mine_file" 2>/dev/null)" = "271 tests/view_test.tscn" ]; echo $?) \
	"a fresh folder: the newest file copied in ($out: $(cat "$mine_file" 2>/dev/null))"
check $([ "$(cat "$home/land/builder/.godot/test_durations.txt")" = "262 tests/view_test.tscn" ] \
	&& [ "$(cat "$home/land/physics/.godot/test_durations.txt")" = "271 tests/view_test.tscn" ]; echo $?) "the others untouched"
printf '140 tests/view_test.tscn\n' >"$mine_file"
touch -d "@$(( $(date +%s) - 3600 ))" "$mine_file"
out="$(timeout 60 bash tools/remote_tests.sh seed 2>/dev/null)"  # stdout: what land.sh greps (here ps -o errs)
check $([ "$out" = "durations: own" ] && [ "$(cat "$mine_file")" = "140 tests/view_test.tscn" ]; echo $?) "its own, though older: left alone ($out)"

[ "$failed" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL ($failed failed)"
[ "$failed" = 0 ]
