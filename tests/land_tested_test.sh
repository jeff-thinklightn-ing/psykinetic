#!/usr/bin/env bash
# tools/land_tested.sh (278 amended (1)): a landing's PASS line names the commit its tests
# ran, and fails if HEAD or the tracked files moved during the run. Driven in a scratch git
# repository: a clean run's line carries the sha (and the push pattern finds it), a commit
# made mid-run fails it, a tracked file changed mid-run fails it, a run begun with tracked
# changes names no bare sha, a FAIL line passes through unchanged; and tests/land.sh and
# tests/land.ps1 use it. No Godot, no gate.
set -u
cd "$(dirname "$0")/.."
root="$PWD"
. tools/land_tested.sh
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = "$2" ]; then echo "  PASS  $3"; else echo "  FAIL  $3: got [$1], wanted [$2]"; failed=$((failed + 1)); fi
}
pushed() {  # The sha a landing script would push from the line, or nothing.
	printf '%s\n' "$1" | sed -n 's/^LANDING TESTS: PASS.* tested \([0-9a-f]\{40\}\)$/\1/p'
}
pass="LANDING TESTS: PASS (suite, net_test; 400s)"
cd "$tmp"
git init -q .
git config user.email test@example.invalid
git config user.name test
git config core.autocrlf false
echo one > a.txt
git add a.txt
git commit -q -m one
sha="$(git rev-parse HEAD)"

land_tested_begin
got="$(land_tested_end "$pass")"
check "$got" "$pass tested $sha" "a clean run: the PASS line ends with the commit tested"
check "$(pushed "$got")" "$sha" "the push pattern finds that sha"
check "$(land_tested_end "LANDING TESTS: FAIL ( suite; 400s)")" "LANDING TESTS: FAIL ( suite; 400s)" "a FAIL line passes through unchanged"

land_tested_begin
echo two > a.txt
git commit -q -am two
got="$(land_tested_end "$pass")"
case "$got" in "LANDING TESTS: FAIL (the tree moved during the tests: $sha to $(git rev-parse HEAD),"*) ok=yes ;; *) ok="$got" ;; esac
check "$ok" yes "a commit made mid-run fails the line, naming both shas"
check "$(pushed "$got")" "" "and nothing is pushed from it"

land_tested_begin
echo three > a.txt
got="$(land_tested_end "$pass")"
case "$got" in "LANDING TESTS: FAIL (the tree moved during the tests:"*) ok=yes ;; *) ok="$got" ;; esac
check "$ok" yes "a tracked file changed mid-run fails the line"

land_tested_begin
got="$(land_tested_end "$pass")"
check "$got" "$pass tested $(git rev-parse HEAD) and uncommitted changes" "a run begun with tracked changes says so"
check "$(pushed "$got")" "" "and names no bare sha to push"

echo four > b.txt
land_tested_begin
got="$(land_tested_end "$pass")"
check "$got" "$pass tested $(git rev-parse HEAD) and uncommitted changes" "an untracked file is no change (only the tracked one counts)"

cd "$root"
check "$(grep -c 'land_tested_begin\|land_tested_end' tests/land.sh)" 2 "tests/land.sh reads the commit before the run and stamps its line after"
check "$(grep -c 'tested \$tested' tests/land.ps1)" 2 "tests/land.ps1 does the same"
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
