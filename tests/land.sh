#!/usr/bin/env bash
# Everything a landing runs (decision 278): the suite (tests/run.sh), the
# network test, the state test and the exported server's boot (decision
# 450), at the same time; one summary and one exit code: 0 when all pass. Their ports and folders are their own
# (tests/suite_test checks), so they do not meet.
#   tests/land.sh
#   tests/land.sh --checks   only the checks a landing runs before the gate (the CHANGELOG,
#                            Godot launches' logs, the voice inventory), no Godot, gate, lock or
#                            import: one "LANDING CHECKS: PASS|FAIL" line (278 amended (5)); it
#                            names tools/load_check.sh, which it doesn't run (278 amended (7)); it
#                            clears what would stop the rebase, as the lock's take (667 amended (2))
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
# under its lock (physics, 11-12 03:09). Not under --checks (883 amended (1)): the checks take
# no lock and no gate, so the line was only noise there, and it failed land_checks_test's "no
# lock" row for a side worktree's landing run under its lock's name (sound's 924, 11-14).
land_lock_dir="${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}"
# 883 amended (2026-11-15): with PSYKINETIC_TREE set to a name that is not the lock's, the
# run stops here, exit 7 (no other way out of land.sh gives 7), holding nothing, its gate never
# asked. animation's land script took the gate and the lock as animation-gather and ran land.sh
# as animation: no take under that name, so it queued a second, 21st in the gate, holding the
# lock, whose minute beat (a beat from the lock's own checkout counts, 667 amended (5)) kept it
# fresh; 04:13 to 04:55, every queued tree waited. PSYKINETIC_TREE unset keeps 883's adopt.
if [ "${1:-}" != "--checks" ] && [ -f "$land_lock_dir/checkout" ] 		&& [ "$(cat "$land_lock_dir/checkout" 2>/dev/null)" = "$(git rev-parse --show-toplevel 2>/dev/null)" ]; then
	lock_tree="$(cat "$land_lock_dir/owner" 2>/dev/null)"
	if [ -n "$lock_tree" ] && [ "$lock_tree" != "$tree" ]; then
		if [ -z "${PSYKINETIC_TREE:-}" ]; then
			echo "landing tests: the land lock was taken here by $lock_tree: run as $lock_tree, not $tree"
			tree="$lock_tree"
		else
			held=""
			for name in "$tree" "$lock_tree"; do
				for each in suite_remote suite; do
					python tools/heavy_job.py holds "$name" "$each" >/dev/null 2>&1 && held="$held${held:+, }$name $each"
				done
			done
			echo "LANDING TESTS: FAIL (the land lock was taken from this checkout as $lock_tree; land.sh runs as $tree (PSYKINETIC_TREE=$PSYKINETIC_TREE), and the gate take is ${held:-none}: the gate take, the lock and PSYKINETIC_TREE are one name; release the lock and run again (883 amended))"
			exit 7
		fi
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
	# What would stop the rebase (667 amended (2)): the generated ones cleared, as the lock's take does.
	if [ "$code" -eq 0 ] && ! sh tools/tracked_on_main.sh --clear; then
		code=1
		checks_why="an untracked path origin/main tracks, named above (667 amended (2))"
	fi
	echo "not run here: bash tools/load_check.sh loads your changed scripts in a Godot with the autoloads in, a few seconds through the gate (278 amended (7))"
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
	# LAND_TEST_STANDIN (a tool test's, 883 amended): no checks, no hook, no tested sha, and
	# no part run inside the gate; only the naming, the gate and the beat.
	inventory_stale=""
	[ -z "${LAND_TEST_STANDIN:-}" ] && land_hook_install
	[ -n "${LAND_TEST_STANDIN:-}" ] || land_checks "$land_lock_dir" || { echo "LANDING TESTS: FAIL ($checks_why)"; exit 1; }
	# The commit these tests run, read once here, after the inventory's own commit and
	# before any part starts; the result line names it, or fails if it moved (278 amended (1)).
	. tools/land_tested.sh
	[ -z "${LAND_TEST_STANDIN:-}" ] && land_tested_begin
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
	elif [ -n "${LAND_TEST_STANDIN:-}" ]; then
		kind=suite  # Never saturn from a tool test.
	else
		kind="$(bash tools/remote_tests.sh kind)"
		echo "landing tests: no take held; tools/remote_tests.sh kind says $kind"
	fi
	echo "landing tests: through the heavy-job gate as $tree $kind (decision 394)"
	# The result line said again last, after the gate's own lines (its
	# memory table): a check reading the log's tail reads the result. No
	# result line written is a fail, whatever the exit (a killed run).
	result="$(mktemp -t psykinetic-result.XXXXXX)"
	# The land lock's minute beat runs inside the gated run (below), from the grant on, never
	# while a run waits in the queue (883 amended).
	# Holding the land lock, never queue at the gate (394 amended (31)): with no
	# take of this tree's to run in (dropped while it waited, or never taken), the
	# run refuses at once (exit 6) instead of queueing with main locked.
	HEAVY_JOB_INSIDE=1 LAND_RESULT="$result" python tools/heavy_job.py run "$tree" "$kind" 		--no-queue-under-lock "${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}" -- bash tests/land.sh
	code=$?
	line="$(cat "$result" 2>/dev/null)"
	rm -f "$result"
	[ -z "$line" ] && [ "$code" -eq 6 ] && line="LANDING TESTS: FAIL (lost the gate take while holding the land lock: release the lock, take the gate, then the lock again; 394 amended (31))"
	[ -n "$line" ] || line="LANDING TESTS: FAIL (the gated run ended, exit $code, with no result)"
	[ -z "${LAND_TEST_STANDIN:-}" ] && line="$(land_tested_end "$line")"
	echo
	[ -n "$inventory_stale" ] && echo "$inventory_stale"
	echo "$line"
	case "$line" in
		"LANDING TESTS: PASS"*) exit $code ;;
		*) [ "$code" -ne 0 ] && exit $code; exit 1 ;;
	esac
