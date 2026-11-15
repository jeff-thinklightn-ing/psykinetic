#!/usr/bin/env bash
# One name for a landing (883 amended, 2026-11-15): land.sh run under a PSYKINETIC_TREE that is
# not the name of the land lock taken from its own checkout stops at once, exit 7, holding
# nothing; the gate never queues a --no-queue-under-lock run from the checkout holding the lock,
# whatever the names (exit 6); the lock's minute beat starts in the run the gate granted, never
# in one refused or waiting; and status marks a landing's take queued from the checkout holding
# the lock ("self-waiting"), logged once for the daily summary. The ordinary landing (the gate
# take, then the lock, one name) goes through as before and beats from its first second.
# land.sh runs as a stand-in (LAND_TEST_STANDIN: no checks, no parts), on a scratch land lock
# (PSYKINETIC_LAND_LOCK) and a scratch gate (HEAVY_JOBS_DIR); never the real ones, never saturn.
set -u
cd "$(dirname "$0")/.."
here="$(pwd)"
# Never a real suite: a land.sh without the stand-in would run every part, outside the real
# gate (this test against main's land.sh did, 11-15 05:03-05:13). Refused before anything runs,
# and no Godot to start if a stand-in were ever skipped.
if ! grep -q "LAND_TEST_STANDIN" tests/land.sh; then
	echo "RESULT: FAIL (tests/land.sh has no LAND_TEST_STANDIN: not run, it would run the whole suite)"
	exit 1
fi
export GODOT_PATH="$(pwd)/no-godot-in-land_name_test"
tmp="$(mktemp -d)"
waiter=""
run=""
cleanup() {
	[ -n "$waiter" ] && kill "$waiter" 2>/dev/null
	[ -n "$run" ] && kill "$run" 2>/dev/null
	rm -rf "$tmp"
}
trap cleanup EXIT
export PSYKINETIC_LAND_LOCK="$tmp/land.lock" HEAVY_JOBS_DIR="$tmp/gate" HEAVY_JOB_TEST_FREE_GB=64 LAND_LOCAL=1
unset PSYKINETIC_TREE HEAVY_JOB_HELD HEAVY_JOB_KIND HEAVY_JOB_INSIDE LAND_RESULT
lock="$PSYKINETIC_LAND_LOCK"
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); sed "s/^/      | /" "$tmp/out.txt" 2>/dev/null; fi; }
L() { sh "$here/tools/land_lock.sh" "$@" >"$tmp/lock.txt" 2>&1; }
G() { python -B "$here/tools/heavy_job.py" "$@"; }
# land.sh as a stand-in for [1] seconds, under PSYKINETIC_TREE [2] ("" unset); its output in out.txt.
land() {
	if [ -n "$2" ]; then
		PSYKINETIC_TREE="$2" LAND_TEST_STANDIN="$1" bash tests/land.sh >"$tmp/out.txt" 2>&1
	else
		LAND_TEST_STANDIN="$1" bash tests/land.sh >"$tmp/out.txt" 2>&1
	fi
}
unbeaten() { echo 1 >"$lock/since"; }
beaten() { [ "$(cat "$lock/since" 2>/dev/null)" != 1 ]; }
none_queued() { G status 2>&1 | grep -q "^no heavy jobs"; }

echo "== the ordinary landing: the gate's take, then the lock, one name =="
G take lnt suite >/dev/null 2>&1
L take lnt "lnt's landing"; check $? "lnt takes the lock after its gate take"
unbeaten
land 3 lnt; code=$?
check $([ $code = 1 ] && grep -q "a tool test's stand-in" "$tmp/out.txt" && grep -q "inside this tree's take" "$tmp/out.txt"; echo $?) \
	"land.sh as lnt runs inside lnt's take, through the gate as before (exit $code)"
