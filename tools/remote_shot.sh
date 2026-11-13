#!/usr/bin/env bash
# A shot or clip run on the laptop runner (lenovo-tethys; the coordinator's
# design, 2026-11-08), so a windowed run never takes this machine's screen:
#   tools/remote_shot.sh [--runner lenovo|atlas] [--with <local file>]... [--timeout MIN] [--repeat N] [--vsync off|default]
#     [--joined [--server-args "ARGS"]] <sha> <name> -- <godot args>
# --vsync (828 amended (5)): off by default, the engine's --disable-vsync put first in the
# godot args, so a run's timing is the game's and not the laptop's present: the Atlas holds
# each frame 200 to 500 ms with vsync on (3.5 fps against 204 with it off, the same full
# world, 11-12; the Lenovo is unaffected), so a vsync-on run there plays the game clock at a
# third of its speed. --vsync default keeps the game's own setting, for a run that is about
# what a player gets. runner.log in the review folder ends with which ("SHOT vsync: off").
# --repeat N: the game run N times in a row with the same user data (the second
# starts after the first has exited and saved its caches: a player's next
# session); pass n's log comes back as out/godot-n.log.
# --runner: lenovo (lenovo-tethys, its clone on D:, the default) or atlas
# (asus-atlas, the low-spec player machine, C: only); D: below is the runner's drive.
# 1. D:\psykinetic (a clone with no remote) brought to <sha> by a git bundle
#    (only HEAD..sha when the laptop's HEAD is ours), refused if it has
#    changes. An untracked *.uid or *.import that <sha> tracks (the laptop's own
#    import made it first) is removed and named; any other untracked file <sha>
#    tracks refuses the run (828 amended (3)). Each --with file (a git-ignored shot scene, say) copied to the
#    same path in it; imported (headless, over ssh).
# 2. The game run in the laptop's logged-on session as a one-shot task
#    (an ssh session has no desktop: a window there fails its swapchain),
#    at once, on the laptop's screen in front without taking focus (Jeff,
#    2026-11-09: "i want the visuals to show up on screen when the screen is
#    on so i can see what being done"), the display kept on, silent, at 0,0
#    and 1600x900 or the screen's size, its user data its own, its host bound
#    to 127.0.0.1 (never open on the tailnet), stopped past the timeout or
#    from its tray icon ("stopped by user"). runner.log says whether the
#    laptop was used during the run and its power (mains, scheme, GPU state)
#    at start and end: a bench's caller says whether its timings count.
#    <Dir>\shown.txt appears once the window is up.
# 3. <Dir>\out (and the log) pulled to C:/dev/review/<name>, then the run's
#    folder on the laptop deleted.
# In the godot args, {out} is the run's output folder on the laptop. One run
# at a time (a lock on the laptop). Nothing is passed but the bundle, the
# --with files and the args: no agent, no forwarding, no token.
# No mode after the game's "--" gets --host (828 amended (2)): with none, a
# fresh settings file waits as a client behind the connect screen. A locked
# laptop is refused at once, and so are window and path flags and test scenes.
# A bench's worst frame on the Atlas: a stray ~450 ms frame now and then is the
# laptop's own (perf, 2026-11-12: 5 of 9 wilds runs on the Atlas, 0 of 5 on the
# Lenovo; the one caught spent ~420 ms outside everything the engine times, with
# nothing built). A bench whose worst frame matters runs on the Lenovo (--runner
# lenovo), and map_bench's --hitch-ms=N says what a long frame did.
# --joined (828 amended (4)): the game joins a server as a client, both on the laptop.
# The runner starts the game headless as `--server --bind 127.0.0.1` on a free
# loopback port first, with a user folder of its own in the run's folder (a fresh
# world: no state file, nothing of the box's, no player's id), waits for its
# "listening" line, and checks its sockets: one bound past loopback stops the run
# ("beyond loopback"; never a firewall rule). Then the windowed game as
# `--client --address=127.0.0.1 --port=P`. --server-args "<args>" go to the server
# alone (its clock, its map: --hour=21 --map=wilds), split on spaces. A joined run's
# args name no mode, address or port (it joins 127.0.0.1 and nothing else).
# out/server.log comes back with the rest. Every run's processes, joined or not,
# are in a job object that Windows ends with the runner: a tray stop, a timeout,
# the client's crash or the runner's own end take the server with them.
set -u
RUNNER=lenovo
REPEAT=1
TIMEOUT=15
WITH=()
VSYNC=off
JOINED=0
SERVER_ARGS=""
while [ $# -gt 0 ]; do
	case "$1" in
		--with) WITH+=("$2"); shift 2 ;;
		--timeout) TIMEOUT="$2"; shift 2 ;;
		--runner) RUNNER="$2"; shift 2 ;;
		--repeat) REPEAT="$2"; shift 2 ;;
		--vsync) VSYNC="$2"; shift 2 ;;
		--joined) JOINED=1; shift ;;
		--server-args) SERVER_ARGS="$2"; shift 2 ;;
		*) break ;;
	esac
