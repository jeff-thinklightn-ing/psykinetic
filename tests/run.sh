#!/usr/bin/env bash
# Runs the headless sim tests: every tests/*_test.tscn, several at once
# (decision 278). Exit code 0 = every assertion in every scene passed, 1 = any
# failed: a scene's non-zero exit, a timeout, or SCRIPT ERROR / ERROR: in its
# output.
#   tests/run.sh            in parallel: PSYKINETIC_TEST_JOBS at once, else
#                           half the cores less the other Godot processes
#                           running (other trees' tests), 2 to 8; 2 while
#                           another tree holds the bench lock
#   tests/run.sh --serial   one after another, each scene's output as it goes
# The slowest scenes start first (their last times are kept in
# .godot/test_durations.txt); a line prints as each finishes, and at the end
# the whole output of every scene that failed, then a summary.
# Godot is taken from $GODOT_PATH, or `godot` on PATH.
set -u

GODOT="${GODOT_PATH:-godot}"

# The Windows GUI build detaches from the console (no output, no exit code);
# use the console build that ships next to it when there is one.
case "$GODOT" in
	*_console.exe) ;;
	*.exe)
		console="${GODOT%.exe}_console.exe"
		if [ -f "$console" ]; then GODOT="$console"; fi
		;;
esac

# A scene that has not finished in this many seconds (a parse error leaves
# Godot running, waiting) is killed and fails the run.
TIMEOUT="${TEST_TIMEOUT:-300}"

cd "$(dirname "$0")/.."
. tests/godot_log.sh  # Its logs in build/logs (decision 664).
. tests/jobs.sh
SERIAL=0
[ "${1:-}" = "--serial" ] && SERIAL=1
# Logs of this run's own: other worktrees may be running the suite too.
LOGS="$(mktemp -d -t psykinetic-run.XXXXXX)"
trap 'rm -rf "$LOGS"' EXIT
DURATIONS=.godot/test_durations.txt

# Every tests/*_test.tscn, found by name, so a new test scene needs no edit here (a
# shared list made every tree adding a test conflict with the others). Slowest
# first by the last run's times; a scene not timed yet goes first too (it may be slow).
# One awk for all (a process a scene costs seconds on Windows).
scenes="$(ls tests/*_test.tscn | awk -v durations="$DURATIONS" '
	BEGIN { while ((getline line < durations) > 0) { split(line, f, " "); if (!(f[2] in took)) took[f[2]] = f[1] } }
	{ print ($0 in took ? took[$0] : 999), $0 }' | sort -rn | cut -d' ' -f2)"

