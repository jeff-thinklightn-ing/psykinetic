#!/usr/bin/env bash
# tests/run.sh stops a scene whose script fails to parse (278 amended (6)): 3 s after "SCRIPT
# ERROR: Parse Error" or "ERROR: Failed to load script", by its own process, not at its time
# limit; its verdict says it was stopped early. Another engine error is not stopped. Named scenes
# run alone and keep the other scenes' times; net_test is refused. A fake project (tests/run.sh
# and its helpers copied) and a fake godot, so no Godot runs here. tests/run.ps1 the same (read).
set -u
cd "$(dirname "$0")/.."
tmp="$(mktemp -d -t run_parse.XXXXXX)"
# The fake's own processes, by the pids it wrote, should a stop have missed them.
trap 'for f in "$tmp"/pids/*; do [ -f "$f" ] && kill -9 "$(cat "$f")" 2>/dev/null; done; rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi
}

mkdir -p "$tmp/p/tests" "$tmp/p/tools" "$tmp/p/.godot" "$tmp/pids"
cp tests/run.sh tests/jobs.sh tests/godot_log.sh "$tmp/p/tests/"
for s in parse late err fine other; do : >"$tmp/p/tests/${s}_test.tscn"; done
# The fake godot. parse: the parse lines, then idles (its idle's pid kept, to see it stopped);
# late: a parse line, then ends within the grace; err: another engine error, finishing at 5 s.
cat >"$tmp/godot" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do case "\$arg" in *.tscn) scene="\$arg" ;; esac; done
echo "Godot Engine v4.7.2.stable.official - https://godotengine.org"
case "\$scene" in
*parse_test.tscn)
	echo "SCRIPT ERROR: Parse Error: There is already a variable named \"far\" declared in this scope."
	echo "   at: GDScript::reload (res://tests/parse_test.gd:12)"
	echo "ERROR: Failed to load script \"res://tests/parse_test.gd\" with error \"Parse error\"."
	sleep 600 &
	echo \$! >"$tmp/pids/idle"
	echo \$\$ >"$tmp/pids/godot"
	wait ;;
*late_test.tscn)
	echo "ERROR: Failed to load script \"res://x.gd\" with error \"Parse error\"."
	echo "RESULT: FAIL (0 failed)"; exit 1 ;;
*err_test.tscn)
	echo "ERROR: a sound bus was missing"
	sleep 5
	echo "RESULT: PASS (0 failed)"; exit 0 ;;
*)
	echo "  PASS  all well"; echo "RESULT: PASS (0 failed)"; exit 0 ;;
esac
EOF
chmod +x "$tmp/godot"
run() { (cd "$tmp/p" && GODOT_PATH="$tmp/godot" PSYKINETIC_TEST_JOBS=4 bash tests/run.sh "$@" 2>&1); }

started=$(date +%s)
out="$(run)"; code=$?
took=$(( $(date +%s) - started ))
check $([ $code = 1 ] && [ "$took" -lt 60 ]; echo $?) "the suite ends in ${took}s, not at the parse scene's limit (300 s)"
verdict="$(printf '%s\n' "$out" | grep -m 1 '^FAIL  parse_test ')"
check $(printf '%s' "$verdict" | grep -q "a parse error: stopped early, 3s after it, the rest of the scene not run: SCRIPT ERROR: Parse Error: There is already"; echo $?) \
	"its verdict says stopped early, naming the line ($verdict)"
secs="$(printf '%s' "$verdict" | sed -n 's/^FAIL  parse_test \([0-9]*\)s:.*/\1/p')"
check $([ -n "$secs" ] && [ "$secs" -ge 3 ] && [ "$secs" -le 20 ]; echo $?) "stopped 3 s after the line (${secs:-?}s in all)"
sleep 1
check $(! kill -0 "$(cat "$tmp/pids/godot" 2>/dev/null || echo 999999)" 2>/dev/null && ! kill -0 "$(cat "$tmp/pids/idle" 2>/dev/null || echo 999999)" 2>/dev/null; echo $?) \
	"its process and the one under it are gone"
check $(printf '%s\n' "$out" | grep -q '^FAIL  late_test [0-9]*s: an engine error: ERROR: Failed to load script'; echo $?) \
	"a scene that ends within the grace: its own verdict, not stopped"
check $(printf '%s\n' "$out" | grep -qE '^FAIL  err_test ([5-9]|[1-9][0-9])s: an engine error: ERROR: a sound bus was missing'; echo $?) \
	"another engine error: not stopped, runs to its end (5 s)"
check $(printf '%s\n' "$out" | grep -q '^PASS  fine_test '; echo $?) "a scene that passes, passes"
check $(printf '%s\n' "$out" | sed -n '/^SUITE: FAIL/,$p' | grep -q "Parse Error"; echo $?) "the summary's digest carries the parse line"

