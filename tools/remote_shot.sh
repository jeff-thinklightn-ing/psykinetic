#!/usr/bin/env bash
# A shot or clip run on the laptop runner (lenovo-tethys; the coordinator's
# design, 2026-11-08), so a windowed run never takes this machine's screen:
#   tools/remote_shot.sh [--with <local file>]... [--timeout MIN] <sha> <name> -- <godot args>
# 1. D:\psykinetic (a clone with no remote) brought to <sha> by a git bundle
#    (only HEAD..sha when the laptop's HEAD is ours), refused if it has
#    changes; each --with file (a git-ignored shot scene, say) copied to the
#    same path in it; imported (headless, over ssh).
# 2. The game run in the laptop's logged-on session as a one-shot task
#    (an ssh session has no desktop: a window there fails its swapchain),
#    only once the laptop has been idle 5 minutes (never over its user; it
#    gives up with "laptop in use" at the timeout), silent, at 0,0 and
#    1600x900, its user data its own, its host bound to 127.0.0.1 (never open
#    on the tailnet), stopped past the timeout.
# 3. <Dir>\out (and the log) pulled to C:/dev/review/<name>, then the run's
#    folder on the laptop deleted.
# In the godot args, {out} is the run's output folder on the laptop. One run
# at a time (a lock on the laptop). Nothing is passed but the bundle, the
# --with files and the args: no agent, no forwarding, no token.
set -u
HOST="${REMOTE_SHOT_HOST:-jequi@lenovo-tethys}"
ROOT='D:\psykinetic'
RUNS='D:\psykinetic-runs'
TIMEOUT=15
WITH=()
while [ $# -gt 0 ]; do
	case "$1" in
		--with) WITH+=("$2"); shift 2 ;;
		--timeout) TIMEOUT="$2"; shift 2 ;;
		*) break ;;
	esac