done
[ $# -ge 3 ] && [ "$3" = "--" ] || { echo "usage: remote_shot.sh [--runner lenovo|atlas] [--with FILE]... [--timeout MIN] [--repeat N] [--vsync off|default] [--joined [--server-args \"ARGS\"]] <sha> <name> -- <godot args>"; exit 2; }
[ -z "$SERVER_ARGS" ] || [ $JOINED -eq 1 ] || { echo "--server-args: only with --joined"; exit 2; }
# Each runner: its ssh address, the drive its clone and runs are on, and the
# shell its ssh server starts (atlas's is PowerShell; every line here is cmd's).
case "$REPEAT" in [1-5]) ;; *) echo "repeat: 1 to 5"; exit 2 ;; esac
case "$VSYNC" in off|default) ;; *) echo "vsync: off or default"; exit 2 ;; esac
case "$RUNNER" in
	lenovo) HOST=jequi@lenovo-tethys; DRIVE=D; SHELL_KIND=cmd ;;
	atlas) HOST=jequi@asus-atlas; DRIVE=C; SHELL_KIND=powershell ;;
	*) echo "runner: lenovo or atlas"; exit 2 ;;
esac
ROOT="$DRIVE:\\psykinetic"
RUNS="$DRIVE:\\psykinetic-runs"
SHA="$(git rev-parse --verify "$1^{commit}")" || exit 2
NAME="$2"
shift 3
case "$NAME" in *[!A-Za-z0-9_-]*|"") echo "name: letters, digits, _ and - only"; exit 2 ;; esac
DIR="$RUNS\\$NAME"
OUT_FWD="$DRIVE:/psykinetic-runs/$NAME/out"  # Forward slashes: a bash replacement eats backslashes.
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
# The runner's copy is this run's own (828 amended (4)): one shared copy was written by every
# remote_shot before it asks for the laptop's lock, so a tree waiting on the lock replaced the
# runner under a run that held it, and that run's task started another tree's runner (main's,
# which had no -Joined: four joined proofs ended in a parameter error before a line ran, 11-12).
# A short random name (8 hex), not the run's: schtasks /tr holds 261 characters and the run's
# name is in it once already (-Dir).
helper="$RUNS\\r-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n').ps1"
drop_helper() { rsh "if exist $helper del /q $helper" >/dev/null 2>&1; }
# A cmd line run on the runner. Where its ssh server starts PowerShell, the line
# goes as base64 inside a -EncodedCommand script that hands it to cmd.exe as it is
# (no quoting of PowerShell's between), its exit code back.
rsh() {
	if [ "$SHELL_KIND" = cmd ]; then
		"${SSH[@]}" "$1"
		return
	fi
	local line script
	line="$(printf '%s' "$1" | base64 -w0)"
	script="\$ProgressPreference = 'SilentlyContinue'; \$i = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe'; \$i.Arguments = '/c ' + [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$line')); \$i.UseShellExecute = \$false; \$p = [Diagnostics.Process]::Start(\$i); \$p.WaitForExit(); exit \$p.ExitCode"
	"${SSH[@]}" "powershell -NoProfile -NonInteractive -EncodedCommand $(printf '%s' "$script" | iconv -f utf-8 -t utf-16le | base64 -w0)"
}
rps() { rsh "powershell -NoProfile -ExecutionPolicy Bypass -File $helper -Root $ROOT -Runs $RUNS $*"; }

