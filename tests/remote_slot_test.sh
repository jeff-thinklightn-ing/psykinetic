#!/usr/bin/env bash
# Saturn's slot taken over from a landing gone on this PC (878 amended (1)): tools/remote_tests.sh
# slot, its saturn side run here (PSYKINETIC_REMOTE_HERE: a scratch folder as its HOME), with a
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
# A running gate take for [tree], or none.
take_by() {
	rm -f "$gate/running/"*.json
	[ -n "${1:-}" ] || return 0
	now=$(date +%s)
	printf '{"tree": "%s", "kind": "suite_remote", "pid": null, "queued": %s, "started": %s, "ram_gb": 1.6, "gpu": false, "watched": false}\n' \
		"$1" "$now" "$now" >"$gate/running/$1-suite_remote-1.json"
}
ask() {
	out="$(timeout 60 bash tools/remote_tests.sh slot 2>&1)"; code=$?
	holder="$(cat "$home/land/.busy/holder" 2>/dev/null)"
}
cleared() { grep -c "" "$home/land/.slot_clears.log" 2>/dev/null || echo 0; }

echo "== another tree's slot, its landing gone here =="
held_by "physics 2b928b9f7" 300; lock_by; take_by
ask
check $([ $code = 0 ] && [ "$holder" = "slottest $sha" ]; echo $?) "no lock, no gate take, 5 min untouched, nothing running: taken over at once ($code: $out)"
check $(grep -q "taken over by slottest $sha from 'physics 2b928b9f7' (3[0-9][0-9] s untouched): its landing gone on the PC (no land-lock beat in 150 s and no gate take), nothing running under ~/land/physics" "$home/land/.slot_clears.log"; echo $?) \
	"logged in ~/land/.slot_clears.log: $(tail -1 "$home/land/.slot_clears.log" 2>/dev/null)"
before=$(cleared)

held_by "physics 2b928b9f7" 300; lock_by physics 200; take_by
ask
check $([ $code = 0 ] && [ "$holder" = "slottest $sha" ]; echo $?) "its lock held but unbeaten 200 s, no gate take: taken over ($code)"

echo "== waits: either sign of life is enough =="
held_by "physics 2b928b9f7" 300; lock_by physics 30; take_by
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ]; echo $?) "its lock beaten 30 s ago: waits, the slot kept ($code: $(printf '%s' "$out" | tail -1))"
held_by "physics 2b928b9f7" 300; lock_by physics 200; take_by physics
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ]; echo $?) "its lock unbeaten but a live gate take (between its take and its lock): waits ($code)"
held_by "physics 2b928b9f7" 300; lock_by; take_by physics
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ]; echo $?) "no lock, a live gate take: waits ($code)"

echo "== waits: saturn's own checks =="
held_by "physics 2b928b9f7" 60; lock_by; take_by
ask
check $([ $code = 1 ] && [ "$holder" = "physics 2b928b9f7" ]; echo $?) "touched 60 s ago (under 2 min): waits ($code)"
held_by "physics 2b928b9f7" 300; lock_by; take_by
( cd "$home/land/physics" && exec sleep 60 ) &
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
check $([ "$count" = 3 ]; echo $?) "three takeovers logged in all ($count)"

[ "$failed" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL ($failed failed)"
[ "$failed" = 0 ]