# One scene, its output to its log; then its verdict line in <log>.result:
# "PASS name 12s" or "FAIL name 3s (why)", and its time for DURATIONS.
run_scene() {
	scene="$1"
	name="${scene##*/}"
	name="${name%.tscn}"
	log="$LOGS/$name.log"
	started=$(date +%s)
	# The marker names this run's process of this scene, for the kill below.
	marker="psykinetic-run-$$-$name"
	timeout --kill-after=10 "$TIMEOUT" "$GODOT" --log-file "$(godot_log "$(basename "$scene" .tscn)")" --headless --path . --scene "$scene" -- "--run-marker=$marker" </dev/null >"$log" 2>&1
	status=$?
	retried=""
	if launch_failed "$status" "$started" "$log"; then
		# Died at launch, before any of its own code ran (decision 530: exit 127
		# with an empty log, exit 1 after the banner, in a suite's first burst):
		# noted with what the machine had, then run once more.
		retried="$(launch_note "$name" "$status" "$log")"
		retried="${retried%%; backtrace:*}"  # The whole one is in the gate's log.
		sleep 2
		again=$(date +%s)
		timeout --kill-after=10 "$TIMEOUT" "$GODOT" --log-file "$(godot_log "$(basename "$scene" .tscn)_again")" --headless --path . --scene "$scene" -- "--run-marker=$marker" </dev/null >"$log" 2>&1
		status=$?
		if launch_failed "$status" "$again" "$log"; then
			again_note="$(launch_note "$name" "$status" "$log")"
			retried="$retried; the retry too: ${again_note%%; backtrace:*}"
		fi
	fi
	if { [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; } && command -v powershell.exe >/dev/null 2>&1; then
		# On Windows the console build runs the game as a child, which outlives
		# the wrapper timeout kills: stop it too, found by this run's marker.
		powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*$marker*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
	fi
	took=$(( $(date +%s) - started ))
	why=""
	if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
		why="did not finish within ${TIMEOUT}s (a parse error, or a hang): killed"
		echo "FAIL  $scene $why" >>"$log"
	elif grep -q "SCRIPT ERROR\|^ERROR:" "$log"; then
		why="an engine error: $(grep -m 1 "SCRIPT ERROR\|^ERROR:" "$log")"
	elif [ "$status" -ne 0 ]; then
		why="$(grep -m 1 '^RESULT:' "$log" || echo "exit $status")"
	fi
	[ -n "$retried" ] && retried=" (retried after a launch failure: $retried)"
	if [ -z "$why" ]; then
		echo "PASS  $name ${took}s$retried" >"$log.result"
	else
		echo "FAIL  $name ${took}s: $why$retried" >"$log.result"
	fi
	echo "$took $scene" >"$log.took"
}

# What a scene that died at launch may show (decision 530): Godot's banner,
# blank lines and, since 530 amended (anim_rig_test, signal 11 at 5 s), the
# engine's crash-handler block. Any other line is the game's own.
LAUNCH_ONLY='^Godot Engine v|^[[:space:]]*$|^=+$|^CrashHandlerException:|^Engine version:|^Dumping the backtrace|^Load address:|^\[[0-9]+\] |^-- END OF .*BACKTRACE --$'

# Whether a scene died at launch (decision 530): exit [param 1] non-zero
# within 10 s of [param 2] (5 until 530 amended: a crash dump took 5 s, an
# instant exit read 6 under load), and its log [param 3] holding nothing but
# LAUNCH_ONLY's lines (no line of the game's own, no RESULT). A scene that
# ran any of its own code is never retried.
launch_failed() {
	[ "$1" -ne 0 ] && [ $(( $(date +%s) - $2 )) -le 10 ] \
		&& ! grep -v -q -E "$LAUNCH_ONLY" "$3"
}

# A launch failure's diagnosis for its .result, logged in the gate's log too
# (heavy_job summary counts them): exit [param 2], the command, where its
# programs resolve, the machine's free RAM and commit; a crash's top frame
# and its whole backtrace from log [param 3] (heavy_job summary groups
# crashes by top frame: the same one again is an engine or asset bug).
launch_note() {
	detail="$1 exit $2 at launch; timeout: $(command -v timeout || echo none), godot: $(command -v "$GODOT" || echo "$GODOT not found")"
	if grep -q '^CrashHandlerException:' "$3"; then
		frames="$(grep -E '^\[[0-9]+\] ' "$3" | sed -E 's/^\[[0-9]+\] [0-9a-fx]+ \(([^)]*)\).*/\1/' | tr '\n' ' ')"
		detail="$detail; crashed ($(grep -m 1 '^CrashHandlerException:' "$3" | sed 's/^CrashHandlerException: //')) at ${frames%% *}; backtrace: ${frames% }"
	fi
	python -B tools/heavy_job.py note "$(basename "$(pwd)")" launch "$detail" 2>/dev/null || echo "$detail"
}

started=$(date +%s)
if [ "$SERIAL" -eq 1 ]; then
	jobs_at_once=1
	for scene in $scenes; do
		echo "### $scene"
		run_scene "$scene"
		name="${scene##*/}"; cat "$LOGS/${name%.tscn}.log"
	done
else
	jobs_at_once="$(test_jobs)"
	echo "running $(echo "$scenes" | wc -w | tr -d ' ') scenes, $jobs_at_once at once"
	running=0
	for scene in $scenes; do
		if [ "$running" -ge "$jobs_at_once" ]; then
			wait -n
			running=$((running - 1))
		fi
		( run_scene "$scene"; cat "$LOGS/$name.log.result" ) &
		running=$((running + 1))
		# Not all in the same instant (decision 530): two scenes died at launch
		# in a suite's first burst of nine Godots.
		sleep 0.2
	done
	wait
fi

code=0
failed=""
for scene in $scenes; do
	name="${scene##*/}"
	name="${name%.tscn}"
	if ! grep -q '^PASS' "$LOGS/$name.log.result" 2>/dev/null; then
		code=1
		failed="$failed $name"
	fi
done
# The times, for the next run's order.
cat "$LOGS"/*.took 2>/dev/null | sort -rn >"$DURATIONS.new" && mv "$DURATIONS.new" "$DURATIONS"
if [ "$SERIAL" -eq 0 ]; then
	for name in $failed; do
		echo
		echo "### tests/$name.tscn (failed)"
		cat "$LOGS/$name.log"
	done
fi
echo
count=$(echo "$scenes" | wc -w | tr -d ' ')
retries=$(cat "$LOGS"/*.result 2>/dev/null | grep -c "retried after a launch failure")
again=""
[ "$retries" -gt 0 ] && again="; $retries retried after a launch failure"
if [ "$code" -eq 0 ]; then
	echo "SUITE: PASS ($count scenes, $jobs_at_once at once, $(( $(date +%s) - started ))s$again)"
	cat "$LOGS"/*.result 2>/dev/null | grep "retried after a launch failure"
else
	echo "SUITE: FAIL ($(echo "$failed" | wc -w | tr -d ' ') of $count failed:$failed; $(( $(date +%s) - started ))s$again)"
	for name in $failed; do cat "$LOGS/$name.log.result"; done
fi
exit $code