fi
. tests/jobs.sh
. tests/land_retry.sh  # tool_part: a tool part retried once on a temp-folder fault (278 amended (8)).
LOGS="$(mktemp -d -t psykinetic-land.XXXXXX)"
# 878 amended (2): saturn's slot given back on every way out (a failed or refused
# part, a stop), not only after the parts: ui's landing that ended at 20:20 on 11-14
# left its holder, and the next landing's tests were refused. finish removes the
# holder only when it names this tree and this commit.
on_exit() {
	[ -n "${beater:-}" ] && kill "$beater" 2>/dev/null
	[ -n "${tail_guard:-}" ] && kill "$tail_guard" 2>/dev/null
	if [ -n "${remote:-}" ]; then
		bash tools/remote_tests.sh finish >/dev/null 2>&1
	fi
	rm -rf "$LOGS"
}
trap on_exit EXIT
# While the tests run, a land lock this tree holds is beaten each minute (667 amended): a live
# landing, however long, is never taken for stale, and one killed stops beating (the loop ends
# with this script) and goes stale as before. Since 883 amended it starts here, in the run the
# gate granted (a landing holding its take: at once, its first beat in its first second), never
# in the run that asks the gate: one that ever waited in the queue holding the lock would not
# beat it, and the lock would go stale by 667's rule instead of living as long as the wait.
parent=$$
( while kill -0 "$parent" 2>/dev/null; do sh tools/land_lock.sh beat "$tree"; sleep 60; done ) &
beater=$!
if [ -n "${LAND_TEST_STANDIN:-}" ]; then
	sleep "$LAND_TEST_STANDIN"
	line="LANDING TESTS: FAIL (a tool test's stand-in, no part run)"
	echo "$line"
	[ -z "${LAND_RESULT:-}" ] || echo "$line" > "$LAND_RESULT"
	exit 1
