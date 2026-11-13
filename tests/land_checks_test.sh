#!/usr/bin/env bash
# tests/land.sh --checks (and land.ps1 -Checks) run only the landing's checks before the gate
# (278 amended (5)): the CHANGELOG, Godot launches' logs and the voice inventory, one "LANDING
# CHECKS: PASS|FAIL" line, no Godot, gate, lock or import. Once on this checkout as it is, then
# on a fake project (land.sh, land.ps1 and land_stamp.sh copied; the three checks faked, each
# failing on its own) for each way to fail, and that the voice inventory is never given the
# land lock to commit under.
set -u
cd "$(dirname "$0")/.."
tmp="$(mktemp -d -t land_checks.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi
}

# A land.sh without --checks would run a whole landing on the argument it ignores: none here.
if ! grep -q '^if \[ "${1:-}" = "--checks" \]; then' tests/land.sh || ! grep -q '^param(\[switch\]$Checks)' tests/land.ps1; then
	echo "  FAIL  tests/land.sh or land.ps1 has no --checks: not run, it would start a landing"
	echo
	echo "RESULT: FAIL (1 failed)"
	exit 1
fi

# This checkout: passes, quickly, and never reaches the gate.
started=$(date +%s)
out="$(bash tests/land.sh --checks 2>&1)"; code=$?
took=$(( $(date +%s) - started ))
check $([ $code = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^LANDING CHECKS: PASS')" = 1 ]; echo $?) \
	"this checkout: LANDING CHECKS: PASS, exit 0 (${took}s)"
check $(! printf '%s\n' "$out" | grep -qE "heavy-job gate|LANDING TESTS|land lock"; echo $?) "no gate, no landing result, no lock"

# The fake project.
mkdir -p "$tmp/p/tests" "$tmp/p/tools" "$tmp/lock"
cp tests/land.sh tests/land.ps1 "$tmp/p/tests/"
cp tools/land_stamp.sh "$tmp/p/tools/"
# tools/tracked_on_main.sh (667 amended (2)): says how it was run, exits FAKE_TRACKED.
printf '#!/usr/bin/env sh\necho "tracked_on_main $* exit ${FAKE_TRACKED:-0}"\nexit "${FAKE_TRACKED:-0}"\n' >"$tmp/p/tools/tracked_on_main.sh"
for tool in changelog_check godot_log_check voice_inventory; do
	cat >"$tmp/p/tools/$tool.py" <<EOF
import os, sys
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "$tool.args"), "w").write(" ".join(sys.argv[1:]))
code = int(os.environ.get("FAKE_$tool".upper(), "0"))
if "$tool" == "voice_inventory" and code == 3:
    print("VOICE INVENTORY STALE (a warning; not committed here: this tree doesn't hold the land lock)")
print("$tool exit %d" % code)
sys.exit(code)
EOF
done
# The land lock as land.sh finds it, held here by this checkout: --checks must not use it.
echo "fake-tree" >"$tmp/lock/owner"
run_fake() {
	(cd "$tmp/p" && env PSYKINETIC_LAND_LOCK="$tmp/lock" PSYKINETIC_TREE=fake-tree "$@" bash tests/land.sh --checks 2>&1)
}
out="$(run_fake)"; code=$?
check $([ $code = 0 ] && printf '%s\n' "$out" | grep -q '^LANDING CHECKS: PASS'; echo $?) "all three pass: PASS, exit 0"
check $(printf '%s\n' "$out" | grep -q "changelog_check exit 0" && printf '%s\n' "$out" | grep -q "godot_log_check exit 0" \
	&& printf '%s\n' "$out" | grep -q "voice_inventory exit 0"; echo $?) "each of the three ran"
lock_given="$(sed 's/.*--lock //' "$tmp/p/tools/voice_inventory.args")"
check $([ -n "$lock_given" ] && [ "$lock_given" != "$tmp/lock" ] && [ ! -e "$lock_given" ]; echo $?) \
	"the voice inventory's lock is an empty folder of its own, gone after (not the land lock)"