# The game's args: {out} filled in, and the host bound to 127.0.0.1 after the game's "--".
# The runner sets the window, the path and the audio itself, and a test scene runs headless in
# the suite, never on a laptop (828 amended (2)): refused before the laptop is touched.
ARGS=()
dashed=0
moded=0
for arg in "$@"; do
	if [ "$arg" = "--" ] && [ $dashed -eq 0 ]; then
		dashed=1
	elif [ $dashed -eq 0 ]; then
		case "$arg" in
			--headless|--path|--path=*|--position|--position=*|--resolution|--resolution=*|--fullscreen|--maximized)
				echo "$arg: refused (the runner sets the window and the path; a laptop run is windowed)"; exit 2 ;;
			res://tests/*|tests/*)
				echo "$arg: refused (a test scene runs headless in the suite, not on a laptop)"; exit 2 ;;
			--disable-vsync)
				echo "$arg: refused (remote_shot's --vsync says it)"; exit 2 ;;
		esac
	else
		# A mode named after the game's "--" (Net._parse_args); --menu wants the menu on purpose.
		case "$arg" in --host|--client|--server|--practice|--menu) moded=1 ;; esac
		# Joined: the runner names the mode, the address and the port, 127.0.0.1 only (828 amended (4)).
		if [ $JOINED -eq 1 ]; then
			case "$arg" in
				--host|--client|--server|--practice|--menu|--address|--address=*|--port|--port=*|--bind|--bind=*|--token|--token=*)
					echo "$arg: refused (a joined run joins its own server on 127.0.0.1; the runner names the mode, address and port)"; exit 2 ;;
			esac
		fi
	fi
	ARGS+=("${arg//\{out\}/$OUT_FWD}")
done
[ $dashed -eq 1 ] || ARGS+=("--")
# No mode named: a fresh settings file joins 127.0.0.1 as a client, finds no server and waits
# behind the connect screen, so a bench times that screen and a shot finds no player (11-10).
# A joined run's client mode comes from the runner, with the server's port.
if [ $moded -eq 0 ] && [ $JOINED -eq 0 ]; then
	ARGS+=("--host")
	echo "remote_shot: no mode named (--host, --client, --server, --practice or --menu): added --host"
fi
ARGS+=("--bind=127.0.0.1")
# 828 amended (5): vsync off unless --vsync default, an engine arg (before the game's "--").
[ "$VSYNC" = off ] && ARGS=("--disable-vsync" "${ARGS[@]}")
echo "SHOT vsync: $VSYNC"
printf '%s\n' "${ARGS[@]}" >"$TMP/args.txt"
# The server's own args (828 amended (4)): the world it makes, nothing that reaches out
# (no address, port, bind, state, token, admin, model or log): an allowlist, each --key=value.
: >"$TMP/server_args.txt"
if [ $JOINED -eq 1 ]; then
	read -r -a server_words <<<"$SERVER_ARGS"
	for arg in "${server_words[@]}"; do
		case "$arg" in
			--hour=*|--map=*|--day-minutes=*|--weather=*|--season=*|--season-days=*|--max-players=*|--no-companions|--still-monsters)
				printf '%s\n' "$arg" >>"$TMP/server_args.txt" ;;
			*) echo "--server-args $arg: refused (the server takes --hour, --map, --day-minutes, --weather, --season, --season-days, --max-players as --key=value, and --no-companions, --still-monsters)"; exit 2 ;;
		esac
	done
fi

rsh "if not exist $RUNS mkdir $RUNS" >/dev/null || { echo "laptop not reachable"; exit 1; }
# Locked (or at its logon screen): the task would never show a window, and the run would wait
# out its whole timeout for nothing (atlas, 11-10). Refused at once.
if rsh "tasklist /nh /fi \"imagename eq LogonUI.exe\" | find /i \"LogonUI.exe\"" >/dev/null 2>&1; then
	echo "the laptop is locked (LogonUI runs): nothing run; ask Jeff to unlock it"; exit 1