check $(beaten; echo $?) "it beat the lock in its first seconds (since $(cat "$lock/since"))"
check $(! grep -q "883 amended" "$tmp/out.txt"; echo $?) "no word of a name clash"
L release lnt; G release lnt suite >/dev/null 2>&1

echo "== PSYKINETIC_TREE unset: the lock's name adopted, as 883 has it =="
G take lnt-gather suite >/dev/null 2>&1
L take lnt-gather "lnt's side landing"
unbeaten
land 3 ""; code=$?
check $([ $code = 1 ] && grep -q "taken here by lnt-gather: run as lnt-gather" "$tmp/out.txt" && grep -q "a tool test's stand-in" "$tmp/out.txt"; echo $?) \
	"run as lnt-gather, inside its take (exit $code)"
check $(beaten; echo $?) "and beaten from its first seconds"

echo "== PSYKINETIC_TREE not the lock's name: exit 7 at once, holding nothing =="
unbeaten
start=$(date +%s)
land 3 lnt; code=$?
check $([ $code = 7 ]; echo $?) "exit 7 (got $code)"
check $(grep -q "LANDING TESTS: FAIL (the land lock was taken from this checkout as lnt-gather; land.sh runs as lnt (PSYKINETIC_TREE=lnt), and the gate take is lnt-gather suite: the gate take, the lock and PSYKINETIC_TREE are one name" "$tmp/out.txt"; echo $?) \
	"the line names the lock's name, the tree, PSYKINETIC_TREE and the take found"
check $([ $(( $(date +%s) - start )) -lt 30 ] && ! grep -q "through the heavy-job gate" "$tmp/out.txt"; echo $?) "the gate never asked"
check $(G holds lnt suite >/dev/null 2>&1; [ $? = 1 ]; echo $?) "no take made under lnt"
check $(! beaten; echo $?) "the lock not beaten"
check $([ "$(cat "$lock/owner")" = lnt-gather ]; echo $?) "the lock still lnt-gather's"
L release lnt-gather; G release lnt-gather suite >/dev/null 2>&1

echo "== the gate: no queue from the checkout holding the lock, whatever the names =="
L take lnt-gather "lnt's side landing"
G run lnt suite --no-queue-under-lock "$lock" -- true >"$tmp/out.txt" 2>&1; code=$?
check $([ $code = 6 ] && grep -q "the land lock was taken from this checkout" "$tmp/out.txt" && grep -q "one name, 883 amended" "$tmp/out.txt"; echo $?) \
	"a run as lnt, the lock lnt-gather's from here: exit 6 (got $code)"
check $(none_queued; echo $?) "nothing queued"
G run lnt-gather suite --no-queue-under-lock "$lock" -- true >"$tmp/out.txt" 2>&1; code=$?
check $([ $code = 6 ] && grep -q "this tree holds the land lock" "$tmp/out.txt"; echo $?) "the lock's own name with no take: exit 6 as 394 amended (31) has it (got $code)"
G take lnt-gather suite >/dev/null 2>&1
G run lnt-gather suite --no-queue-under-lock "$lock" -- true >"$tmp/out.txt" 2>&1; code=$?
check $([ $code = 0 ] && grep -q "inside this tree's take" "$tmp/out.txt"; echo $?) "with its take held: runs inside it (got $code)"
G release lnt-gather suite >/dev/null 2>&1
mine="$(cat "$lock/checkout")"
echo "$tmp/other" >"$lock/checkout"
G run lnt suite --no-queue-under-lock "$lock" -- true >"$tmp/out.txt" 2>&1; code=$?
check $([ $code = 0 ]; echo $?) "the lock taken from another checkout under another name: runs as before (got $code)"
echo "$mine" >"$lock/checkout"
L release lnt-gather

echo "== the beat starts only in the granted run =="
L take lnt "lnt's landing"
unbeaten
land 3 lnt; code=$?
check $([ $code = 6 ] && grep -q "lost the gate take while holding the land lock" "$tmp/out.txt"; echo $?) "no take, holding the lock: refused, exit 6 (got $code)"
check $(! beaten; echo $?) "the refused run never beat the lock (it did before 883 amended: the beater started before the gate)"
L release lnt

