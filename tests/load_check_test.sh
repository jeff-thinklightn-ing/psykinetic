#!/usr/bin/env bash
# tools/load_check.sh (278 amended (7)) with a fake Godot, in a throwaway repo: which scripts it
# names (changed against origin/main: committed, staged, unstaged, new; not deleted ones), its
# refusals, and its verdict from the loader's lines. The gate is its own, in a private folder
# (HEAVY_JOBS_DIR), so the live queue never sees it. The real loader's proof is a run on a
# broken script (the decision's paragraph).
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
failed=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; failed=$((failed + 1)); fi; }
work="$(mktemp -d -t load_check_test.XXXXXX)"
trap 'rm -rf "$work"' EXIT
repo="$work/repo"
mkdir -p "$repo/tools" "$repo/sim" "$repo/.godot"
cp "$here/tools/load_check.sh" "$here/tools/heavy_job.sh" "$here/tools/heavy_job.py" "$repo/tools/"
: >"$repo/tools/load_check.gd"
# The fake Godot: reads --log-file and the res:// paths after "--", writes the loader's lines
# there; a path holding $FAKE_FAIL fails with an engine line; FAKE_SILENT writes no verdict.
cat >"$work/godot" <<'EOF'
#!/usr/bin/env bash
log=""; after=0; paths=()
while [ $# -gt 0 ]; do
	case "$1" in
		--log-file) shift; log="$1" ;;
		--) after=1 ;;
		*) [ $after = 1 ] && paths+=("$1") ;;
	esac
	shift
done
command -v cygpath >/dev/null 2>&1 && log="$(cygpath -u "$log")"
printf '%s\n' "${paths[@]}" >"$FAKE_SEEN"
[ -n "${FAKE_SILENT:-}" ] && { echo "Godot Engine" >"$log"; exit 1; }
bad=0
for p in "${paths[@]}"; do
	if [ -n "${FAKE_FAIL:-}" ] && case "$p" in *"$FAKE_FAIL"*) true ;; *) false ;; esac; then
		printf 'SCRIPT ERROR: Parse Error: Cannot infer the type of "x" variable.\n   at: GDScript::reload (%s:3)\nLOAD FAIL %s\n' "$p" "$p" >>"$log"
		bad=$((bad + 1))
	else
		echo "LOAD ok $p" >>"$log"
	fi
done
echo "LOAD_CHECK: $([ $bad -gt 0 ] && echo FAIL || echo PASS) ($bad of ${#paths[@]} scripts failed to load)" >>"$log"
[ $bad -gt 0 ] && exit 1
exit 0
EOF
chmod +x "$work/godot"
cd "$repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf 'extends Node\n' >sim/kept.gd
printf 'extends Node\n' >sim/gone.gd
printf 'extends Node\n' >sim/edited.gd
git add -A && git commit -q -m base && git update-ref refs/remotes/origin/main HEAD
printf 'extends Node\n' >sim/committed.gd
git rm -q sim/gone.gd
git add -A && git commit -q -m take
printf 'extends Node\nvar x\n' >sim/edited.gd
printf 'extends Node\n' >sim/staged.gd && git add sim/staged.gd
printf 'extends Node\n' >sim/new.gd
printf 'not a script\n' >notes.txt
export GODOT_PATH="$work/godot" HEAVY_JOBS_DIR="$work/gate" FAKE_SEEN="$work/seen.txt" PSYKINETIC_TREE=load_check_test
unset HEAVY_JOB_HELD PYTHONIOENCODING

out="$(bash tools/load_check.sh 2>&1)"; code=$?
check $([ $code = 2 ] && printf '%s\n' "$out" | grep -q "not imported"; echo $?) "an unimported checkout: refused, exit 2"
printf '[cache]\n' >.godot/global_script_class_cache.cfg

out="$(bash tools/load_check.sh 2>&1)"; code=$?
seen="$(tr -d '\r' <"$work/seen.txt" | sort | paste -sd ' ' -)"
check $([ $code = 0 ] && [ "$seen" = "res://sim/committed.gd res://sim/edited.gd res://sim/new.gd res://sim/staged.gd" ]; echo $?) \
	"changed against origin/main: committed, unstaged, new and staged; not the deleted or the untouched ($seen)"
check $(printf '%s\n' "$out" | tail -1 | grep -q '^LOAD_CHECK: PASS (0 of 4'; echo $?) "all load: LOAD_CHECK: PASS last, exit 0"
check $(printf '%s\n' "$out" | grep -q '^LOAD ok res://sim/new.gd'; echo $?) "each script's line shown"
check $(grep -q "load_check_test.*load_check" "$work/gate/heavy_jobs.log" 2>/dev/null; echo $?) "it went through the gate as load_check"

out="$(FAKE_FAIL=edited bash tools/load_check.sh 2>&1)"; code=$?
check $([ $code = 1 ] && printf '%s\n' "$out" | tail -1 | grep -q '^LOAD_CHECK: FAIL (1 of 4' \
	&& printf '%s\n' "$out" | grep -q '^SCRIPT ERROR: Parse Error' && printf '%s\n' "$out" | grep -q '^LOAD FAIL res://sim/edited.gd'; echo $?) \
	"a script failing: FAIL, exit 1, with the engine's line and its own"

out="$(bash tools/load_check.sh sim/kept.gd res://sim/new.gd 2>&1)"; code=$?
seen="$(tr -d '\r' <"$work/seen.txt" | paste -sd ' ' -)"
check $([ $code = 0 ] && [ "$seen" = "res://sim/kept.gd res://sim/new.gd" ]; echo $?) "named scripts: those only ($seen)"

out="$(bash tools/load_check.sh notes.txt 2>&1)"; code=$?
check $([ $code = 2 ] && printf '%s\n' "$out" | grep -q "not a .gd script"; echo $?) "a file not a script: refused, exit 2"

out="$(FAKE_SILENT=1 bash tools/load_check.sh sim/kept.gd 2>&1)"; code=$?
check $([ $code = 2 ] && printf '%s\n' "$out" | tail -1 | grep -q '^LOAD_CHECK: FAIL (Godot gave no verdict'; echo $?) \
	"no verdict from Godot: FAIL, exit 2, never a pass"

git reset -q --hard origin/main
rm -f sim/new.gd notes.txt
out="$(bash tools/load_check.sh 2>&1)"; code=$?
check $([ $code = 0 ] && printf '%s\n' "$out" | grep -q '^LOAD_CHECK: PASS (no changed scripts)'; echo $?) "nothing changed: PASS, no Godot"

if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