fi
"${SCP[@]}" tools/remote_shot_run.ps1 "$HOST:$(fwd "$helper")" || exit 1
rps -Mode lock -Dir "$NAME" -StaleMin $((TIMEOUT + 25)) || { echo "the laptop runner is busy"; drop_helper; exit 1; }
release() { rps -Mode unlock >/dev/null 2>&1; drop_helper; }
trap 'release; rm -rf "$TMP"' EXIT
# A crashed run's runner copy is swept by the next run holding the lock: r-*.ps1 last written
# before yesterday (forfiles' whole days; a run lasts under an hour, so none is in use).
rsh "forfiles /p $RUNS /m r-*.ps1 /d -1 /c \"cmd /c del /q @path\"" >/dev/null 2>&1
# The runner this run copied, by its hash: runner.log names the copy that ran, and the two match.
RUNNER_SHA="$(sha256sum tools/remote_shot_run.ps1 | cut -c1-16)"
echo "runner: $(fwd "$helper"), sha256 $RUNNER_SHA"

# 1. The clone to <sha>.
state="$(rsh "git -C $ROOT rev-parse HEAD && git -C $ROOT status --porcelain --untracked-files=no" | tr -d '\r')"
remote_head="$(printf '%s\n' "$state" | head -1)"
if [ "$(printf '%s\n' "$state" | sed -n '2,$p' | grep -c .)" -ne 0 ]; then
	echo "$ROOT has changes; nothing touched:"; printf '%s\n' "$state" | sed -n '2,$p'; exit 1
fi
if [ "$remote_head" != "$SHA" ]; then
	# Untracked files there that <sha> tracks would stop the checkout (828 amended
	# (3)): a generated one (*.uid, *.import, the laptop's own import wrote it before
	# its tree committed it) is removed and named; anything else refuses the run.
	. "$here/tools/remote_shot_clash.sh"
	git ls-tree -r --name-only "$SHA" > "$TMP/tracked.txt"
	rsh "git -C $ROOT ls-files --others --exclude-standard" | tr -d '\r' > "$TMP/untracked.txt" \
		|| { echo "the clone's untracked files could not be listed; nothing touched"; exit 1; }
	clashes "$TMP/tracked.txt" "$TMP/untracked.txt" > "$TMP/clashes.txt"
	if grep -q '^stop ' "$TMP/clashes.txt"; then
		echo "$ROOT has untracked files $SHA tracks, not generated ones; nothing touched:"
		sed -n 's/^stop //p' "$TMP/clashes.txt"; exit 1
	fi
	sed -n 's/^remove //p' "$TMP/clashes.txt" | while IFS= read -r path; do
		rsh "del /q \"$ROOT\\$(printf '%s' "$path" | tr '/' '\\')\"" >/dev/null || { echo "could not remove $path"; exit 1; }
		echo "remote_shot: removed $ROOT's untracked $path, which $SHA tracks (a generated file; 828 amended (3))"
	done || exit 1
	git update-ref refs/remote-shot/tip "$SHA"
	if git merge-base --is-ancestor "$remote_head" "$SHA" 2>/dev/null; then
		git bundle create -q "$TMP/tip.bundle" "^$remote_head" refs/remote-shot/tip
	else
		git bundle create -q "$TMP/tip.bundle" refs/remote-shot/tip
	fi
	git update-ref -d refs/remote-shot/tip
	"${SCP[@]}" "$TMP/tip.bundle" "$HOST:$(fwd "$RUNS")/tip.bundle" || exit 1
	rsh "git -C $ROOT fetch -q $RUNS\\tip.bundle refs/remote-shot/tip && git -C $ROOT checkout -q --detach $SHA && del $RUNS\\tip.bundle" || { echo "refresh failed"; exit 1; }
fi
for i in "${!WITH[@]}"; do
	file="${WITH[$i]}"
	rel="${WITH_REL[$i]}"
	# Forward slashes throughout: a backslash before $( stops the substitution.
	to="$(fwd "$ROOT")/$rel"
	rsh "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force '$(dirname "$to")' | Out-Null\"" >/dev/null \
		|| { echo "--with $file: no folder for it"; exit 1; }
	"${SCP[@]}" "$file" "$HOST:$to" || { echo "--with $file: not copied"; exit 1; }
done
rps -Mode import -TimeoutMin 20 || { echo "import failed"; exit 1; }

