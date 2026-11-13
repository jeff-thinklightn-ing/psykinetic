#!/usr/bin/env bash
# Everything a landing runs (decision 278): the suite (tests/run.sh), the
# network test, the state test and the exported server's boot (decision
# 450), at the same time; one summary and one exit code: 0 when all pass. Their ports and folders are their own
# (tests/suite_test checks), so they do not meet.
#   tests/land.sh
#   tests/land.sh --checks   only the checks a landing runs before the gate (the CHANGELOG,
#                            Godot launches' logs, the voice inventory), no Godot, gate, lock or
#                            import: one "LANDING CHECKS: PASS|FAIL" line (278 amended (5))
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
# The tree the gate knows it by: PSYKINETIC_TREE, else the folder's name. A
# landing's take under another name (a side worktree's) is still adopted by
# its process, not its name (394 amended (11)).
tree="${PSYKINETIC_TREE:-$(basename "$(pwd)")}"
# The land lock taken from this checkout under another name (decision 883): this
# run is that landing's, under the lock's name, never a second take queued
# under its lock (physics, 11-12 03:09).
land_lock_dir="${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}"
if [ -z "${PSYKINETIC_TREE:-}" ] && [ -f "$land_lock_dir/checkout" ] 	&& [ "$(cat "$land_lock_dir/checkout" 2>/dev/null)" = "$(git rev-parse --show-toplevel 2>/dev/null)" ]; then
	lock_tree="$(cat "$land_lock_dir/owner" 2>/dev/null)"
	if [ -n "$lock_tree" ] && [ "$lock_tree" != "$tree" ]; then
		echo "landing tests: the land lock was taken here by $lock_tree: run as $lock_tree, not $tree"
		tree="$lock_tree"
	fi
fi
. tools/land_stamp.sh
# The checks before the gate, no Godot: land.sh's first step, and all of --checks (278 amended
# (5)). [param 1] is the land lock the voice inventory may fold its page under: land.sh's own,
# or for --checks an empty folder, so it is never committed there. On a failure checks_why says
# why; a stale page is inventory_stale, a warning.
land_checks() {
	checks_why=""
	inventory_stale=""
	# The CHANGELOG first, before any wait at the gate (decision 539): released
	# sections as tagged, no bullet both unreleased and released.
	python -B tools/changelog_check.py || { checks_why="CHANGELOG.md, decision 539: fix it as above"; return 1; }
	# Every Godot the tooling starts writes its own log in build/logs, never
	# the shared user:// logs folder (decision 664).
	python -B tools/godot_log_check.py || { checks_why="a Godot launch without --log-file, silence or off-screen, decision 664 and its amendments: fix it as above"; return 1; }
	# docs/voice_inventory.md is generated: a changed player's line means
	# re-running its tool, never a hand edit (748 amended (6)). Under this
	# tree's land lock, clean and ahead of origin/main, a stale page is
	# regenerated as a commit of its own that goes out with the landing, its sha
	# named; elsewhere a stale page is a warning, said again before the result
	# line; a generator that fails stops the landing here (748 amended (8)).
	inventory_out="$(python -B tools/voice_inventory.py --land "$tree" --lock "$1" 2>&1)"
	inventory_code=$?
	[ -n "$inventory_out" ] && echo "$inventory_out"
	case "$inventory_code" in
		0|3) ;;
		*) checks_why="voice inventory, 748 amended (8): the generator failed, exit $inventory_code; run python -B tools/voice_inventory.py --check to see it"; return 1 ;;
	esac
	inventory_stale="$(printf '%s\n' "$inventory_out" | grep '^VOICE INVENTORY' || true)"
	return 0
}
if [ "${1:-}" = "--checks" ]; then
	no_lock="$(mktemp -d -t land-checks.XXXXXX)"
	land_checks "$no_lock"
	code=$?
	rm -rf "$no_lock"
	[ -n "$inventory_stale" ] && echo "$inventory_stale"
	if [ "$code" -eq 0 ]; then
		echo "LANDING CHECKS: PASS (CHANGELOG.md, Godot launches' logs, the voice inventory$([ -n "$inventory_stale" ] && echo ", its page stale: the landing regenerates it"))"
		exit 0
	fi
	echo "LANDING CHECKS: FAIL ($checks_why)"
	exit 1