echo "== status: a landing's take queued from the checkout holding the lock =="
G take other bench >/dev/null 2>&1   # A bench running: a suite waits.
L take lnt-gather "lnt's side landing"
G take lnt suite >"$tmp/waiter.txt" 2>&1 &
waiter=$!
for _ in $(seq 1 20); do G status 2>&1 | grep -q "^queued lnt suite" && break; sleep 0.5; done
G status >"$tmp/out.txt" 2>&1
check $(grep -q "^self-waiting: lnt suite queued [0-9]* min from the checkout holding the land lock (lnt-gather, " "$tmp/out.txt"; echo $?) "status: self-waiting, named"
check $(grep -q "self_waiting" "$HEAVY_JOBS_DIR/heavy_jobs.log"; echo $?) "logged for the daily summary"
G summary >"$tmp/out.txt" 2>&1
check $(grep -q "self_waiting by tree: lnt 1" "$tmp/out.txt"; echo $?) "the daily summary counts it by tree"
L release lnt-gather
G status >"$tmp/out.txt" 2>&1
check $(! grep -q "^self-waiting" "$tmp/out.txt"; echo $?) "the lock released: no mark"
G take scene-tree scene >/dev/null 2>&1 &
scene=$!
L take scene-lock "a lock"
sleep 1
G status >"$tmp/out.txt" 2>&1
check $(! grep -q "^self-waiting: scene-tree" "$tmp/out.txt"; echo $?) "a scene queued from there is no landing: no mark"
kill "$scene" "$waiter" 2>/dev/null; waiter=""
L release scene-lock
G release other bench >/dev/null 2>&1