printf '40 tests/other_test.tscn\n30 tests/kept_test.tscn\n7 tests/parse_test.tscn\n' >"$tmp/p/.godot/test_durations.txt"
out="$(run tests/fine_test.tscn ./tests/other_test.tscn)"; code=$?
check $([ $code = 0 ] && printf '%s\n' "$out" | grep -q '^running 2 scenes' && printf '%s\n' "$out" | grep -q '^SUITE: PASS (2 scenes'; echo $?) \
	"named scenes: only those run"
check $(grep -qx '30 tests/kept_test.tscn' "$tmp/p/.godot/test_durations.txt" && grep -qx '7 tests/parse_test.tscn' "$tmp/p/.godot/test_durations.txt" \
	&& [ "$(grep -c ' tests/other_test.tscn$' "$tmp/p/.godot/test_durations.txt")" = 1 ] \
	&& ! grep -qx '40 tests/other_test.tscn' "$tmp/p/.godot/test_durations.txt" && grep -q ' tests/fine_test.tscn$' "$tmp/p/.godot/test_durations.txt"; echo $?) \
	"named scenes: the others' times kept, theirs replaced"
out="$(run tests/net_test.sh)"; code=$?
check $([ $code = 2 ] && printf '%s' "$out" | grep -q "net_test runs alone as the gate's net kind"; echo $?) "net_test refused"
out="$(run tests/none_test.tscn)"; code=$?
check $([ $code = 2 ] && printf '%s' "$out" | grep -q "no scene tests/none_test.tscn"; echo $?) "a scene that isn't there refused"
out="$(run --fast)"; code=$?
check $([ $code = 2 ]; echo $?) "an unknown argument refused"

# tests/run.ps1 the same where PowerShell is, with a native fake (a .cmd; its idle a ping).
if command -v powershell.exe >/dev/null 2>&1; then
	cp tests/run.ps1 tests/jobs.ps1 tests/godot_log.ps1 "$tmp/p/tests/"
	rm -f "$tmp/p/tests/late_test.tscn" "$tmp/p/tests/err_test.tscn"
	printf '%s\r\n' '@echo off' 'echo %* | findstr /c:"parse_test" >nul && goto parse' \
		'echo   PASS  all well' 'echo RESULT: PASS (0 failed)' 'exit /b 0' ':parse' \
		'echo SCRIPT ERROR: Parse Error: There is already a variable named "far" declared in this scope.' \
		'echo ERROR: Failed to load script "res://tests/parse_test.gd" with error "Parse error".' \
		'ping -n 597 127.0.0.1 >nul' >"$tmp/godot.cmd"
	ps1="$(cygpath -w "$tmp/p/tests/run.ps1")"
	started=$(date +%s)
	(cd "$tmp/p" && GODOT_PATH="$(cygpath -w "$tmp/godot.cmd")" PSYKINETIC_TEST_JOBS=4 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" >"$tmp/ps.out" 2>&1)
	code=$?
	took=$(( $(date +%s) - started ))
	out="$(tr -d '\r' <"$tmp/ps.out")"
	check $([ $code = 1 ] && [ "$took" -lt 90 ]; echo $?) "run.ps1: the suite ends in ${took}s, not at the parse scene's limit"
	check $(printf '%s\n' "$out" | grep -q '^FAIL  parse_test [0-9]*s: a parse error: stopped early, 3s after it, the rest of the scene not run: SCRIPT ERROR: Parse Error'; echo $?) \
		"run.ps1: its verdict says stopped early, naming the line"
	idle="$(powershell.exe -NoProfile -Command "@(Get-CimInstance Win32_Process -Filter \"Name = 'PING.EXE'\" | Where-Object { \$_.CommandLine -like '*-n 597 127.0.0.1*' }).Count" | tr -d '\r')"
	check $([ "$idle" = 0 ]; echo $?) "run.ps1: the scene's process and the one under it are gone ($idle left)"
	printf '40 tests/other_test.tscn\n30 tests/kept_test.tscn\n' >"$tmp/p/.godot/test_durations.txt"
	(cd "$tmp/p" && GODOT_PATH="$(cygpath -w "$tmp/godot.cmd")" PSYKINETIC_TEST_JOBS=4 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" tests/fine_test.tscn >"$tmp/ps.out" 2>&1)
	code=$?
	out="$(tr -d '\r' <"$tmp/ps.out")"
	check $([ $code = 0 ] && printf '%s\n' "$out" | grep -q '^SUITE: PASS (1 scenes' && grep -q ' tests/kept_test.tscn' "$tmp/p/.godot/test_durations.txt"; echo $?) \
		"run.ps1: a named scene alone, the others' times kept"
	(cd "$tmp/p" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" tests/net_test.ps1 >"$tmp/ps.out" 2>&1)
	code=$?
	check $([ $code = 2 ] && grep -q "net_test runs alone" "$tmp/ps.out"; echo $?) "run.ps1: net_test refused"
fi
grep -q "^tool_part run_parse_test bash tests/run_parse_test.sh" tests/land.sh
check $? "tests/land.sh runs this test"
echo
echo "RESULT: $([ $failed = 0 ] && echo PASS || echo FAIL) ($failed failed)"
[ $failed = 0 ]
