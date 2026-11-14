#!/usr/bin/env bash
# A landing's Godot tests on saturn (Jeff, 2026-11-11: "go ahead and move
# landings' test runs to saturn"). This PC ran short of memory for a suite;
# saturn (Ubuntu, 24 cores, 30 GB) runs the whole suite in about five
# minutes. The land lock, the rebase and the push stay here; only the
# commit under test travels, as a git bundle, to a checkout of its own there
# (~/land/<tree>, a worktree of ~/psykinetic, which has no remote and no
# credentials). The result counts only for the commit it names.
#   tools/remote_tests.sh available          exit 0: saturn answers and is set up
#   tools/remote_tests.sh kind               the gate kind for this landing: suite_remote
#                                            when saturn answers (and LAND_LOCAL is unset), else suite
#   tools/remote_tests.sh prepare            send HEAD, check it out, import it
#   tools/remote_tests.sh part <name>        suite | state_test | net_test, on HEAD
#   tools/remote_tests.sh finish             give saturn's slot back
#   tools/remote_tests.sh slot               take saturn's slot only (tests/remote_slot_test.sh's)
#   tools/remote_tests.sh run                prepare, the three parts, finish
# One landing's tests at a time there (a slot, ~/land/.busy, stale after 40
# minutes; waited for 10). A slot whose landing is gone on this PC is taken
# over at once (878 amended (1)): prepare tells saturn which trees are live
# here (the land lock's holder beaten in the last 150 s, and every tree with a
# running gate take) and whether this tree holds the lock; a holder that is
# neither live nor this tree's own earlier take is taken over only when
# nothing runs under ~/land/<holder> and the slot has gone 2 minutes
# untouched, each one logged in saturn's ~/land/.slot_clears.log. The timeouts there (slot 10 min, two imports 5
# each, the suite 20 with state_test's 15 beside it, net_test 10) sum under
# the gate's 60 for suite_remote. A part prints the remote log and ends with
#   REMOTE <name>: PASS|FAIL sha=<sha> <seconds>s
# and exits 0 only on PASS for this checkout's HEAD. A lost connection is a
# fail, never a pass and never a quiet local rerun.
set -u

HOST="${PSYKINETIC_REMOTE_HOST:-jequig@saturn}"
JOBS="${PSYKINETIC_REMOTE_JOBS:-12}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
SCP=(scp -o BatchMode=yes -o ConnectTimeout=5 -q)

cd "$(dirname "$0")/.." || exit 1
tree="${PSYKINETIC_TREE:-$(basename "$(pwd)")}"
case "$tree" in
	*[!A-Za-z0-9_.-]*|"") echo "remote_tests: a tree name of letters, digits, _ . - only (got '$tree')"; exit 1 ;;
esac

