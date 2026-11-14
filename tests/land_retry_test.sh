#!/usr/bin/env bash
# tests/land_retry.sh's tool_part (278 amended (8)): a tool part that failed on the temp folder
# runs once more; a failed check, any other failure and the Godot parts never do.
# Run: bash tests/land_retry_test.sh
cd "$(dirname "$0")/.." || exit 1
failed=0
check() {
	if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi
}
scratch="$(mktemp -d -t land_retry_test.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
LOGS="$scratch/logs"
mkdir -p "$LOGS"
LAND_RETRY_WAIT=0
. tests/land_retry.sh

# A fake part: each run counts itself in $scratch/<name>.runs and does what its plan's line for
# that run says (denied: the git line of 11-13 and exit 1; check: a failed check and the denied
# line; other: a plain error; ok: exit 0).
cat >"$scratch/fake.sh" <<'EOF'
name="$1"; dir="$2"
runs=$(( $(cat "$dir/$name.runs" 2>/dev/null || echo 0) + 1 ))
echo "$runs" >"$dir/$name.runs"
what="$(sed -n "${runs}p" "$dir/$name.plan")"
case "$what" in
	denied) echo "RuntimeError: git add -A: error: unable to write file .git/objects/b9/be7b: Permission denied"; exit 1 ;;
	access) echo "OSError: [WinError 5] Access is denied: 'C:\\Temp\\x'"; exit 1 ;;
	check) echo "  FAIL  the bullet kept"; echo "error: unable to write file .git/objects/aa: Permission denied"; exit 1 ;;
	other) echo "Traceback: KeyError 'load_check'"; exit 1 ;;
	*) echo "  PASS  all"; exit 0 ;;
esac
EOF
run() {  # run <name> <plan lines...>: tool_part's output into $scratch/<name>.out
	name="$1"; shift
	printf '%s\n' "$@" >"$scratch/$name.plan"
	tool_part "$name" bash "$scratch/fake.sh" "$name" "$scratch" >"$scratch/$name.out"
}
runs() { cat "$scratch/$1.runs"; }
status() { cut -d' ' -f1 "$LOGS/$1.status"; }

echo "== denied once, then it passes =="
run once denied ok
check $([ "$(runs once)" = 2 ] && [ "$(status once)" = 0 ]; echo $?) "run twice, the rerun's exit is the part's (runs $(runs once), status $(status once))"
check $(grep -q "^retried: once (temp folder: .*Permission denied" "$scratch/once.out"; echo $?) "the retried line, with the line that caused it: $(head -1 "$scratch/once.out")"
check $(grep -q "^PASS  once " "$scratch/once.out"; echo $?) "then PASS"
check $([ -f "$LOGS/once.first.log" ] && grep -q "Permission denied" "$LOGS/once.first.log" && grep -q "PASS  all" "$LOGS/once.log"; echo $?) "the first log kept as once.first.log, the rerun's as once.log"
check $([ "$(land_retried)" = "; retried: once (temp folder)" ]; echo $?) "the result line's note: '$(land_retried)'"

echo "== Access is denied (Windows' own wording) =="
run access access ok
check $([ "$(runs access)" = 2 ] && [ "$(status access)" = 0 ]; echo $?) "retried and passed"

echo "== a failed check beside the denied line: never retried =="
run check check ok
check $([ "$(runs check)" = 1 ] && [ "$(status check)" = 1 ] && [ ! -f "$LOGS/check.retried" ]; echo $?) "run once, FAIL, no retried line"

echo "== any other failure: never retried =="
run other other ok
check $([ "$(runs other)" = 1 ] && [ "$(status other)" = 1 ]; echo $?) "run once, FAIL"

echo "== denied twice: retried once, then it fails =="
run twice denied denied ok
check $([ "$(runs twice)" = 2 ] && [ "$(status twice)" = 1 ]; echo $?) "run twice, not three times, FAIL"
check $(grep -q "^FAIL  twice " "$scratch/twice.out"; echo $?) "FAIL printed"

echo "== a pass is run once =="
run plain ok
check $([ "$(runs plain)" = 1 ] && [ "$(status plain)" = 0 ] && [ ! -f "$LOGS/plain.retried" ]; echo $?) "run once, PASS"
check $([ "$(land_retried)" = "; retried: access once twice (temp folder)" ]; echo $?) "the note names every retried part, sorted: '$(land_retried)'"
rm -f "$LOGS"/*.retried
check $([ -z "$(land_retried)" ]; echo $?) "no retry: no note"

echo "== land.sh =="
godot="$(grep -nE '^\s*tool_part (suite|net_test|state_test|server_boot_test|remote_prepare)( |$)' tests/land.sh)"
check $([ -z "$godot" ]; echo $?) "no Godot part goes through tool_part${godot:+: $godot}"
for name in suite net_test state_test server_boot_test remote_prepare; do
	check $(grep -qE "^\s*part $name( |$)" tests/land.sh; echo $?) "$name runs through part()"
done
plain="$(grep -nE '^\s*part [a-z_]*(_test|font_import) (python|bash)' tests/land.sh | grep -vE '^[0-9]+:\s*part (suite|net_test|state_test|server_boot_test|remote_prepare) ')"
check $([ -z "$plain" ]; echo $?) "every tool part goes through tool_part${plain:+: $plain}"
checks_exit=$(awk '/^if \[ "\$\{1:-\}" = "--checks" \]; then/{c=1} c&&/^fi$/{print NR; exit}' tests/land.sh)
first_tool=$(grep -nE '^\s*tool_part ' tests/land.sh | head -1 | cut -d: -f1)
check $([ -n "$checks_exit" ] && [ -n "$first_tool" ] && [ "$checks_exit" -lt "$first_tool" ] \
	&& sed -n "1,${checks_exit}p" tests/land.sh | awk '/--checks/{c=1} c' | grep -q '^	exit 1$'; echo $?) \
	"--checks ends (line $checks_exit) before the first tool part (line $first_tool): never retried there"
check $(grep -c 'voice_inventory_test\$retried; ' tests/land.sh | grep -qx 1 && grep -q 'FAIL (\$failed\$retried; ' tests/land.sh; echo $?) \
	"the PASS and FAIL lines carry the note"

echo
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"
exit 1
