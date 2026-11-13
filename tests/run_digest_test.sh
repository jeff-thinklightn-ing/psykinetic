#!/usr/bin/env bash
# tests/run.sh's summary names a failed scene's failure (278 amended (4)): after "SUITE: FAIL"
# each failed scene's verdict, then its failed checks, every engine error with the two lines
# after it and its RESULT line, at most 40, so a reader's tail finds the check however long the
# scene's output. A fake project (tests/run.sh and its helpers copied) and a fake godot, so no
# Godot runs here. tests/run.ps1 the same (read here, not run).
set -u
cd "$(dirname "$0")/.."
tmp="$(mktemp -d -t run_digest.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi
}

mkdir -p "$tmp/p/tests" "$tmp/p/tools" "$tmp/p/.godot"
cp tests/run.sh tests/jobs.sh tests/godot_log.sh "$tmp/p/tests/"
: >"$tmp/p/tests/long_test.tscn"; : >"$tmp/p/tests/many_test.tscn"; : >"$tmp/p/tests/fine_test.tscn"
# The fake godot: long_test fails one check 800 lines up and logs an engine error; many_test
# fails 60 checks; fine_test passes.
cat >"$tmp/godot" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in *.tscn) scene="$arg" ;; esac; done
echo "Godot Engine v4.7.2.stable.official - https://godotengine.org"
case "$scene" in
*long_test.tscn)
	for i in $(seq 1 30); do echo "  PASS  early check $i"; done
	echo "  FAIL  five trade cues at once: the last plays (3 fading, 2 left)"
	echo "ERROR: a sound bus was missing"
	echo "   at: push_error (core/variant/variant_utility.cpp:1024)"
	echo "   GDScript backtrace (most recent call first):"
	for i in $(seq 1 800); do echo "  PASS  later check $i"; done
	echo "RESULT: FAIL (1 failed)"; exit 1 ;;
*many_test.tscn)
	for i in $(seq 1 60); do echo "  FAIL  many $i"; done
	echo "RESULT: FAIL (60 failed)"; exit 1 ;;
*)
	echo "  PASS  all well"; echo "RESULT: PASS (0 failed)"; exit 0 ;;
esac
EOF
chmod +x "$tmp/godot"
out="$(cd "$tmp/p" && GODOT_PATH="$tmp/godot" PSYKINETIC_TEST_JOBS=2 bash tests/run.sh 2>&1)"; code=$?
summary="$(printf '%s\n' "$out" | sed -n '/^SUITE: FAIL/,$p')"
check $([ $code = 1 ] && printf '%s' "$summary" | grep -q "^SUITE: FAIL (2 of 3 failed"; echo $?) "the suite fails, two of three scenes"
check $(printf '%s\n' "$summary" | grep -qxF "  FAIL  five trade cues at once: the last plays (3 fading, 2 left)"; echo $?) \
	"the summary names the check that failed 800 lines up"
check $(printf '%s\n' "$summary" | grep -A2 -xF "ERROR: a sound bus was missing" | grep -qF "GDScript backtrace"; echo $?) \
	"an engine error with the two lines after it"
check $(printf '%s\n' "$summary" | grep -qxF "RESULT: FAIL (1 failed)"; echo $?) "the failed scene's RESULT line"
check $(! printf '%s\n' "$summary" | grep -qE "later check|early check|all well"; echo $?) "no PASS line and nothing of the scene that passed"
check $([ "$(printf '%s\n' "$summary" | grep -c '^  FAIL  many ')" = 40 ]; echo $?) "at most 40 lines a scene ($(printf '%s\n' "$summary" | grep -c '^  FAIL  many ') of 60 failed checks)"
grep -q '^function Get-Digest' tests/run.ps1 && grep -qF 'Get-Digest (Join-Path $logs' tests/run.ps1
check $? "tests/run.ps1 prints the same digest in its summary"
grep -q "^part run_digest_test bash tests/run_digest_test.sh" tests/land.sh
check $? "tests/land.sh runs this test"
echo
echo "RESULT: $([ $failed = 0 ] && echo PASS || echo FAIL) ($failed failed)"
[ $failed = 0 ]