# What runs on saturn. Arguments: verb tree sha jobs [part]. Sent on stdin so
# nothing is installed there but Godot and the clone.
remote() {
	if [ -n "${PSYKINETIC_REMOTE_HERE:-}" ]; then
		remote_script | HOME="$PSYKINETIC_REMOTE_HERE" bash -s -- "$@"
	else
		remote_script | "${SSH[@]}" "$HOST" bash -s -- "$@"
	fi
}
# tests/remote_slot_test.sh runs it here, its HOME a scratch folder (PSYKINETIC_REMOTE_HERE).
remote_script() {
	cat <<'REMOTE'
set -u
verb="$1"; tree="$2"; sha="$3"; jobs="$4"; part="${5:-}"
export PATH="$HOME/.local/bin:$PATH"
G="$HOME/godot/Godot_v4.7.2-stable_linux.x86_64"
REPO="$HOME/psykinetic"
W="$HOME/land/$tree"
BUSY="$HOME/land/.busy"
LOGS="$HOME/land/.logs/$tree"
mkdir -p "$HOME/land/.logs" "$HOME/land/.in"
# This shell leads its own session (sshd starts it so), and a test under
# `timeout` leaves its process group but never its session: whatever this
# shell started is stopped by session, never by name.
sid="$(ps -o sid= -p $$ | tr -d ' ')"
end_session() { pkill -TERM -s "$sid" 2>/dev/null; }
trap 'trap - TERM HUP INT; end_session' HUP TERM INT
# What an earlier run left in a tree's checkout (its shell died with the
# connection, its Godots ran on): this user's processes whose folder is that
# checkout, stopped by id.
running_in() {
	for p in /proc/[0-9]*; do
		pid="${p#/proc/}"
		[ "$pid" = "$$" ] && continue
		c="$(readlink "$p/cwd" 2>/dev/null)" || continue
		case "$c" in "$1"|"$1"/*) printf ' %s' "$pid" ;; esac
	done
}
stop_leftovers() {
	left="$(running_in "$1")"
	[ -n "$left" ] || return 0
	echo "remote: stopping what an earlier run left in $1:$left"
	kill -TERM $left 2>/dev/null; sleep 3; kill -KILL $left 2>/dev/null
	return 0
}

holder() { cat "$BUSY/holder" 2>/dev/null; }
mine() { [ "$(holder)" = "$tree $sha" ]; }
# 878 amended (1): what this PC said with prepare ("live=a,b;mine=1"; nothing
# said, nothing taken over early). A holder is gone when its tree is not live
# here (no land-lock beat in 150 s and no gate take: both signs, never one),
# or is this tree's own earlier take while this take holds the land lock.
said_live=""; said_mine=""; said_wait=600; said_any=""
case "${part:-}" in
live=*|wait=*)
	for each in $(printf '%s' "$part" | tr ';' ' '); do
		case "$each" in
		live=*) said_live=",${each#live=},"; said_any=1 ;;
		mine=*) said_mine="${each#mine=}" ;;
		wait=*) said_wait="${each#wait=}" ;;
		esac
	done
	;;
esac
gone_why() {
	[ -n "$said_any" ] || return 1
	case "$1" in
	"$tree") [ "$2" != "$sha" ] && [ "$said_mine" = 1 ] && echo "this tree's earlier take; this take holds the land lock" ;;
	*) case "$said_live" in *",$1,"*) return 1 ;; esac
		echo "no land-lock beat in 150 s and no gate take" ;;
	esac
}
take_slot() {
	waited=0
	while ! mkdir "$BUSY" 2>/dev/null; do
		if mine; then return 0; fi
		age=$(( $(date +%s) - $(stat -c %Y "$BUSY" 2>/dev/null || echo 0) ))
		other="$(holder)"
		why=""
		[ "$age" -ge 120 ] && [ -n "$other" ] && why="$(gone_why "${other%% *}" "${other#* }")"
		if [ -n "$why" ] && [ -z "$(running_in "$HOME/land/${other%% *}")" ] && [ "$(holder)" = "$other" ]; then
			echo "$(date '+%Y-%m-%d %H:%M:%S') taken over by $tree $sha from '$other' ($age s untouched): its landing gone on the PC ($why), nothing running under ~/land/${other%% *}" >>"$HOME/land/.slot_clears.log"
			echo "remote: the slot held by '$other' ($age s untouched) taken over: its landing is gone on the PC ($why)"
			rm -rf "$BUSY"
			continue
		fi
		if [ "$age" -gt 2400 ]; then
			echo "remote: the slot held by '$(holder)' is $age s old: taken over"
			other="$(holder)"; other="${other%% *}"
			[ -n "$other" ] && stop_leftovers "$HOME/land/$other"
			rm -rf "$BUSY"
			continue
		fi
		[ "$waited" -ge "$said_wait" ] && { echo "remote: saturn's slot is held by '$(holder)' ($age s); waited $(( said_wait / 60 )) minutes"; return 1; }
		sleep 5; waited=$(( waited + 5 ))
	done
	echo "$tree $sha" > "$BUSY/holder"
}

case "$verb" in
available)
	[ -x "$G" ] && git -C "$REPO" rev-parse -q --verify main >/dev/null || exit 1
	# What saturn already has, for the sender to leave out of its bundle.
	git -C "$REPO" for-each-ref --format='have %(objectname)' refs/heads refs/land
	;;
has)
	git -C "$REPO" cat-file -e "$sha^{commit}" 2>/dev/null
	;;
slot)
	take_slot || exit 1
	echo "remote: the slot is $tree's for $sha"
	;;
prepare)
	take_slot || exit 1
	stop_leftovers "$W"
	rm -rf "$LOGS"; mkdir -p "$LOGS"
	bundle="$HOME/land/.in/$tree.bundle"
	if [ -f "$bundle" ]; then
		git -C "$REPO" fetch -q --force "$bundle" "HEAD:refs/land/$tree" || { echo "remote: the bundle did not fetch"; exit 1; }
		rm -f "$bundle"
	fi
	git -C "$REPO" cat-file -e "$sha^{commit}" 2>/dev/null || { echo "remote: saturn does not have $sha"; exit 1; }
	if [ -e "$W/.git" ]; then
		git -C "$W" checkout -q --force --detach "$sha" && git -C "$W" clean -fdq || { echo "remote: could not check out $sha in $W"; exit 1; }
	else
		git -C "$REPO" worktree prune
		git -C "$REPO" worktree add -q --force --detach "$W" "$sha" || { echo "remote: could not make $W"; exit 1; }
	fi
	cd "$W" || exit 1
	[ "$(git rev-parse HEAD)" = "$sha" ] || { echo "remote: $W is at $(git rev-parse HEAD), not $sha"; exit 1; }
	[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "remote: $W is not clean"; exit 1; }
	# Twice: a first pass on a fresh .godot logs font errors, the second is clean.
	timeout 300 "$G" --headless --audio-driver Dummy --path . --import >"$LOGS/import1.log" 2>&1 </dev/null
	timeout 300 "$G" --headless --audio-driver Dummy --path . --import >"$LOGS/import2.log" 2>&1 </dev/null
	code=$?
	if [ "$code" -ne 0 ] || grep -q "SCRIPT ERROR" "$LOGS/import2.log"; then
		grep -E "SCRIPT ERROR|^ERROR" -A3 "$LOGS/import2.log" | head -40
		echo "remote: the import failed (exit $code)"; exit 1
	fi
	echo "remote: $tree at $sha checked out and imported on $(hostname)"
	;;
part)
	mine || { echo "remote: the slot is not $tree's for $sha (held by '$(holder)'): prepare first"; exit 1; }
	cd "$W" || exit 1
	[ "$(git rev-parse HEAD)" = "$sha" ] || { echo "remote: $W is at $(git rev-parse HEAD), not $sha"; exit 1; }
	touch "$BUSY"
	export GODOT_PATH="$G" HEAVY_JOB_INSIDE=1 PSYKINETIC_TEST_JOBS="$jobs"
	case "$part" in
	suite|state_test|net_test) ;;
	*) echo "remote: no part '$part'"; exit 1 ;;
	esac
	# The connection watched: with no terminal there is no HUP when the PC's
	# side dies (a stopped landing, a lost network), and the Godots, writing
	# to their own logs, would run on in this checkout. A blank line to
	# stderr every ten seconds; when it can't be written, the session ends.
	( trap '' PIPE; while sleep 10; do echo >&2 || { end_session; sleep 3; pkill -KILL -s "$sid"; exit; }; done ) &
	watcher=$!
	t0=$(date +%s)
	case "$part" in
	suite) timeout 1200 bash tests/run.sh </dev/null 2>&1 ;;
	state_test) timeout 900 bash tests/state_test.sh </dev/null 2>&1 ;;
	net_test) timeout 600 bash tests/net_test.sh </dev/null 2>&1 ;;
	esac
	code=$?
	pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null
	touch "$BUSY"
	echo "REMOTE $part: $([ "$code" -eq 0 ] && echo PASS || echo FAIL) sha=$sha $(( $(date +%s) - t0 ))s"
	exit "$code"
	;;
finish)
	if mine; then rm -rf "$BUSY"; fi
	;;
*)
	echo "remote: no verb '$verb'"; exit 1 ;;
esac
REMOTE
}

sha="$(git rev-parse HEAD)" || exit 1
# 878 amended (1): the trees whose landings are live on this PC, for saturn's
# slot: the land lock's holder when beaten in the last 150 s, and every tree
# with a running gate take (the gate drops the dead and those from before a
# boot). With "mine=1" when this tree holds the lock. Nothing printed when
# either can't be read: saturn then takes nothing over early.
live_here() {
	lock="${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}"
	owner=""; mine=0
	if [ -d "$lock" ]; then
		owner="$(cat "$lock/owner" 2>/dev/null)"
		since="$(cat "$lock/since" 2>/dev/null)"
		[ "$owner" = "$tree" ] && mine=1
		case "$since" in ''|*[!0-9]*) return 1 ;; esac
		[ $(( $(date +%s) - since )) -le 150 ] || owner=""
	fi
	gate="$(python -B -c "
import sys
sys.path.insert(0, 'tools')
import heavy_job as gate
with gate.StateLock():
    print(','.join(sorted({each['tree'] for each in gate._entries('running')})))
" 2>/dev/null)" || return 1
	case "$owner,$gate" in *[!A-Za-z0-9_.,-]*) return 1 ;; esac
	echo "live=$owner,$gate;mine=$mine"
}
# What prepare tells saturn's slot: the live list, and a test's own wait (tests/remote_slot_test.sh;
# a landing never sets PSYKINETIC_REMOTE_SLOT_WAIT, so its prepare waits the 10 minutes).
slot_said() {
	said="$(live_here)"
	[ -n "${PSYKINETIC_REMOTE_SLOT_WAIT:-}" ] && said="${said:-live_unread=1};wait=$PSYKINETIC_REMOTE_SLOT_WAIT"
	case "$said" in live_unread=*) said="wait=${said#*;wait=}" ;; esac
	printf '%s' "$said"
}
# Tracked files changed and not committed, less the pages a landing
# regenerates (no Godot test reads them): the commit is what saturn tests.
uncommitted() {
	git status --porcelain --untracked-files=no | grep -vE '^.. (docs/|CHANGELOG\.md$|art/kit/status\.json$)'
}

case "${1:-}" in
available)
	remote available "$tree" "$sha" "$JOBS" >/dev/null 2>&1
	;;
kind)
	# Uncommitted work is tried here, as before: saturn tests commits.
	if [ -z "${LAND_LOCAL:-}" ] && [ -z "$(uncommitted)" ] && remote available "$tree" "$sha" "$JOBS" >/dev/null 2>&1; then
		echo suite_remote
	else
		echo suite
	fi
	;;
prepare)
	# The commit is what is tested. A generated page or the CHANGELOG changed
	# and not yet committed (a landing's own regeneration) is said and let by:
	# no Godot test reads them. Anything else uncommitted refuses.
	dirty="$(uncommitted)"
	if [ -n "$dirty" ]; then
		echo "remote_tests: tracked files are changed and not committed; the commit is what is tested"
		echo "$dirty" | head -10
		exit 1
	fi
	git status --porcelain --untracked-files=no | sed 's/^/remote_tests: uncommitted, not sent: /' | head -5
	if ! remote has "$tree" "$sha" "$JOBS" 2>/dev/null; then
		there="$(remote available "$tree" "$sha" "$JOBS" 2>/dev/null | sed -n 's/^have //p' | sort -u)"
		[ -n "$there" ] || { echo "remote_tests: saturn does not answer"; exit 1; }
		tmp="$(mktemp -d -t psykinetic-remote.XXXXXX)"
		trap 'rm -rf "$tmp"' EXIT
		# Only what saturn lacks: every commit it names that this checkout
		# knows is left out (its main, and each tree's last tested tip).
		known=""
		for each in $there; do
			git cat-file -e "$each^{commit}" 2>/dev/null && known="$known ^$each"
		done
		( cd "$tmp" && git -C "$OLDPWD" bundle create "$tmp/$tree.bundle" HEAD $known ) >"$tmp/bundle.log" 2>&1
		if [ ! -s "$tmp/$tree.bundle" ]; then
			cat "$tmp/bundle.log"
			echo "remote_tests: could not bundle $sha"; exit 1
		fi
		( cd "$tmp" && "${SCP[@]}" "$tree.bundle" "$HOST:land/.in/$tree.bundle" ) || { echo "remote_tests: could not send the bundle"; exit 1; }
	fi
	remote prepare "$tree" "$sha" "$JOBS" "$(slot_said)"
	;;
slot)
	# tests/remote_slot_test.sh's: take saturn's slot only, as prepare would.
	remote slot "$tree" "$sha" "$JOBS" "$(slot_said)"
	;;
part)
	name="${2:-}"
	out="$(mktemp -t psykinetic-remote-part.XXXXXX)"
	# The remote side's stderr is only its ten-second line to this connection.
	remote part "$tree" "$sha" "$JOBS" "$name" 2>/dev/null | tee "$out"
	code="${PIPESTATUS[0]}"
	last="$(grep -E "^REMOTE $name: " "$out" | tail -1)"
	rm -f "$out"
	# Only this commit's own PASS line passes: a lost connection (255) or a
	# line for another sha never does.
	case "$last" in
		"REMOTE $name: PASS sha=$sha "*) [ "$code" -eq 0 ] && exit 0 ;;
	esac
	[ -n "$last" ] || echo "REMOTE $name: FAIL sha=$sha (no result line: the connection or the run was cut, exit $code)"
	exit 1
	;;
finish)
	remote finish "$tree" "$sha" "$JOBS"
	;;
run)
	bash "$0" prepare || { bash "$0" finish; echo "REMOTE TESTS: FAIL sha=$sha (prepare)"; exit 1; }
	started=$(date +%s)
	failed=""
	bash "$0" part state_test >"${TMPDIR:-/tmp}/remote-$tree-state.log" 2>&1 &
	state_pid=$!
	bash "$0" part suite || failed="$failed suite"
	wait "$state_pid" || failed="$failed state_test"
	tail -3 "${TMPDIR:-/tmp}/remote-$tree-state.log"
	bash "$0" part net_test || failed="$failed net_test"
	bash "$0" finish
	if [ -z "$failed" ]; then
		echo "REMOTE TESTS: PASS sha=$sha (suite, state_test, net_test; $(( $(date +%s) - started ))s)"
	else
		echo "REMOTE TESTS: FAIL sha=$sha ($failed; $(( $(date +%s) - started ))s)"
		exit 1
	fi
	;;
*)
	sed -n '2,20p' "$0"
	exit 2
	;;
esac
