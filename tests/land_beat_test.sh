#!/usr/bin/env bash
# The land lock's beats (667 amended (5)): the first beat logged once per take, a beat accepted
# from the checkout the lock was taken from whatever name it runs under, and status saying
# "never beaten" with the seconds. On a scratch land lock (PSYKINETIC_LAND_LOCK) and a scratch
# gate (HEAVY_JOBS_DIR); never touches the real locks or gate. When a lock goes stale is unchanged.
set -u
cd "$(dirname "$0")/.."
here="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export PSYKINETIC_LAND_LOCK="$tmp/land.lock" HEAVY_JOBS_DIR="$tmp/gate" HEAVY_JOB_TEST_FREE_GB=64
lock="$PSYKINETIC_LAND_LOCK"
lg="$lock.log"
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); sed "s/^/      | /" "$tmp/out.txt" 2>/dev/null; fi; }
L() { sh "$here/tools/land_lock.sh" "$@" >"$tmp/out.txt" 2>&1; }
firsts() { grep -c "first beat by" "$lg" 2>/dev/null || true; }
# Another checkout: a git folder of its own, from which the lock tool is run.
other="$tmp/other"
git init -q "$other"

echo "== the first beat, once per take =="
L take t "a take"; check $? "t takes the lock"
check $([ "$(cat "$lock/checkout")" = "$(git rev-parse --show-toplevel)" ]; echo $?) "the take records its checkout"
taken="$(( $(date +%s) - 42 ))"
echo "$taken" >"$lock/taken"; echo "$taken" >"$lock/since"
L status; check $(grep -qE "never beaten \(4[2-9] s\)" "$tmp/out.txt"; echo $?) "status: never beaten, with the seconds: $(cat "$tmp/out.txt")"
L beat t
check $([ "$(cat "$lock/since")" -gt "$taken" ]; echo $?) "the holder's beat moves since"
check $(grep -qE "first beat by t after 4[2-9] s \(t's take\)" "$lg"; echo $?) "its first beat logged with the seconds since the take"
L status; check $(grep -q "never beaten" "$tmp/out.txt" || grep -q "last beat" "$tmp/out.txt"; [ $? = 0 ] && ! grep -q "never beaten" "$tmp/out.txt"; echo $?) "status no longer says never beaten: $(cat "$tmp/out.txt")"
L beat t; L beat t
check $([ "$(firsts)" = 1 ]; echo $?) "two more beats: still one first-beat line ($(firsts))"
L release t
L take t "a second take"
L beat t
check $([ "$(firsts)" = 2 ]; echo $?) "a new take's first beat logged again ($(firsts))"
L release t

echo "== a beat in the take's own second still counts once =="
L take t "a take"
L beat t
L status; check $([ $? = 0 ] && ! grep -q "never beaten" "$tmp/out.txt"; echo $?) "beaten the same second as the take: not never beaten ($(cat "$tmp/out.txt"))"
L beat t
check $([ "$(firsts)" = 3 ]; echo $?) "and one first-beat line for it ($(firsts))"
L release t

echo "== a beat from the lock's own checkout, under another name =="
L take t "a take"
echo "1" >"$lock/since"
L beat physics; check $([ "$(cat "$lock/since")" != 1 ]; echo $?) "land.sh here under another name beats it"
check $(grep -qE "first beat by physics after [0-9]+ s \(t's take\)" "$lg"; echo $?) "its first beat logged under both names"
check $([ "$(cat "$lock/owner")" = t ]; echo $?) "the owner unchanged"
echo "1" >"$lock/since"
(cd "$other" && sh "$here/tools/land_lock.sh" beat physics >"$tmp/out.txt" 2>&1)
check $([ "$(cat "$lock/since")" = 1 ]; echo $?) "the same name from another checkout: no beat"
(cd "$other" && sh "$here/tools/land_lock.sh" beat t >"$tmp/out.txt" 2>&1)
check $([ "$(cat "$lock/since")" != 1 ]; echo $?) "the owner's name from anywhere: beaten, as before"
echo "1" >"$lock/since"
rm -f "$lock/checkout"
L beat physics; check $([ "$(cat "$lock/since")" = 1 ]; echo $?) "a lock with no checkout recorded: only its owner beats it"
L release t
L beat t; check $([ ! -d "$lock" ]; echo $?) "a free lock: a beat never takes it"
(cd "$other" && sh "$here/tools/land_lock.sh" take u "another checkout's take" >"$tmp/out.txt" 2>&1)
echo "1" >"$lock/since"
L beat t; check $([ "$(cat "$lock/since")" = 1 ] && [ "$(cat "$lock/owner")" = u ]; echo $?) "another checkout's lock under another name: never beaten from here"
(cd "$other" && sh "$here/tools/land_lock.sh" release u >/dev/null 2>&1)

echo "== when a lock goes stale is unchanged =="
L take t "a take"
taken="$(( $(date +%s) - 1400 ))"; echo "$taken" >"$lock/taken"; echo "$taken" >"$lock/since"
L take u "a take"; check $([ $? = 1 ] && [ "$(cat "$lock/owner")" = t ]; echo $?) "never beaten 1400 s: held, not taken over"
taken="$(( $(date +%s) - 1600 ))"; echo "$taken" >"$lock/taken"; echo "$taken" >"$lock/since"
L take u "a take"; check $([ $? = 0 ] && [ "$(cat "$lock/owner")" = u ]; echo $?) "never beaten 1600 s: taken over at 1500, as before"
L release u

echo "== release's freeze reads as before =="
L take release "v0.1.216 cut (main frozen)"
L beat release
L take u "a take"; check $([ $? = 3 ]; echo $?) "a take while main is frozen: exit 3"
L status; check $(grep -q "held by release" "$tmp/out.txt"; echo $?) "status names the freeze's holder"
L release release

[ "$failed" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL ($failed failed)"
[ "$failed" = 0 ]
