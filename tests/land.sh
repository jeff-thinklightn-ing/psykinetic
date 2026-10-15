#!/usr/bin/env bash
# Everything a landing runs (decision 278): the suite (tests/run.sh), the
# network test and the state test, at the same time; one summary and one exit
# code: 0 when all three pass. Their ports and folders are their own
# (tests/suite_test checks), so they do not meet.
#   tests/land.sh
# The suite takes the job count (tests/jobs.sh) less the two the others use
# most of the time; each part's whole output is shown if it fails, else only
# its last line. tests/land.ps1 is the same; one of them is enough.
set -u
cd "$(dirname "$0")/.."
. tests/jobs.sh
LOGS="$(mktemp -d -t psykinetic-land.XXXXXX)"
trap 'rm -rf "$LOGS"' EXIT

jobs_at_once="$(test_jobs)"
suite_jobs=$(( jobs_at_once - 2 ))
[ "$suite_jobs" -lt 2 ] && suite_jobs=2
started=$(date +%s)
echo "landing tests: the suite ($suite_jobs at once), net_test and state_test together"

part() {
	name="$1"
	shift
	t0=$(date +%s)
	"$@" >"$LOGS/$name.log" 2>&1
	echo "$? $(( $(date +%s) - t0 ))" >"$LOGS/$name.status"
	read -r code took <"$LOGS/$name.status"
	echo "$([ "$code" -eq 0 ] && echo PASS || echo FAIL)  $name ${took}s"
}
part suite env PSYKINETIC_TEST_JOBS="$suite_jobs" bash tests/run.sh &
part net_test bash tests/net_test.sh &
part state_test bash tests/state_test.sh &
wait

code=0
failed=""
for name in suite net_test state_test; do
	read -r status took <"$LOGS/$name.status"
	if [ "$status" -ne 0 ]; then
		code=1
		failed="$failed $name"
	fi
done
for name in $failed; do
	echo
	echo "### $name (failed)"
	cat "$LOGS/$name.log"
done
echo
if [ "$code" -eq 0 ]; then
	echo "LANDING TESTS: PASS (suite, net_test, state_test; $(( $(date +%s) - started ))s)"
else
	echo "LANDING TESTS: FAIL ($failed; $(( $(date +%s) - started ))s)"
fi
exit $code
