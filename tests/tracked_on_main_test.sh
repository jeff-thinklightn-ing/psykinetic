#!/usr/bin/env bash
# tools/tracked_on_main.sh and the land lock's take with it (667 amended (2)), in a throwaway
# origin and clone: origin/main adds a .import, a .uid, a hand file, an ignored one and one
# the take has staged; the lock, its log and the gate's state are private (never C:/dev/land.lock
# or the live queue).
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi; }
work="$(mktemp -d -t tracked_test.XXXXXX)"
trap 'rm -rf "$work"' EXIT
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
quiet() { git -c init.defaultBranch=main -c user.email=t@t -c user.name=t -c core.autocrlf=false "$@" >/dev/null 2>&1; }
quiet init --bare "$work/origin.git"
quiet clone "$work/origin.git" "$work/seed"
cd "$work/seed" || exit 1
printf 'gen.ignored\n' >.gitignore
echo base >base.txt
quiet add -A && quiet commit -m base && quiet push origin HEAD:main
quiet clone "$work/origin.git" "$work/clone"
echo tracked >x.import; echo tracked >y.uid; echo tracked >hand.txt; echo tracked >gen.ignored; echo tracked >staged.import
mkdir -p dir.import && echo tracked >dir.import/inner.txt
quiet add -f x.import y.uid hand.txt gen.ignored staged.import dir.import/inner.txt && quiet commit -m "main tracks" && quiet push origin HEAD:main
main="$(git rev-parse --short HEAD)"
cd "$work/clone" || exit 1
quiet config user.email t@t && quiet config user.name t && quiet config core.autocrlf false
echo mine >take.txt && quiet add take.txt && quiet commit -m take
put() { for f in "$@"; do echo local >"$f"; done; }
put x.import y.uid hand.txt gen.ignored staged.import
quiet add -f staged.import
tool="$here/tools/tracked_on_main.sh"

out="$(sh "$tool" 2>&1)"; code=$?
check $([ $code = 1 ] && printf '%s\n' "$out" | grep -q "x.import is untracked here" && printf '%s\n' "$out" | grep -q "y.uid is untracked" \
	&& printf '%s\n' "$out" | grep -q "hand.txt is untracked" && [ -f x.import ] && [ -f y.uid ]; echo $?) \
	"named: the .import, the .uid and the hand file, exit 1, nothing removed without --clear"
check $(printf '%s\n' "$out" | grep -q "gen.ignored\|staged.import"; [ $? = 1 ]; echo $?) \
	"not named: one ignored here (git overwrites it) nor one in the index"

out="$(sh "$tool" --clear 2>&1)"; code=$?
check $([ $code = 1 ] && [ ! -e x.import ] && [ ! -e y.uid ] && [ -f hand.txt ] && [ -f gen.ignored ] && [ -f staged.import ] \
	&& [ "$(printf '%s\n' "$out" | grep -c '^tracked_on_main: removed ')" = 2 ] && printf '%s\n' "$out" | grep -q "hand.txt is untracked"; echo $?) \
	"--clear: the .import and the .uid removed, a line each; the hand file named, exit 1; the ignored and staged kept"

mkdir -p dir.import && echo local >dir.import/inner.txt
out="$(sh "$tool" --clear 2>&1)"
check $([ -d dir.import ] && [ -f dir.import/inner.txt ] && printf '%s\n' "$out" | grep -q "dir.import/inner.txt is untracked"; echo $?) \
	"a directory named like a generated file: never removed, its file named"
rm -rf dir.import

export PSYKINETIC_LAND_LOCK="$(win "$work/land.lock")" HEAVY_JOBS_DIR="$(win "$work/gate")"
lock="$here/tools/land_lock.sh"
put x.import
out="$(sh "$lock" take t1 "a landing" 2>&1)"; code=$?
check $([ $code = 4 ] && [ ! -d "$work/land.lock" ] && [ ! -e x.import ] && printf '%s\n' "$out" | grep -q "not taken: an untracked path"; echo $?) \
	"the take: the .import cleared, the hand file refuses it, exit 4, no lock left held"
check $(grep -q "cleared t1 x.import (origin/main $main" "$work/land.lock.log" && grep -q "refused t1 hand.txt (origin/main $main" "$work/land.lock.log" \
	&& grep -q "refused t1 (a landing)" "$work/land.lock.log"; echo $?) "the lock's log: each removal and refusal, with the tree, the path and origin/main's sha"
rm -f hand.txt
out="$(sh "$lock" take t2 "the next" 2>&1)"; code=$?
check $([ $code = 0 ] && [ "$(cat "$work/land.lock/owner" 2>/dev/null)" = t2 ]; echo $?) "a second take straight after succeeds: the refused one held nothing"
sh "$lock" release t2 >/dev/null 2>&1

put x.import hand.txt
out="$(sh "$lock" take release "main frozen for the cut" 2>&1)"; code=$?
check $([ $code = 0 ] && [ -f x.import ] && [ -f hand.txt ] && ! printf '%s\n' "$out" | grep -q tracked_on_main; echo $?) \
	"release's freeze: no check, nothing removed, never refused"
sh "$lock" release release >/dev/null 2>&1

quiet remote set-url origin "$work/nowhere.git"
out="$(sh "$lock" take t3 "a landing" 2>&1)"; code=$?
check $([ $code = 0 ] && [ -f x.import ] && printf '%s\n' "$out" | grep -q "fetching origin/main failed"; echo $?) \
	"a failed fetch: one line, the take granted as before, nothing removed"
sh "$lock" release t3 >/dev/null 2>&1
quiet remote set-url origin "$work/origin.git"

rm -f x.import hand.txt
out="$(sh "$lock" take t4 "a landing" 2>&1)"; code=$?
check $([ $code = 0 ] && ! printf '%s\n' "$out" | grep -q tracked_on_main; echo $?) "a clean checkout: taken as today, nothing said"
sh "$lock" release t4 >/dev/null 2>&1

PSYKINETIC_LOCK_STALE=1500 out="$(PSYKINETIC_BENCH_LOCK="$(win "$work/bench.lock")" sh "$here/tools/bench_lock.sh" take t5 bench 2>&1)"; code=$?
check $([ $code = 0 ]; echo $?) "the bench lock never runs it"
PSYKINETIC_BENCH_LOCK="$(win "$work/bench.lock")" sh "$here/tools/bench_lock.sh" release t5 >/dev/null 2>&1

if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