done
[ $# -ge 3 ] && [ "$3" = "--" ] || { echo "usage: remote_shot.sh [--with FILE]... [--timeout MIN] <sha> <name> -- <godot args>"; exit 2; }
SHA="$(git rev-parse --verify "$1^{commit}")" || exit 2
NAME="$2"
shift 3
case "$NAME" in *[!A-Za-z0-9_-]*|"") echo "name: letters, digits, _ and - only"; exit 2 ;; esac
DIR="$RUNS\\$NAME"
OUT_FWD="D:/psykinetic-runs/$NAME/out"  # Forward slashes: a bash replacement eats backslashes.
REVIEW="C:/dev/review/$NAME"
SSH=(ssh -o BatchMode=yes -o ForwardAgent=no -o ClearAllForwardings=yes -o ConnectTimeout=15 "$HOST")
SCP=(scp -q -o BatchMode=yes -o ForwardAgent=no -o ClearAllForwardings=yes)
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
# The --with files checked before the laptop is touched (828): each a file named on the line,
# in this tree, never a credential, a token or the box's.
WITH_REL=()
for file in "${WITH[@]}"; do
	# (realpath --relative-to gives an absolute path under Git Bash.)
	[ -f "$file" ] || { echo "--with $file: a file named on the line, not a folder or a glob"; exit 2; }
	# Never a token or a credential, nor anything off the box (828): by name, then by what it holds.
	case "$(basename "$file" | tr 'A-Z' 'a-z')" in
		.env*|*.env|*.key|*.pem|*.pfx|*.p12|id_*|*token*|*secret*|*credential*|*password*|*freesound*|override.cfg|project.godot|world.json|mind.log|*.jsonl)
			echo "--with $file: refused (a credential, a token or the box's: never sent)"; exit 2 ;;
	esac
	if grep -qiE '(api[_-]?key|token|secret|password|passwd|private key)[^a-z]{0,4}[:=]' "$file"; then
		echo "--with $file: refused (it holds what reads as a key or a token)"; exit 2
	fi
	# Both in one form: Git Bash's pwd gives C:/... or /c/... by how it got there.
	abs="$(cygpath -u "$(cd "$(dirname "$file")" && pwd)/$(basename "$file")")"
	rel="${abs#"$(cygpath -u "$here")"/}"
	case "$rel" in /*) echo "--with $file: not in this tree"; exit 2 ;; esac
	WITH_REL+=("$rel")
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# The laptop's paths for scp (forward slashes).
fwd() { printf '%s' "$1" | tr '\\' '/'; }
helper="$RUNS\\remote_shot_run.ps1"
rps() { "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File $helper $*"; }

# The game's args: {out} filled in, and the host bound to 127.0.0.1 after the game's "--".
ARGS=()
dashed=0
for arg in "$@"; do
	[ "$arg" = "--" ] && dashed=1
	ARGS+=("${arg//\{out\}/$OUT_FWD}")
done
[ $dashed -eq 1 ] || ARGS+=("--")
ARGS+=("--bind=127.0.0.1")
printf '%s\n' "${ARGS[@]}" >"$TMP/args.txt"

"${SSH[@]}" "if not exist $RUNS mkdir $RUNS" >/dev/null || { echo "laptop not reachable"; exit 1; }
"${SCP[@]}" tools/remote_shot_run.ps1 "$HOST:$(fwd "$helper")" || exit 1
rps -Mode lock -Dir "$NAME" -StaleMin $((TIMEOUT + 25)) || { echo "the laptop runner is busy"; exit 1; }
release() { rps -Mode unlock >/dev/null 2>&1; }
trap 'release; rm -rf "$TMP"' EXIT

# 1. The clone to <sha>.
state="$("${SSH[@]}" "git -C $ROOT rev-parse HEAD && git -C $ROOT status --porcelain --untracked-files=no" | tr -d '\r')"
remote_head="$(printf '%s\n' "$state" | head -1)"
if [ "$(printf '%s\n' "$state" | sed -n '2,$p' | grep -c .)" -ne 0 ]; then
	echo "D:\\psykinetic has changes; nothing touched:"; printf '%s\n' "$state" | sed -n '2,$p'; exit 1
fi
if [ "$remote_head" != "$SHA" ]; then
	git update-ref refs/remote-shot/tip "$SHA"
	if git merge-base --is-ancestor "$remote_head" "$SHA" 2>/dev/null; then
		git bundle create -q "$TMP/tip.bundle" "^$remote_head" refs/remote-shot/tip
	else
		git bundle create -q "$TMP/tip.bundle" refs/remote-shot/tip
	fi
	git update-ref -d refs/remote-shot/tip
	"${SCP[@]}" "$TMP/tip.bundle" "$HOST:$(fwd "$RUNS")/tip.bundle" || exit 1
	"${SSH[@]}" "git -C $ROOT fetch -q $RUNS\\tip.bundle refs/remote-shot/tip && git -C $ROOT checkout -q --detach $SHA && del $RUNS\\tip.bundle" || { echo "refresh failed"; exit 1; }
fi
for i in "${!WITH[@]}"; do
	file="${WITH[$i]}"
	rel="${WITH_REL[$i]}"
	# Forward slashes throughout: a backslash before $( stops the substitution.
	to="$(fwd "$ROOT")/$rel"
	"${SSH[@]}" "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force '$(dirname "$to")' | Out-Null\"" >/dev/null \
		|| { echo "--with $file: no folder for it"; exit 1; }
	"${SCP[@]}" "$file" "$HOST:$to" || { echo "--with $file: not copied"; exit 1; }
done
rps -Mode import -TimeoutMin 20 || { echo "import failed"; exit 1; }

# 2. The run, in the logged-on session.
# (cmd: the parentheses keep the mkdir out of the if's body.)
"${SSH[@]}" "(if exist $DIR rmdir /s /q $DIR) & mkdir $DIR" >/dev/null || { echo "no run folder"; exit 1; }
# The run folder (its out and its APPDATA) goes however this ends (828).
trap '"${SSH[@]}" "if exist $DIR rmdir /s /q $DIR" >/dev/null 2>&1; release; rm -rf "$TMP"' EXIT
"${SCP[@]}" "$TMP/args.txt" "$HOST:$(fwd "$DIR")/args.txt" || exit 1
task="psyk_shot_$NAME"
"${SSH[@]}" "schtasks /create /f /tn $task /sc once /st 00:00 /it /rl limited /tr \"powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $helper -Mode run -Dir $DIR -TimeoutMin $TIMEOUT\" >nul && schtasks /run /tn $task >nul" \
	|| { echo "no task (is anyone logged on?)"; exit 1; }
done=""
for _ in $(seq 1 $(((TIMEOUT + 3) * 6))); do
	done="$("${SSH[@]}" "if exist $DIR\\done.txt type $DIR\\done.txt" 2>/dev/null | tr -d '\r')"
	[ -n "$done" ] && break
	sleep 10
done
"${SSH[@]}" "schtasks /delete /f /tn $task" >/dev/null 2>&1
echo "run: ${done:-no answer (no interactive session?)}"

# 3. The frames back, the laptop's copy gone.
mkdir -p "$REVIEW"
"${SCP[@]}" -r "$HOST:$(fwd "$DIR")/out/." "$REVIEW/" 2>/dev/null
"${SCP[@]}" "$HOST:$(fwd "$DIR")/godot.log" "$REVIEW/godot.log" 2>/dev/null
"${SSH[@]}" "rmdir /s /q $DIR" >/dev/null 2>&1
"${SSH[@]}" "if exist $DIR (echo left) else (echo gone)" 2>/dev/null | grep -q gone || echo "warning: $DIR still on the laptop"
ls "$REVIEW"
case "$done" in "exit 0") exit 0 ;; *) exit 1 ;; esac