fi
# The commit this run tests: a PASS stamps it only if HEAD is still here at the end.
export LAND_HEAD="${LAND_HEAD:-$(git rev-parse HEAD 2>/dev/null)}"
if [ -z "${HEAVY_JOB_INSIDE:-}" ]; then
	# The push guard's hook, when origin/main switches it on (tools/hooks/install).
	land_hook_install
	land_checks "$land_lock_dir" || { echo "LANDING TESTS: FAIL ($checks_why)"; exit 1; }
	# The commit these tests run, read once here, after the inventory's own commit and
	# before any part starts; the result line names it, or fails if it moved (278 amended (1)).
	. tools/land_tested.sh
	land_tested_begin
	# The Godot parts on saturn when it answers (Jeff, 2026-11-11: "go ahead
	# and move landings' test runs to saturn"; tools/remote_tests.sh): the
	# gate is then asked for suite_remote, the room of the parts that stay
	# here. A take this tree already holds decides it (a landing takes the
	# kind `tools/remote_tests.sh kind` prints, before the land lock);
	# LAND_LOCAL=1 keeps everything here (the cut's suite on main does).
	# A held suite_remote first: a take of suite the gate swapped when saturn
	# answered (394 amended (33)) holds both, and runs on saturn. A held
	# suite has this PC's room and runs here as before.
	kind=suite
	if [ -z "${LAND_LOCAL:-}" ] && python tools/heavy_job.py holds "$tree" suite_remote >/dev/null 2>&1; then
		kind=suite_remote
		echo "landing tests: this landing holds a suite_remote take: the Godot parts on saturn"
	elif python tools/heavy_job.py holds "$tree" suite >/dev/null 2>&1; then
		kind=suite
		echo "landing tests: this landing holds a suite take: every part here"
	else
		kind="$(bash tools/remote_tests.sh kind)"
		echo "landing tests: no take held; tools/remote_tests.sh kind says $kind"
	fi
	echo "landing tests: through the heavy-job gate as $tree $kind (decision 394)"
	# The result line said again last, after the gate's own lines (its
	# memory table): a check reading the log's tail reads the result. No
	# result line written is a fail, whatever the exit (a killed run).
	result="$(mktemp -t psykinetic-result.XXXXXX)"
	# While the tests run, a land lock this tree holds is beaten each minute (667
	# amended): a live landing, however long, is never taken for stale, and one
	# killed stops beating (the loop ends with this script) and goes stale as before.
	parent=$$
	( while kill -0 "$parent" 2>/dev/null; do sh tools/land_lock.sh beat "$tree"; sleep 60; done ) &
	beater=$!
	# Holding the land lock, never queue at the gate (394 amended (31)): with no
	# take of this tree's to run in (dropped while it waited, or never taken), the
	# run refuses at once (exit 6) instead of queueing with main locked.
	HEAVY_JOB_INSIDE=1 LAND_RESULT="$result" python tools/heavy_job.py run "$tree" "$kind" 		--no-queue-under-lock "${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}" -- bash tests/land.sh
	code=$?
	kill "$beater" 2>/dev/null
	line="$(cat "$result" 2>/dev/null)"
	rm -f "$result"
	[ -z "$line" ] && [ "$code" -eq 6 ] && line="LANDING TESTS: FAIL (lost the gate take while holding the land lock: release the lock, take the gate, then the lock again; 394 amended (31))"
	[ -n "$line" ] || line="LANDING TESTS: FAIL (the gated run ended, exit $code, with no result)"
	line="$(land_tested_end "$line")"
	echo
	[ -n "$inventory_stale" ] && echo "$inventory_stale"
	echo "$line"
	case "$line" in
		"LANDING TESTS: PASS"*) exit $code ;;
		*) [ "$code" -ne 0 ] && exit $code; exit 1 ;;
	esac
fi
. tests/jobs.sh
LOGS="$(mktemp -d -t psykinetic-land.XXXXXX)"
trap 'rm -rf "$LOGS"' EXIT

jobs_at_once="$(test_jobs)"
suite_jobs=$(( jobs_at_once - 2 ))
[ "$suite_jobs" -lt 2 ] && suite_jobs=2
lean=""
case "${HEAVY_JOB_KIND:-}" in
suite_lean*)
	# The gate ran it lean (394 amended (9), (10)): memory was short, fewer
	# at once, and net_test after the suite (state_test and server_boot_test beside it, 394 amended (19)).
	[ "$suite_jobs" -gt 3 ] && suite_jobs=3
	lean=1
	;;
