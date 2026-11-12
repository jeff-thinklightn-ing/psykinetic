#!/usr/bin/env bash
# The push guard (decision 883): tools/land_stamp.sh's stamp and install, and
# tools/hooks/pre-push, in a scratch clone pushing to a scratch bare remote.
# Never touches this checkout's own hooks or stamps.
set -u
cd "$(dirname "$0")/.."
here="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi
}
g() { git -c user.name=t -c user.email=t@t -c core.autocrlf=false -c advice.detachedHead=false "$@"; }

git init -q --bare -b main "$tmp/remote.git"
g clone -q "$tmp/remote.git" "$tmp/clone" 2>/dev/null
cd "$tmp/clone"
mkdir -p tools/hooks docs
cp "$here/tools/hooks/pre-push" tools/hooks/pre-push
echo off > tools/hooks/install
echo "code" > game.gd; echo "# readme" > README.md
g add -A; g commit -q -m base; g push -q origin HEAD:main 2>/dev/null
common="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
. "$here/tools/land_stamp.sh"
cp "$here/tools/hooks/pre-push" "$common/hooks/pre-push"; chmod +x "$common/hooks/pre-push"
# The gate's log for the loud line: a scratch state folder, the gate's script beside the clone.
mkdir -p "$tmp/state"; cp "$here/tools/heavy_job.py" tools/heavy_job.py
export HEAVY_JOBS_DIR="$tmp/state"
echo "tools/heavy_job.py" >> .git/info/exclude

push() { g push origin "HEAD:${1:-main}" > "$tmp/push.txt" 2>&1; }

echo "== a code change to main =="
echo "code 2" > game.gd; g commit -qam "a change"
push; check $(( $? == 0 ? 1 : 0 )) "no stamp: refused"
grep -q "Run tests/land.sh on this commit" "$tmp/push.txt"; check $? "the refusal names the remedy"
start="$(git rev-parse HEAD)"
land_stamp_write "$start" t "LANDING TESTS: PASS (suite, net_test, state_test on saturn, ...; 300s)" > "$tmp/stamp.txt"
check $? "a saturn PASS with HEAD unchanged writes the stamp"
[ -f "$common/land_pass/$start" ] && grep -q "^line=LANDING TESTS: PASS (suite, net_test, state_test on saturn" "$common/land_pass/$start"
check $? "the stamp is named for HEAD's sha and holds the saturn PASS line"
push; check $? "with the stamp: pushed"

echo "== HEAD moved during the run =="
start="$(git rev-parse HEAD)"
echo "code 3" > game.gd; g commit -qam "moved"
land_stamp_write "$start" t "LANDING TESTS: PASS (...)" > "$tmp/stamp.txt"
check $(( $? == 0 ? 1 : 0 )) "no stamp written"
[ ! -f "$common/land_pass/$(git rev-parse HEAD)" ]; check $? "none for the new HEAD either"
grep -q "HEAD moved during the run" "$tmp/stamp.txt"; check $? "it says why"
push; check $(( $? == 0 ? 1 : 0 )) "and its push is refused"
g reset -q --hard origin/main

echo "== pushes the guard leaves alone =="
echo "## v0.1.212" >> CHANGELOG.md; g add -A; g commit -qm "cut"
push; check $? "a cut (CHANGELOG.md only): pushed with no stamp"
echo "notes" > docs/notes.txt; echo "more" >> README.md; echo "x" > docs/decisions.md; g add -A; g commit -qm "docs"
push; check $? "docs/ and top-level Markdown: pushed with no stamp"
mkdir -p sub; echo "# not top" > sub/x.md; g add -A; g commit -qm "nested md"
push; check $(( $? == 0 ? 1 : 0 )) "Markdown below the top, outside docs/: needs a stamp"
g reset -q --hard origin/main
echo "code 4" > game.gd; g commit -qam "a branch's own work"
push perf-x; check $? "a push to another branch: never looked at"
g reset -q --hard origin/main

echo "== a revert =="
g revert --no-edit "$(git log --format=%H --grep="^a change$" -1)" >/dev/null 2>&1
git diff --name-only origin/main HEAD | grep -qx game.gd; check $? "(a revert of a code change made)"
push; check $(( $? == 0 ? 1 : 0 )) "a revert with no stamp: refused, no bypass"
g reset -q --hard origin/main

echo "== the owner's marker (Jeff's pick B) =="
echo "code 5" > game.gd; g commit -qam "mine [owner-push]"
push; check $(( $? == 0 ? 1 : 0 )) "the marker off (as shipped): refused"
sed 's/^OWNER_MARKER=""/OWNER_MARKER="[owner-push]"/' "$here/tools/hooks/pre-push" > "$common/hooks/pre-push"
push; check $? "the marker on: pushed without a stamp"
cp "$here/tools/hooks/pre-push" "$common/hooks/pre-push"
g reset -q --hard origin/main

echo "== an error of the guard's own =="
echo "code 6" > game.gd; g commit -qam "while broken"
PUSH_GUARD_BREAK=1 push; check $? "it lets the push through"
grep -q "the push goes through unguarded" "$tmp/push.txt"; check $? "loudly"
grep -q "push_guard" "$tmp/state/heavy_jobs.log" 2>/dev/null; check $? "with a line in the gate's log"

echo "== the install =="
rm -f "$common/hooks/pre-push"
land_hook_install; [ ! -e "$common/hooks/pre-push" ]; check $? "origin/main's install says off: nothing installed"
echo on > tools/hooks/install; g commit -qam "install on"
land_stamp_write "$(git rev-parse HEAD)" t "LANDING TESTS: PASS" >/dev/null; push
g fetch -q origin
land_hook_install > "$tmp/install.txt"; cmp -s "$common/hooks/pre-push" tools/hooks/pre-push; check $? "on: origin/main's copy installed"
echo "# a branch's edit" >> tools/hooks/pre-push
land_hook_install; ! grep -q "a branch's edit" "$common/hooks/pre-push"; check $? "from origin/main, never the branch's copy"
git checkout -q tools/hooks/pre-push
rm -f "$common/hooks/pre-push"; : > "$common/hooks/pre-push.lifted"
land_hook_install; [ ! -e "$common/hooks/pre-push" ]; check $? "lifted by release: not put back"

echo "== the lock records its checkout =="
PSYKINETIC_BENCH_LOCK="$tmp/land.lock" sh "$here/tools/bench_lock.sh" take t "x" >/dev/null
[ "$(cat "$tmp/land.lock/checkout")" = "$(git rev-parse --show-toplevel)" ]; check $? "the lock names the checkout it was taken from"

cd "$here"
echo
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
