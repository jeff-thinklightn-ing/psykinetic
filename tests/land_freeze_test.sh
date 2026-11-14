#!/usr/bin/env bash
# A pending freeze (667 amended (4)): tools/land_lock.sh freeze/unfreeze and a take during one,
# on a scratch land lock (PSYKINETIC_LAND_LOCK), a scratch bench lock and a scratch gate
# (HEAVY_JOBS_DIR). Never touches the real locks or gate. The holder's push through
# tools/land_push.sh during a pending freeze is tests/land_push_test.sh's.
set -u
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
loop=""
trap '[ -n "$loop" ] && kill "$loop" 2>/dev/null; rm -rf "$tmp"' EXIT
export PSYKINETIC_LAND_LOCK="$tmp/land.lock" HEAVY_JOBS_DIR="$tmp/gate" HEAVY_JOB_TEST_FREE_GB=64
mark="$PSYKINETIC_LAND_LOCK.freeze"
lg="$PSYKINETIC_LAND_LOCK.log"
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); sed "s/^/      | /" "$tmp/out.txt" 2>/dev/null; fi; }
L() { sh tools/land_lock.sh "$@" >"$tmp/out.txt" 2>&1; }
logged() { grep -qF "$1" "$lg" 2>/dev/null; }

echo "== a pending freeze while a landing holds the lock =="
L take t "a take"; check $? "t takes the lock"
L freeze release "v0.1.216 cut"; check $? "the freeze written at once: exit 0"
[ -f "$mark/owner" ] && [ -f "$mark/why" ] && [ -f "$mark/since" ] && [ -f "$mark/beat" ] && [ "$(cat "$mark/owner")" = release ]
check $? "the mark: owner, why, since, beat"
logged "freeze pending by release (v0.1.216 cut)"; check $? "logged"
L take u "another take"; code=$?
check $([ $code = 3 ] && grep -q "main frozen (pending)" "$tmp/out.txt"; echo $?) "another take: exit 3, \"main frozen (pending)\" ($code)"
logged "refused u (another take): main frozen (pending)"; check $? "the refusal logged"
L status; check $(grep -q "freeze pending by release" "$tmp/out.txt"; echo $?) "status names it"

echo "1" >"$PSYKINETIC_LAND_LOCK/since"; mark_beat="$(cat "$mark/beat")"
L beat t; check $([ "$(cat "$PSYKINETIC_LAND_LOCK/since")" != 1 ] && [ "$(cat "$mark/beat")" = "$mark_beat" ]; echo $?) "the holder's beat lands, the mark untouched"
L release t; check $([ $? = 0 ] && [ ! -d "$PSYKINETIC_LAND_LOCK" ] && [ -d "$mark" ]; echo $?) "the holder's release lands, the mark kept"

echo "0" >"$mark/beat"; echo "$(( $(date +%s) - 10 ))" >"$mark/beat"; old="$(cat "$mark/beat")"
L take release "v0.1.216 cut (main frozen)"; code=$?
check $([ $code = 0 ] && [ "$(cat "$PSYKINETIC_LAND_LOCK/owner")" = release ]; echo $?) "release's frozen take gets the free lock ($code)"
check $([ "$(cat "$mark/beat")" -gt "$old" ]; echo $?) "its try beats the mark"
echo "$(( $(date +%s) - 10 ))" >"$mark/beat"; old="$(cat "$mark/beat")"
L beat release; check $([ "$(cat "$mark/beat")" -gt "$old" ]; echo $?) "its beat while holding the lock beats the mark"
L unfreeze u; check $([ $? = 1 ] && [ -d "$mark" ]; echo $?) "another tree's unfreeze: refused, the mark kept"
L unfreeze release; check $([ $? = 0 ] && [ ! -d "$mark" ] && [ ! -d "$PSYKINETIC_LAND_LOCK" ]; echo $?) "release's unfreeze: the mark and the lock gone"
logged "freeze mark removed by release" && logged "released by release"; check $? "both logged"
L take u "after the cut"; check $? "a take after the unfreeze: exit 0"
L release u

echo "== a stale mark =="
L freeze release "v0.1.216 cut"
echo "$(( $(date +%s) - 1600 ))" >"$mark/beat"
L take u "a take"; code=$?
check $([ $code = 0 ] && [ "$(cat "$PSYKINETIC_LAND_LOCK/owner")" = u ]; echo $?) "unbeaten 1600 s (stale at 1500): passed, taken ($code)"
logged "pending freeze stale, passed by u"; check $? "the pass logged"
L release u; rm -rf "$mark"

echo "== the bench lock never reads it =="
L freeze release "v0.1.216 cut"
mkdir -p "$tmp/bench.lock.freeze"
PSYKINETIC_BENCH_LOCK="$tmp/bench.lock" sh tools/bench_lock.sh take u "a bench" >"$tmp/out.txt" 2>&1; check $? "a bench take during a pending freeze: exit 0"
PSYKINETIC_BENCH_LOCK="$tmp/bench.lock" sh tools/bench_lock.sh release u >/dev/null 2>&1
rm -rf "$mark"

echo "== a waiter already in its loop when the mark is written =="
# CLAUDE.md's loop: the gate's take first, then the lock's tries with the take's holds check;
# on exit 3 the gate's take is given back and the loop stops.
L take t "a take"
python -B tools/heavy_job.py take w suite_remote >"$tmp/gate_take.txt" 2>&1
python -B tools/heavy_job.py holds w suite_remote >/dev/null 2>&1; check $? "w holds its gate take"
(
	while :; do
		sh tools/land_lock.sh take w "w's landing" >>"$tmp/w.txt" 2>&1; code=$?
		[ $code = 0 ] && { echo taken >"$tmp/w.end"; break; }
		if [ $code = 3 ]; then
			python -B tools/heavy_job.py release w suite_remote >/dev/null 2>&1
			echo "stopped 3" >"$tmp/w.end"; break
		fi
		python -B tools/heavy_job.py holds w suite_remote >/dev/null 2>&1 || { echo "lost its take" >"$tmp/w.end"; break; }
		sleep 1
	done
) &
loop=$!
until grep -q "held by t" "$tmp/w.txt" 2>/dev/null; do sleep 0.2; done
L freeze release "v0.1.216 cut"
for i in $(seq 1 60); do [ -f "$tmp/w.end" ] && break; sleep 0.5; done
check $([ "$(cat "$tmp/w.end" 2>/dev/null)" = "stopped 3" ] && grep -q "main frozen (pending)" "$tmp/w.txt"; echo $?) "its next try gets 3: \"$(cat "$tmp/w.end" 2>/dev/null)\""
python -B tools/heavy_job.py holds w suite_remote >/dev/null 2>&1; check $([ $? != 0 ]; echo $?) "its gate take given back"
check $([ "$(cat "$PSYKINETIC_LAND_LOCK/owner")" = t ]; echo $?) "the holder still holds the lock"
wait "$loop" 2>/dev/null; loop=""
L unfreeze release; L release t

[ "$failed" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL ($failed failed)"
[ "$failed" = 0 ]
