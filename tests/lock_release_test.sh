#!/usr/bin/env bash
# A lock's release with a file held open (667 amended (6)): on Windows a file another process
# holds open (Python's open() doesn't share delete) survives rm -rf, and the folder stayed held
# (combat-lob's release, 11-15 15:18:05). tools/bench_lock.sh's remove_lock tries again till the
# folder is gone; past its last try, "release incomplete", exit 5; a lock with no "since" ages
# from its folder's mtime. On a scratch land lock (PSYKINETIC_LAND_LOCK), a scratch bench lock
# and a scratch gate (HEAVY_JOBS_DIR); never the real ones. LOCK_RELEASE_TEST_BENCH_LOCK runs it
# against another copy of bench_lock.sh (the old one, to see these rows fail there).
set -u
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
holder=""
trap '[ -n "$holder" ] && kill "$holder" 2>/dev/null; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tools"
cp tools/land_lock.sh tools/heavy_job.py tools/heavy_job.sh tools/tracked_on_main.sh "$tmp/tools/" 2>/dev/null
cp "${LOCK_RELEASE_TEST_BENCH_LOCK:-tools/bench_lock.sh}" "$tmp/tools/bench_lock.sh"
for f in tools/*.py; do [ -f "$tmp/$f" ] || cp "$f" "$tmp/tools/"; done
export PSYKINETIC_LAND_LOCK="$tmp/land.lock" HEAVY_JOBS_DIR="$tmp/gate" HEAVY_JOB_TEST_FREE_GB=64
lg="$PSYKINETIC_LAND_LOCK.log"
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); sed "s/^/      | /" "$tmp/out.txt" 2>/dev/null; sed "s/^/      log| /" "$lg" 2>/dev/null | tail -6; fi; }
L() { sh "$tmp/tools/land_lock.sh" "$@" >"$tmp/out.txt" 2>&1; }
B() { PSYKINETIC_BENCH_LOCK="$tmp/bench.lock" sh "$tmp/tools/bench_lock.sh" "$@" >"$tmp/out.txt" 2>&1; }
# A Python child holds <file> open, as a waiter's read does, for <seconds>; back once it has it open.
hold_open() {
	rm -f "$tmp/opened"
	python -c "import sys, time
f = open(sys.argv[1])
open(sys.argv[2], 'w').close()
time.sleep(float(sys.argv[3]))
f.close()" "$(cygpath -w "$1" 2>/dev/null || echo "$1")" "$(cygpath -w "$tmp/opened" 2>/dev/null || echo "$tmp/opened")" "$2" &
	holder=$!
	for _ in $(seq 1 100); do [ -f "$tmp/opened" ] && return 0; sleep 0.1; done
	return 1
}

echo "== the land lock: its owner file held open for 2 s during the release =="
L take t "a take"; check $? "t takes the lock"
hold_open "$PSYKINETIC_LAND_LOCK/owner" 2; check $? "a reader holds its owner file open"
L release t; code=$?
wait "$holder" 2>/dev/null; holder=""
check $([ $code = 0 ] && [ ! -d "$PSYKINETIC_LAND_LOCK" ]; echo $?) "the release ends with the folder gone (exit $code)"
check $(grep -q "release by t: .* still there after try 1 (left: owner" "$lg" && grep -q "released by t" "$lg"; echo $?) "the try that left a file is logged with its name, then the release"
L take u "the next"; check $? "the next take gets it at once"
L release u

echo "== the bench lock (the same file): its owner held open for 2 s =="
B take t "a bench"; check $? "t takes the bench lock"
hold_open "$tmp/bench.lock/owner" 2; check $? "a reader holds its owner file open"
B release t; code=$?
wait "$holder" 2>/dev/null; holder=""
check $([ $code = 0 ] && [ ! -d "$tmp/bench.lock" ]; echo $?) "the bench lock's release ends with its folder gone (exit $code)"

echo "== held open past every try: release incomplete, exit 5, the lock named =="
L take t "a take"; check $? "t takes the lock"
hold_open "$PSYKINETIC_LAND_LOCK/owner" 4; check $? "a reader holds its owner file open for 4 s"
PSYKINETIC_LOCK_REMOVE_TRIES=2 L release t; code=$?
check $([ $code = 5 ] && grep -q "release incomplete by t" "$tmp/out.txt"; echo $?) "exit 5, \"release incomplete\" said ($code)"
check $(grep -q "release incomplete by t: .* still there after 2 tries (left: owner" "$lg"; echo $?) "and logged, naming what is left"
check $([ -d "$PSYKINETIC_LAND_LOCK" ] && [ "$(cat "$PSYKINETIC_LAND_LOCK/owner")" = t ]; echo $?) "the lock stays, its owner named"
L status; check $(grep -q "held by t" "$tmp/out.txt"; echo $?) "status: held by t"
wait "$holder" 2>/dev/null; holder=""

echo "== a remnant (owner and checkout, no since): it goes stale by the rule (the bench lock, whose stale time a test may set) =="
bl="$tmp/bench.lock"
rm -rf "$bl"; mkdir "$bl"; echo t >"$bl/owner"; echo here >"$bl/checkout"
PSYKINETIC_LOCK_STALE=60 B take u "a fresh remnant"; code=$?
check $([ $code = 1 ] && [ "$(cat "$bl/owner")" = t ]; echo $?) "fresh (its folder just made, as a lock mid-take): held, not taken (exit $code)"
touch -d "@$(( $(date +%s) - 120 ))" "$bl"
B status; check $(grep -q "held by t ().* 2 min" "$tmp/out.txt"; echo $?) "status reads its age from its folder: 2 min, never 0 min"
PSYKINETIC_LOCK_STALE=60 B take u "past the stale time"; code=$?
check $([ $code = 0 ] && [ "$(cat "$bl/owner")" = u ] && grep -q "taking over a stale lock" "$tmp/out.txt"; echo $?) "120 s old against a 60 s stale time: taken over (exit $code)"
B release u
check $([ ! -d "$bl" ]; echo $?) "and released"

echo
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($failed)"; exit 1; fi