esac
started=$(date +%s)
# Under the gate's suite_remote (chosen above when saturn answered): the
# suite, state_test and net_test run on saturn on this checkout's HEAD, the
# small Windows parts here. The gate gave this run only those parts' room,
# so a remote fail, or saturn lost since, fails the landing: there is no
# local second try.
remote=""
[ "${HEAVY_JOB_KIND:-}" = "suite_remote" ] && remote=1
if [ -n "$remote" ]; then
	echo "landing tests: the suite, state_test and net_test on saturn (tools/remote_tests.sh); server_boot_test and the tool tests here"
elif [ -n "$lean" ]; then
	echo "landing tests: the suite ($suite_jobs at once, lean) with state_test and server_boot_test beside it, then net_test"
else
	echo "landing tests: the suite ($suite_jobs at once), net_test, state_test and server_boot_test together"
fi

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
part decision_number_test python -B tests/decision_number_test.py
part changelog_check_test python -B tests/changelog_check_test.py
part changelog_resolve_test python -B tests/changelog_resolve_test.py
part voice_inventory_test python -B tests/voice_inventory_test.py
part remote_shot_clash_test bash tests/remote_shot_clash_test.sh
part push_guard_test bash tests/push_guard_test.sh
part remote_shot_sockets_test bash tests/remote_shot_sockets_test.sh
part land_tested_test bash tests/land_tested_test.sh
part fonts_imported_test bash tests/fonts_imported_test.sh
part run_digest_test bash tests/run_digest_test.sh
part land_checks_test bash tests/land_checks_test.sh
# Each font's .fontdata before any Godot part: a first import that segfaulted on the fonts left
# them unmade and server_boot_test's export failed on it (perf-sha, 11-13). One more import if
# one is missing, under this run's take; still missing, the part fails naming it.
part font_import bash tools/fonts_imported.sh .
grep -h "^re-imported: " "$LOGS/font_import.log"
# Started a little apart, as the suite starts its scenes (decision 530: Godots
# launched in the same instant died at launch).
if [ -n "$remote" ]; then
	part server_boot_test bash tests/server_boot_test.sh &
	part remote_prepare bash tools/remote_tests.sh prepare
	prepared=""
	read -r prepared _ <"$LOGS/remote_prepare.status"
	if [ "$prepared" = "0" ]; then
		part state_test bash tools/remote_tests.sh part state_test &
		sleep 0.3
		part suite bash tools/remote_tests.sh part suite
		part net_test bash tools/remote_tests.sh part net_test &
	fi
elif [ -n "$lean" ]; then
	# Lean (394 amended (19)): state_test and server_boot_test, a Godot or two
	# each, beside the suite; net_test, many at once, after it, its groups one
	# after another (394 amended (12)). state_test, boots one after another,
	# had become the longest part after the suite (~600 s, 2026-11-02).
	part state_test bash tests/state_test.sh &
	sleep 0.3
	part server_boot_test bash tests/server_boot_test.sh &
	sleep 0.3
	part suite env PSYKINETIC_TEST_JOBS="$suite_jobs" bash tests/run.sh
	part net_test env NET_TEST_SERIAL=1 bash tests/net_test.sh &
else
	part suite env PSYKINETIC_TEST_JOBS="$suite_jobs" bash tests/run.sh &
	sleep 0.3
	part net_test bash tests/net_test.sh &
	sleep 0.3
	part state_test bash tests/state_test.sh &
	sleep 0.3
	part server_boot_test bash tests/server_boot_test.sh &
fi
wait
[ -n "$remote" ] && bash tools/remote_tests.sh finish

code=0
failed=""
# The parts every run has, then any other part that wrote a status (remote_shot_clash_test
# was run and never counted until 278 amended (1)).
names="heavy_job_test decision_number_test changelog_check_test changelog_resolve_test voice_inventory_test ${remote:+remote_prepare} suite net_test state_test server_boot_test"
for each in "$LOGS"/*.status; do
	[ -f "$each" ] || continue
	each="$(basename "$each" .status)"
	case " $names " in *" $each "*) ;; *) names="$names $each" ;; esac
done
for name in $names; do
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
	line="LANDING TESTS: PASS (suite, net_test, state_test${remote:+ on saturn}, server_boot_test, heavy_job_test, decision_number_test, changelog_check_test, changelog_resolve_test, voice_inventory_test; $(( $(date +%s) - started ))s)"
else
	line="LANDING TESTS: FAIL ($failed; $(( $(date +%s) - started ))s)"
fi
echo "$line"
[ "$code" -eq 0 ] && land_stamp_write "$LAND_HEAD" "$tree" "$line"
[ -z "${LAND_RESULT:-}" ] || echo "$line" > "$LAND_RESULT"
exit $code