echo "== the gated run ends after its parts, its beat with it (883 amended (2)) =="
# The row's own stand-in, not a flag land.sh must know: a scratch folder outside any git
# repository (GIT_DIR names none) holding a copy of this checkout's tests/land.sh and the
# helpers it sources, and every part and tool part it starts as a stub that exits 0 at once; the
# beat's tools/land_lock.sh a stub writing its caller's pid (the beater's) to beater.pid. Run as
# the gate runs it (HEAVY_JOB_INSIDE, kind suite), so it goes from the beat through every part
# to the result line in seconds, starting no Godot whatever land.sh it is. Before the mend,
# land.sh's bare wait waited for the beater, and perf-lockname's landing held the lock 46
# minutes after its parts passed (11-15).
standin() {
	dir="$tmp/$1"
	rm -rf "$dir"
	mkdir -p "$dir/tests" "$dir/tools"
	cp "${LAND_NAME_TEST_LAND_SH:-$here/tests/land.sh}" "$dir/tests/land.sh"
	for each in tests/jobs.sh tests/land_retry.sh tools/land_stamp.sh tools/land_tested.sh; do cp "$here/$each" "$dir/$each"; done
	for each in $(grep -oE "(tests|tools)/[a-z_]+\.(sh|py)" "$dir/tests/land.sh" | sort -u); do
		case "$each" in
			*.py) [ -f "$dir/$each" ] || printf 'raise SystemExit(0)\n' >"$dir/$each" ;;
			*) [ -f "$dir/$each" ] || printf 'exit 0\n' >"$dir/$each" ;;
		esac
	done
	printf 'echo "$PPID" > beater.pid\n' >"$dir/tools/land_lock.sh"
}
# Runs the stand-in in [1] for at most [2] seconds; sets ended (1: it ended by itself) and took.
standin_run() {
	dir="$tmp/$1"
	rm -f "$tmp/standin_result" "$dir/beater.pid"
	( cd "$dir" && GIT_DIR="$tmp/no-git" HEAVY_JOB_INSIDE=1 HEAVY_JOB_KIND=suite PSYKINETIC_TEST_JOBS=4 \
		PSYKINETIC_TREE=lnt LAND_RESULT="$tmp/standin_result" exec bash tests/land.sh ) >"$tmp/out.txt" 2>&1 </dev/null &
	run=$!
	start=$(date +%s)
	while kill -0 "$run" 2>/dev/null && [ $(( $(date +%s) - start )) -lt "$2" ]; do sleep 1; done
	took=$(( $(date +%s) - start ))
	ended=1
	if kill -0 "$run" 2>/dev/null; then
		ended=0
		# Hung: its beater stopped, so the run it holds ends by itself.
		[ -f "$dir/beater.pid" ] && kill "$(cat "$dir/beater.pid")" 2>/dev/null
		for _ in $(seq 1 30); do kill -0 "$run" 2>/dev/null || break; sleep 1; done
		kill "$run" 2>/dev/null
	fi
	wait "$run" 2>/dev/null
	run=""
	sleep 2
}
beater_gone() { [ -f "$1/beater.pid" ] && ! kill -0 "$(cat "$1/beater.pid")" 2>/dev/null; }
standin standin
standin_run standin 60
check $([ "$ended" = 1 ]; echo $?) "land.sh ended by itself after its parts, in ${took} s (it waited on its own beater before the mend)"
check $(grep -q "^LANDING TESTS: PASS" "$tmp/out.txt" && grep -q "^LANDING TESTS: PASS" "$tmp/standin_result" 2>/dev/null; echo $?) "its PASS line printed and written for the outer run"
check $(beater_gone "$tmp/standin"; echo $?) "it beat, and its beater is gone with it"
check $(! grep -q "every part had ended" "$tmp/out.txt"; echo $?) "the tail's limit never met"
# The tail's own limit: the 11-15 fault put back in a copy (the bare wait), the limit 3 s.
standin hung
sed -i -e 's/^for p in \$parts; do wait "\$p"; done$/wait/' -e 's/^LAND_TAIL_SECONDS=180$/LAND_TAIL_SECONDS=3/' "$tmp/hung/tests/land.sh"
check $(grep -qx "wait" "$tmp/hung/tests/land.sh" && grep -qx "LAND_TAIL_SECONDS=3" "$tmp/hung/tests/land.sh"; echo $?) "the copy holds the bare wait and a 3 s limit"
standin_run hung 60
check $([ "$ended" = 1 ] && [ "$took" -lt 40 ]; echo $?) "a land.sh held past its parts ended by itself, in ${took} s"
check $(grep -q "^LANDING TESTS: FAIL (every part had ended, and land.sh had not ended 3 s later: stopped, its beat with it; give the lock back (883 amended (2)))" "$tmp/out.txt" \
	&& grep -q "^LANDING TESTS: FAIL (every part had ended" "$tmp/standin_result" 2>/dev/null; echo $?) "it failed loudly, its line printed and written for the outer run"
check $(beater_gone "$tmp/hung"; echo $?) "its beater gone with it"

echo "== checkout paths =="
python -B - "$here" <<'EOF' >"$tmp/out.txt" 2>&1
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "tools"))
import heavy_job as gate
ok = gate.same_checkout("/c/dev/psykinetic-trees/x", "C:/dev/psykinetic-trees/x") if os.name == "nt" else True
ok = ok and gate.same_checkout("C:/dev/a", "C:/dev/a/") and not gate.same_checkout("C:/dev/a", "C:/dev/ab")
ok = ok and not gate.same_checkout("", "") and gate.lock_checkout(os.path.join(os.environ["HEAVY_JOBS_DIR"], "no.lock")) == ""
print("ok" if ok else "bad")
EOF
check $(grep -qx ok "$tmp/out.txt"; echo $?) "Git Bash's and Windows' forms, a trailing slash, a free lock"

echo
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($failed failed)"; fi
[ "$failed" -eq 0 ]