out="$(run_fake FAKE_CHANGELOG_CHECK=1)"; code=$?
check $([ $code = 1 ] && printf '%s\n' "$out" | grep -q '^LANDING CHECKS: FAIL (CHANGELOG.md' \
	&& ! printf '%s\n' "$out" | grep -q "godot_log_check exit"; echo $?) "a CHANGELOG fault: FAIL naming it, exit 1, nothing after"
out="$(run_fake FAKE_GODOT_LOG_CHECK=1)"; code=$?
check $([ $code = 1 ] && printf '%s\n' "$out" | grep -q '^LANDING CHECKS: FAIL (a Godot launch without --log-file'; echo $?) \
	"a Godot launch without its log: FAIL naming it"
out="$(run_fake FAKE_VOICE_INVENTORY=2)"; code=$?
check $([ $code = 1 ] && printf '%s\n' "$out" | grep -q '^LANDING CHECKS: FAIL (voice inventory'; echo $?) \
	"the voice inventory's generator failing: FAIL naming it"
out="$(run_fake FAKE_VOICE_INVENTORY=3)"; code=$?
check $([ $code = 0 ] && printf '%s\n' "$out" | tail -2 | grep -q '^VOICE INVENTORY STALE' \
	&& printf '%s\n' "$out" | tail -1 | grep -q "^LANDING CHECKS: PASS (.*its page stale"; echo $?) \
	"a stale page: a warning said again before PASS"
out="$(run_fake FAKE_TRACKED=1)"; code=$?
check $([ $code = 1 ] && printf '%s\n' "$out" | grep -q '^tracked_on_main --clear exit 1' \
	&& printf '%s\n' "$out" | grep -q '^LANDING CHECKS: FAIL (an untracked path origin/main tracks'; echo $?) \
	"a path that would stop the rebase: tracked_on_main --clear run, FAIL naming it (667 amended (2))"

# land.ps1 -Checks the same, where PowerShell is.
if command -v powershell.exe >/dev/null 2>&1; then
	ps1="$(cygpath -w "$tmp/p/tests/land.ps1" 2>/dev/null || echo "$tmp/p/tests/land.ps1")"
	(cd "$tmp/p" && PSYKINETIC_TREE=fake-tree powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" -Checks >"$tmp/ps.out" 2>&1); code=$?
	out="$(tr -d '\r' <"$tmp/ps.out")"
	check $([ $code = 0 ] && printf '%s\n' "$out" | tail -1 | grep -q '^LANDING CHECKS: PASS'; echo $?) "land.ps1 -Checks: PASS, exit 0"
	check $(! printf '%s\n' "$out" | grep -qE "heavy-job gate|LANDING TESTS"; echo $?) "land.ps1 -Checks: no gate"
	(cd "$tmp/p" && FAKE_GODOT_LOG_CHECK=1 PSYKINETIC_TREE=fake-tree powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" -Checks >"$tmp/ps.out" 2>&1); code=$?
	out="$(tr -d '\r' <"$tmp/ps.out")"
	check $([ $code = 1 ] && printf '%s\n' "$out" | tail -1 | grep -q '^LANDING CHECKS: FAIL (a Godot launch'; echo $?) "land.ps1 -Checks: a fault fails, naming it"
	lock_given="$(sed 's/.*--lock //' "$tmp/p/tools/voice_inventory.args")"
	check $(case "$lock_given" in *land-checks-*) [ ! -e "$lock_given" ]; echo $? ;; *) echo 1 ;; esac) \
		"land.ps1 -Checks: the voice inventory's lock is an empty folder of its own"
fi
grep -q "^part land_checks_test bash tests/land_checks_test.sh" tests/land.sh
check $? "tests/land.sh runs this test"
echo
echo "RESULT: $([ $failed = 0 ] && echo PASS || echo FAIL) ($failed failed)"
[ $failed = 0 ]
