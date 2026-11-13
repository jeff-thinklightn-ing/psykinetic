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
#   tests/run.sh tests/x_test.tscn [...]   only the scenes named (a solo run, through the
#                           gate: sh tools/heavy_job.sh run <tree> scene -- bash tests/run.sh
#                           tests/x_test.tscn); the other scenes' times kept
# A scene whose script fails to parse is stopped 3 s after the line, not left to its time
# limit (278 amended (6)).
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
# Godot running, waiting) is killed and fails the run. Since 90 amended (1)
# this is the floor: a scene gets twice its own last run (DURATIONS) when
# that is more, up to TIMEOUT_CAP, so a slow scene on a loaded machine is
# not killed at 300 s (view_test and view_land_test run 150 to 240 s lean,
# and were killed in four landings, 11-07).
TIMEOUT="${TEST_TIMEOUT:-300}"
TIMEOUT_CAP=900

cd "$(dirname "$0")/.."
. tests/godot_log.sh  # Its logs in build/logs (decision 664).
. tests/jobs.sh
SERIAL=0
# Named scenes (278 amended (6)): only those, as a solo run through the gate's scene kind; the
# whole suite when none is named. net_test is no scene: it runs alone as the net kind.
NAMED=""
for arg in "$@"; do
	case "$arg" in
		--serial) SERIAL=1 ;;
		*net_test*) echo "run.sh: $arg refused: net_test runs alone as the gate's net kind (tests/net_test.sh), never as a scene (394 amended (24))"; exit 2 ;;
		*.tscn)
			arg="${arg#./}"
			arg="${arg#res://}"
			[ -f "$arg" ] || { echo "run.sh: no scene $arg"; exit 2; }
			NAMED="$NAMED $arg" ;;
		*) echo "run.sh: $arg: not --serial or a scene (tests/x_test.tscn)"; exit 2 ;;
	esac
done
# Logs of this run's own: other worktrees may be running the suite too.
LOGS="$(mktemp -d -t psykinetic-run.XXXXXX)"
trap 'rm -rf "$LOGS"' EXIT
DURATIONS=.godot/test_durations.txt
# Each scene's last time (s), read once (90 amended (1)); the subshells that
# run the scenes inherit it.
declare -A LAST_TOOK
if [ -f "$DURATIONS" ]; then
	while read -r last_took last_scene; do
		[ -n "$last_scene" ] && [ -z "${LAST_TOOK[$last_scene]:-}" ] && LAST_TOOK[$last_scene]="$last_took"
	done <"$DURATIONS"
fi

# The time limit of [param 1]'s scene: TIMEOUT, or twice its last run when
# that is more, at most TIMEOUT_CAP (and never under TIMEOUT).
scene_limit() {
	last="${LAST_TOOK[$1]:-0}"
	limit=$(( last * 2 ))
	[ "$limit" -gt "$TIMEOUT_CAP" ] && limit="$TIMEOUT_CAP"
	[ "$limit" -lt "$TIMEOUT" ] && limit="$TIMEOUT"
	echo "$limit"
}

# Every tests/*_test.tscn, found by name, so a new test scene needs no edit here (a
# shared list made every tree adding a test conflict with the others). Slowest
# first by the last run's times; a scene not timed yet goes first too (it may be slow).
# One awk for all (a process a scene costs seconds on Windows).
scenes="$({ if [ -n "$NAMED" ]; then printf '%s\n' $NAMED | sort -u; else ls tests/*_test.tscn; fi; } | awk -v durations="$DURATIONS" '
	BEGIN { while ((getline line < durations) > 0) { split(line, f, " "); if (!(f[2] in took)) took[f[2]] = f[1] } }
	{ print ($0 in took ? took[$0] : 999), $0 }' | sort -rn | cut -d' ' -f2)"

# A failed scene's lines that name its failure (278 amended (4)): every failed check, every
# engine error with the two lines after it and its RESULT line, at most 40, for the summary at
# the end, where a reader's tail looks. combat's 874 amended (1) landing on saturn: its FAIL
# line sat 800 lines up in sound_kit_test's whole output, and the last ten were all PASS.
digest() {
	awk 'after > 0 { print; after--; next }
		/SCRIPT ERROR|^ERROR:/ { print; after = 2; next }
		/^ *FAIL  |^RESULT:/ { print }' "$1" | head -40
}

# A script that fails to parse leaves its scene idling to its time limit (278 amended (6): maps'
# view_test sat 301 s on 11-07, enemy-ai's solo scene its ten minutes twice on 11-12): once one of
# these lines shows, the scene is given PARSE_GRACE seconds for the lines after it, then stopped.
PARSE_STOP='^SCRIPT ERROR: Parse Error|^ERROR: Failed to load script'
PARSE_GRACE=3

