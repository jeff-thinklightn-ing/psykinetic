#!/usr/bin/env bash
# Everything a landing runs (decision 278): the suite (tests/run.sh), the
# network test, the state test and the exported server's boot (decision
# 450), at the same time; one summary and one exit code: 0 when all pass. Their ports and folders are their own
# (tests/suite_test checks), so they do not meet.
#   tests/land.sh
# The suite takes the job count (tests/jobs.sh) less the two the others use
# most of the time; each part's whole output is shown if it fails, else only
# its last line. tests/land.ps1 is the same; one of them is enough.
# A heavy job (decision 394): it runs through the gate as <checkout> suite
# (tools/heavy_job.py), waiting there if the machine has no room. If this
# checkout already holds suite (a landing takes it before the land lock, so
# it never waits on the gate holding the lock), the run adopts that take
# and is measured in it instead of queueing. tests/heavy_job_test runs
# first, alone.
set -u
cd "$(dirname "$0")/.."
tree="$(basename "$(pwd)")"
if [ -z "${HEAVY_JOB_INSIDE:-}" ]; then
	# The CHANGELOG first, no Godot, before any wait at the gate (decision
	# 539): released sections as tagged, no bullet both unreleased and released.
	python -B tools/changelog_check.py || { echo "LANDING TESTS: FAIL (CHANGELOG.md, decision 539: fix it as above)"; exit 1; }
	echo "landing tests: through the heavy-job gate as $tree suite (decision 394)"
	HEAVY_JOB_INSIDE=1 exec python tools/heavy_job.py run "$tree" suite -- bash tests/land.sh
fi
. tests/jobs.sh
LOGS="$(mktemp -d -t psykinetic-land.XXXXXX)"
trap 'rm -rf "$LOGS"' EXIT

jobs_at_once="$(test_jobs)"
suite_jobs=$(( jobs_at_once - 2 ))
[ "$suite_jobs" -lt 2 ] && suite_jobs=2
lean=""
if [ "${HEAVY_JOB_KIND:-}" = suite_lean ]; then
	# The gate ran it lean (394 amended (9)): memory was short, fewer at once.
	[ "$suite_jobs" -gt 3 ] && suite_jobs=3
	lean=", lean"
fi
started=$(date +%s)
echo "landing tests: the suite ($suite_jobs at once$lean), net_test, state_test and server_boot_test together"

part() {
	name="$1"
	shift
	t0=$(date +%s)
	"$@" >"$LOGS/$name.log" 2>&1
	echo "$? $(( $(date +%s) - t0 ))" >"$LOGS/$name.status"
	read -r code took <"$LOGS/$name.status"
	echo "$([ "$code" -eq 0 ] && echo PASS || echo FAIL)  $name ${took}s"
}
part heavy_job_test python -B tests/heavy_job_test.py
part changelog_check_test python -B tests/changelog_check_test.py
part changelog_resolve_test python -B tests/changelog_resolve_test.py
# Started a little apart, as the suite starts its scenes (decision 530: Godots
# launched in the same instant died at launch).
part suite env PSYKINETIC_TEST_JOBS="$suite_jobs" bash tests/run.sh &
sleep 0.3
part net_test bash tests/net_test.sh &
sleep 0.3
part state_test bash tests/state_test.sh &
sleep 0.3
part server_boot_test bash tests/server_boot_test.sh &
wait

code=0
failed=""
for name in heavy_job_test changelog_check_test changelog_resolve_test suite net_test state_test server_boot_test; do
	# A part killed before it wrote its status (no file, or empty) fails: an
	# empty status passed the test once, and economy's landing pushed over a
	# suite killed mid-run (2026-10-23). Only a status of exactly 0 passes.
	status=""
	[ -f "$LOGS/$name.status" ] && read -r status took <"$LOGS/$name.status"
	if [ "$status" != "0" ]; then
		[ -n "$status" ] || echo "FAIL  $name: killed before it finished (no exit status)"
		code=1
		failed="$failed $name"
	fi
done
# A failed run's logs, kept where they survive the run: .godot/test_failures
# (per checkout, never committed), the last ten. Prints where.
keep_failure() {
	kept=".godot/test_failures/$(date +%Y%m%d-%H%M%S)-$1"
	mkdir -p "$kept"
	shift
	cp -r "$@" "$kept"/ 2>/dev/null
	ls -1d .godot/test_failures/*/ 2>/dev/null | sort | head -n -10 | while read -r old; do rm -rf "$old"; done
	echo "kept in $kept"
}
for name in $failed; do
	echo
	echo "### $name (failed)"
	cat "$LOGS/$name.log"
done
if [ -n "$failed" ]; then
	keep_failure land "$LOGS"/*.log
fi
echo
if [ "$code" -eq 0 ]; then
	echo "LANDING TESTS: PASS (suite, net_test, state_test, server_boot_test, heavy_job_test, changelog_check_test, changelog_resolve_test; $(( $(date +%s) - started ))s)"
else
	echo "LANDING TESTS: FAIL ($failed; $(( $(date +%s) - started ))s)"
fi
exit $code