# 2. The run, in the logged-on session.
# (cmd: the parentheses keep the mkdir out of the if's body.)
rsh "(if exist $DIR rmdir /s /q $DIR) & mkdir $DIR" >/dev/null || { echo "no run folder"; exit 1; }
# The run folder (its out and its APPDATA) and its task go however this ends (828; the task
# since 828 amended (2): a stopped run left psyk_shot_<name> on the laptop).
task="psyk_shot_$NAME"
trap 'rsh "schtasks /delete /f /tn $task" >/dev/null 2>&1; rsh "if exist $DIR rmdir /s /q $DIR" >/dev/null 2>&1; release; rm -rf "$TMP"' EXIT
"${SCP[@]}" "$TMP/args.txt" "$HOST:$(fwd "$DIR")/args.txt" || exit 1
joined_flag=""
if [ $JOINED -eq 1 ]; then
	"${SCP[@]}" "$TMP/server_args.txt" "$HOST:$(fwd "$DIR")/server_args.txt" || exit 1
	joined_flag=" -Joined"
fi
# (2>nul: schtasks warns that /ST 00:00 is past; the task is run at once by /run.)
rsh "schtasks /create /f /tn $task /sc once /st 00:00 /it /rl limited /tr \"powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $helper -Root $ROOT -Runs $RUNS -Mode run -Dir $DIR -TimeoutMin $TIMEOUT -Repeat $REPEAT$joined_flag\" >nul 2>nul && schtasks /run /tn $task >nul" \
	|| { echo "no task (is anyone logged on?)"; exit 1; }
done=""
for _ in $(seq 1 $(((TIMEOUT + 3) * 6))); do
	done="$(rsh "if exist $DIR\\done.txt type $DIR\\done.txt" 2>/dev/null | tr -d '\r')"
	[ -n "$done" ] && break
	sleep 10
done
rsh "schtasks /delete /f /tn $task" >/dev/null 2>&1
echo "run: ${done:-no answer (no interactive session?)}"

# 3. The frames back, the laptop's copy gone.
mkdir -p "$REVIEW"
"${SCP[@]}" -r "$HOST:$(fwd "$DIR")/out/." "$REVIEW/" 2>/dev/null
"${SCP[@]}" "$HOST:$(fwd "$DIR")/godot.log" "$REVIEW/godot.log" 2>/dev/null
rsh "rmdir /s /q $DIR" >/dev/null 2>&1
rsh "if exist $DIR (echo left) else (echo gone)" 2>/dev/null | grep -q gone || echo "warning: $DIR still on the laptop"
printf 'SHOT vsync: %s\n' "$VSYNC" >>"$REVIEW/runner.log"
ls "$REVIEW"
# The runner that ran is the one sent (828 amended (4)), else this run's numbers and stills are
# another tool's: said, and the run fails.
ran_sha="$([ -f "$REVIEW/runner.log" ] && tr -d '\357\273\277\r' < "$REVIEW/runner.log" | sed -n 's/^runner: .*, sha256 \([0-9a-f]*\)$/\1/p' | tail -1)"
if [ -n "$ran_sha" ] && [ "$ran_sha" != "$RUNNER_SHA" ]; then
	echo "remote_shot: the runner that ran (sha256 $ran_sha) is not the one sent ($RUNNER_SHA): this run's results are another tool's"; exit 1
fi
# A joined run's client that never joined its server: the connect screen over whatever it drew;
# its stills are void (828 amended (4)). runner.log's joined lines say why.
if [ $JOINED -eq 1 ]; then
	grep -h "^joined\|^server" "$REVIEW/runner.log" 2>/dev/null
	if ! grep -q "\[net\] connected as peer" "$REVIEW/godot.log" 2>/dev/null; then
		echo "remote_shot: the joined client never connected to its server: its stills are void"; exit 1
	fi
# A game that joined as a client and never hosted, unless --client was asked: no level of its own,
# the connect screen over whatever it drew; its numbers and stills are void (828 amended (2)).
elif ! printf '%s\n' "${ARGS[@]}" | grep -qx -- "--client"; then
	if grep -q "client connecting to" "$REVIEW/godot.log" 2>/dev/null && ! grep -q "host listening" "$REVIEW/godot.log" 2>/dev/null; then
		echo "remote_shot: the game ran as a client and never hosted: its numbers and stills are void"; exit 1
	fi
fi
case "$done" in "exit 0") exit 0 ;; *) exit 1 ;; esac