fi

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
tool_part heavy_job_test python -B tests/heavy_job_test.py
tool_part decision_number_test python -B tests/decision_number_test.py
tool_part changelog_check_test python -B tests/changelog_check_test.py
tool_part changelog_resolve_test python -B tests/changelog_resolve_test.py
tool_part voice_inventory_test python -B tests/voice_inventory_test.py
tool_part remote_shot_clash_test bash tests/remote_shot_clash_test.sh
tool_part push_guard_test bash tests/push_guard_test.sh
# About 80 s, and the parts here run one after another before the Godot parts (667 amended (3), the
# coordinator's ask): only when the take changes the push helper, the lock it checks or the test.
if git diff --name-only origin/main...HEAD -- tools/land_push.sh tools/land_lock.sh tools/bench_lock.sh tests/land_push_test.sh 2>/dev/null | grep -q .; then
	tool_part land_push_test bash tests/land_push_test.sh
else
	echo "land_push_test: not run (the take changes none of tools/land_push.sh, land_lock.sh, bench_lock.sh or its test)"
fi
# Saturn's slot taken from a landing gone here (878 amended (1)), about 30 s: only when the take
# changes tools/remote_tests.sh or the test.
if git diff --name-only origin/main...HEAD -- tools/remote_tests.sh tests/remote_slot_test.sh 2>/dev/null | grep -q .; then
	tool_part remote_slot_test bash tests/remote_slot_test.sh
else
	echo "remote_slot_test: not run (the take changes neither tools/remote_tests.sh nor its test)"
fi
# A pending freeze's own test (667 amended (4)), about 20 s: only when the take changes the lock or the test.
if git diff --name-only origin/main...HEAD -- tools/land_lock.sh tools/bench_lock.sh tests/land_freeze_test.sh 2>/dev/null | grep -q .; then
	tool_part land_freeze_test bash tests/land_freeze_test.sh
else
	echo "land_freeze_test: not run (the take changes none of tools/land_lock.sh, bench_lock.sh or its test)"
fi
# The lock's beats (667 amended (5)), a few seconds: only when the take changes the lock or the test.
if git diff --name-only origin/main...HEAD -- tools/land_lock.sh tools/bench_lock.sh tests/land_beat_test.sh 2>/dev/null | grep -q .; then
	tool_part land_beat_test bash tests/land_beat_test.sh
else
	echo "land_beat_test: not run (the take changes none of tools/land_lock.sh, bench_lock.sh or its test)"
fi
# One name for a landing (883 amended), about 35 s: only when the take changes land.sh, the gate,
# the lock or the test.
if git diff --name-only origin/main...HEAD -- tests/land.sh tools/heavy_job.py tools/land_lock.sh tests/land_name_test.sh 2>/dev/null | grep -q .; then
	tool_part land_name_test bash tests/land_name_test.sh
else
	echo "land_name_test: not run (the take changes none of tests/land.sh, tools/heavy_job.py, land_lock.sh or its test)"
fi
# The retry's own test (278 amended (8)), about 15 s: only when the take changes land.sh, the retry or the test.
if git diff --name-only origin/main...HEAD -- tests/land.sh tests/land_retry.sh tests/land_retry_test.sh 2>/dev/null | grep -q .; then
	tool_part land_retry_test bash tests/land_retry_test.sh
else
	echo "land_retry_test: not run (the take changes none of tests/land.sh, land_retry.sh or its test)"