# Stops the Godot this run started (278 amended (6)): the timeout at [param 1], this shell's own
# background job, and everything under it, walked by parent id from its own pid, never by a name
# or a marker: the shell's process tree (ps), and on Windows each one's native children (the
# console build's game) created at or after [param 2] (epoch s), which Git bash's ps doesn't show.
# On saturn (Linux) the same with ps -o.
stop_own() {
	if command -v powershell.exe >/dev/null 2>&1; then
		# Git bash: "PID PPID PGID WINPID ...", a row maybe led by a flag letter.
		rows="$(ps -l 2>/dev/null | awk 'NR > 1 { if ($1 !~ /^[0-9]+$/) { $1 = ""; $0 = $0 } print $1, $2, $4 }')"
	else
		rows="$(ps -e -o pid= -o ppid= 2>/dev/null | awk '{ print $1, $2, 0 }')"
	fi
	tree="$(printf '%s\n' "$rows" | awk -v root="$1" '{ parent[$1] = $2; win[$1] = $3 }
		END { want[root] = 1; more = 1
			while (more) { more = 0; for (p in parent) if (!(p in want) && (parent[p] in want)) { want[p] = 1; more = 1 } }
			for (p in want) print p, (p in win ? win[p] : 0) }')"
	wins="$(printf '%s\n' "$tree" | awk '$2 > 0 { printf "%s%s", sep, $2; sep = "," }')"
	if [ -n "$wins" ]; then
		powershell.exe -NoProfile -Command "\$since = [DateTimeOffset]::FromUnixTimeSeconds($2).LocalDateTime.AddSeconds(-1); \$all = @(Get-CimInstance Win32_Process); \$ids = @($wins); for (\$i = 0; \$i -lt \$ids.Count; \$i++) { \$p = \$ids[\$i]; \$all | Where-Object { \$_.ParentProcessId -eq \$p -and \$_.CreationDate -ge \$since -and \$ids -notcontains \$_.ProcessId } | ForEach-Object { \$ids += \$_.ProcessId } }; [array]::Reverse(\$ids); foreach (\$id in \$ids) { Stop-Process -Id \$id -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
	fi
	for p in $(printf '%s\n' "$tree" | awk '{ print $1 }'); do kill -TERM "$p" 2>/dev/null; done
}

# Watches $log while the scene's Godot (the timeout at [param 1], started at [param 2]) runs: on a
# PARSE_STOP line, PARSE_GRACE seconds more, then the line to <log>.parse and the scene stopped.
watch_parse() {
	while kill -0 "$1" 2>/dev/null; do
		sleep 1
		line="$(grep -m 1 -E "$PARSE_STOP" "$log" 2>/dev/null)"
		[ -z "$line" ] && continue
		sleep "$PARSE_GRACE"
		kill -0 "$1" 2>/dev/null || return 0  # It ended on its own.
		printf '%s\n' "$line" >"$log.parse"
		stop_own "$1" "$2"
		return 0
	done
}

# The scene's Godot, its output to $log, under its time limit and watch_parse; its exit in status.
# Godot log name [param 1].
play() {
	rm -f "$log.parse"
	since=$(date +%s)
	timeout --kill-after=10 "$limit" "$GODOT" --log-file "$(godot_log "$1")" --headless --path . --scene "$scene" -- "--run-marker=$marker" </dev/null >"$log" 2>&1 &
	godot=$!
	watch_parse "$godot" "$since" &
	watcher=$!
	wait "$godot"
	status=$?
	kill "$watcher" 2>/dev/null
	wait "$watcher" 2>/dev/null
}

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
	limit="$(scene_limit "$scene")"
	play "$name"
	retried=""
	if launch_failed "$status" "$started" "$log"; then
		# Died at launch, before any of its own code ran (decision 530: exit 127
		# with an empty log, exit 1 after the banner, in a suite's first burst):
		# noted with what the machine had, then run once more.
		retried="$(launch_note "$name" "$status" "$log")"
		retried="${retried%%; backtrace:*}"  # The whole one is in the gate's log.
		sleep 2
		again=$(date +%s)
		play "${name}_again"
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
	if [ -f "$log.parse" ]; then
		# Stopped early (278 amended (6)): the rest of the scene never ran.
		why="a parse error: stopped early, ${PARSE_GRACE}s after it, the rest of the scene not run: $(cat "$log.parse")"
		echo "FAIL  $scene $why" >>"$log"
	elif [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
		# Apart from a failed check (90 amended (1)): a kill for time, noted in
		# the gate's log too, so the record tells the two apart.
		why="timed out under load: did not finish within ${limit}s (its last run took ${LAST_TOOK[$scene]:-no}s; a parse error or a hang ends here too): killed"
		echo "FAIL  $scene $why" >>"$log"
		python -B tools/heavy_job.py note "$(basename "$(pwd)")" timeout "$name after ${limit}s (its last run ${LAST_TOOK[$scene]:-unknown}s)" >/dev/null 2>&1
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
# A run of named scenes keeps every other scene's time (278 amended (6)).
{ cat "$LOGS"/*.took 2>/dev/null
	[ -n "$NAMED" ] && [ -f "$DURATIONS" ] && awk -v named="$scenes" 'BEGIN { n = split(named, s, /[ \n]+/); for (i = 1; i <= n; i++) if (s[i] != "") ran[s[i]] = 1 } !($2 in ran)' "$DURATIONS"
} | sort -rn >"$DURATIONS.new" && mv "$DURATIONS.new" "$DURATIONS"
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
	timed_out=$(cat "$LOGS"/*.result 2>/dev/null | grep -c ": timed out under load:")
	slow=""
	[ "$timed_out" -gt 0 ] && slow="; $timed_out of them timed out under load, not a failed check"
	echo "SUITE: FAIL ($(echo "$failed" | wc -w | tr -d ' ') of $count failed:$failed$slow; $(( $(date +%s) - started ))s$again)"
	for name in $failed; do
		cat "$LOGS/$name.log.result"
		digest "$LOGS/$name.log"
	done
fi
exit $code
