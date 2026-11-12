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
#   tools/remote_tests.sh run                prepare, the three parts, finish
# One landing's tests at a time there (a slot, ~/land/.busy, stale after 40
# minutes; waited for 10). The timeouts there (slot 10 min, two imports 5
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
	"${SSH[@]}" "$HOST" bash -s -- "$@" <<'REMOTE'
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
stop_leftovers() {
	left=""
	for p in /proc/[0-9]*; do
		pid="${p#/proc/}"
		[ "$pid" = "$$" ] && continue
		c="$(readlink "$p/cwd" 2>/dev/null)" || continue
		case "$c" in "$1"|"$1"/*) left="$left $pid" ;; esac
	done
	[ -n "$left" ] || return 0
	echo "remote: stopping what an earlier run left in $1:$left"
	kill -TERM $left 2>/dev/null; sleep 3; kill -KILL $left 2>/dev/null
	return 0
}

holder() { cat "$BUSY/holder" 2>/dev/null; }
mine() { [ "$(holder)" = "$tree $sha" ]; }
take_slot() {
	waited=0
	while ! mkdir "$BUSY" 2>/dev/null; do
		if mine; then return 0; fi
		age=$(( $(date +%s) - $(stat -c %Y "$BUSY" 2>/dev/null || echo 0) ))
		if [ "$age" -gt 2400 ]; then
			echo "remote: the slot held by '$(holder)' is $age s old: taken over"
			other="$(holder)"; other="${other%% *}"
			[ -n "$other" ] && stop_leftovers "$HOME/land/$other"
			rm -rf "$BUSY"
			continue
		fi
		[ "$waited" -ge 600 ] && { echo "remote: saturn's slot is held by '$(holder)' ($age s); waited 10 minutes"; return 1; }
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
	remote prepare "$tree" "$sha" "$JOBS"
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