fi
tool_part remote_shot_sockets_test bash tests/remote_shot_sockets_test.sh
tool_part land_tested_test bash tests/land_tested_test.sh
tool_part fonts_imported_test bash tests/fonts_imported_test.sh
tool_part run_digest_test bash tests/run_digest_test.sh
tool_part land_checks_test bash tests/land_checks_test.sh
tool_part run_parse_test bash tests/run_parse_test.sh
tool_part load_check_test bash tests/load_check_test.sh
tool_part tracked_on_main_test bash tests/tracked_on_main_test.sh
# Each font's .fontdata before any Godot part: a first import that segfaulted on the fonts left
# them unmade and server_boot_test's export failed on it (perf-sha, 11-13). One more import if
# one is missing, under this run's take; still missing, the part fails naming it.
tool_part font_import bash tools/fonts_imported.sh .
grep -h "^re-imported: " "$LOGS/font_import.log"
# Started a little apart, as the suite starts its scenes (decision 530: Godots
# launched in the same instant died at launch).
if [ -n "$remote" ]; then
	part server_boot_test bash tests/server_boot_test.sh &
	part remote_prepare bash tools/remote_tests.sh prepare
	prepared=""
	read -r prepared _ <"$LOGS/remote_prepare.status"
	# Where saturn's scene caps came from (90 amended (2)): own, seeded from a tree, or none.
	grep -h "^durations: " "$LOGS/remote_prepare.log"
	# 878 amended (2): a prepare can fail now (before it, every exit came back 0). Its
	# line says which: a slot refused (another landing's, live or not given up in 10
	# minutes) is never this commit's fault, so the landing ends here and says requeue.
	if [ "$prepared" != "0" ]; then
		grep -h "^remote" "$LOGS/remote_prepare.log" | tail -3
		if grep -q "slot is held by" "$LOGS/remote_prepare.log"; then
			echo "SATURN SLOT REFUSED: not this commit's fault; no part ran; requeue (878 amended (2))"
		fi
	fi
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
# The parts alone are waited for, by their own pids, never a bare wait: a bare wait waits for
# every child of this shell, and the beater (above) is one that ends only with this shell. With
# 883 amended (2)'s beat begun here, perf-lockname's landing (11-15, 11:26 to 12:17) waited on
# it for ever after every part had passed, its beat keeping the lock fresh: 46 minutes of the
# whole queue (883 amended (2)).
parts="$(jobs -p | grep -vx "$beater")"
# The tail's own limit (883 amended (2)): once every part has ended, land.sh has
# LAND_TAIL_SECONDS to end too (its tail is the counting and the result line, seconds). Past
# it, whatever holds it, the run fails loudly, its result line written, and stops: its beat
# goes with it (on_exit), and the land script gives the lock back as on any failure.
LAND_TAIL_SECONDS=180
( for p in $parts; do while kill -0 "$p" 2>/dev/null; do sleep 2; done; done
	# In 1 s steps, so a guard stopped at the run's end leaves no long sleep behind it.
	waited=0
	while [ "$waited" -lt "$LAND_TAIL_SECONDS" ]; do
		kill -0 "$parent" 2>/dev/null || exit 0
		sleep 1
		waited=$((waited + 1))
	done
	kill -0 "$parent" 2>/dev/null || exit 0
	line="LANDING TESTS: FAIL (every part had ended, and land.sh had not ended $LAND_TAIL_SECONDS s later: stopped, its beat with it; give the lock back (883 amended (2)))"
	echo "$line"
	[ -z "${LAND_RESULT:-}" ] || echo "$line" > "$LAND_RESULT"
	kill "$parent" ) &
tail_guard=$!
for p in $parts; do wait "$p"; done
[ -n "$remote" ] && bash tools/remote_tests.sh finish
# 278 amended (9): a scene over 220 s in this suite is named, a warning and not a failure; the
# tree adding its next row splits it, as view_test and view_land_test were.
awk '($1 == "PASS" || $1 == "FAIL") && $3 ~ /^[0-9]+s/ { s = $3 + 0; if (s > 220) print "slow scene: " $2 " " s " s, over 220 s; split it at its next row (278 amended (9))" }' "$LOGS/suite.log" 2>/dev/null

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
# A tool part retried on the temp folder is named in the line a tree copies (278 amended (8)).
retried="$(land_retried)"
if [ "$code" -eq 0 ]; then
	line="LANDING TESTS: PASS (suite, net_test, state_test${remote:+ on saturn}, server_boot_test, heavy_job_test, decision_number_test, changelog_check_test, changelog_resolve_test, voice_inventory_test$retried; $(( $(date +%s) - started ))s)"
else
	line="LANDING TESTS: FAIL ($failed$retried; $(( $(date +%s) - started ))s)"
fi
echo "$line"
[ "$code" -eq 0 ] && land_stamp_write "$LAND_HEAD" "$tree" "$line"
[ -z "${LAND_RESULT:-}" ] || echo "$line" > "$LAND_RESULT"
exit $code
