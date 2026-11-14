#!/usr/bin/env bash
# A landing's push to main (667 amended (3); release's conditions, the coordinator's
# proposal, 2026-11-13: buildings' street check passed its landing and lost the push to a
# five-minute connection timeout, the lock held doing nothing, and a whole suite and its
# place in the gate went with it). Every land script pushes through this, after its own
# take's "LANDING TESTS: PASS", with the land lock still held:
#   sh tools/land_push.sh <tree> <tested sha>
# <tree> is the lock's holder (the name the script took it as); <tested sha> the 40-hex sha
# the PASS line names (278 amended (1)). origin/main as this checkout last fetched it (the
# rebase before the tests) is the tested base, and must be an ancestor of the sha.
# Each try is one `git push origin <sha>:refs/heads/main`, cut at 60 s (a dead connection
# costs a minute, not five). A refused push (main moved, the push guard, anything that is
# not a network error) is never tried again. On a network error, up to two more tries, a
# minute apart; before each: the lock is still <tree>'s (beaten), and a fetch says what
# main is: the tested sha (the push went through, its reply lost: landed), still the
# tested base (push again), or anything else, or the fetch fails (stop, as before 667
# amended (3): a fresh run). Each try goes in the lock's log (C:/dev/land.lock.log).
# Exit: 0 on main (pushed, or found landed); 1 not pushed (refused, main moved, a failed
# fetch, the lock not <tree>'s, the network down through all three tries): a fresh run;
# 3 the lock is release's freeze ("main frozen"): release the gate's take and requeue,
# as for land_lock.sh take's exit 3; 2 a usage fault (no lock check, nothing pushed).
# LAND_PUSH_GIT, LAND_PUSH_TIMEOUT and LAND_PUSH_WAIT are for tests/land_push_test.sh.
set -u
tree="${1:-}"
sha="${2:-}"
if [ -z "$tree" ] || ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
	echo "usage: sh tools/land_push.sh <tree> <tested sha (40 hex)>"; exit 2
fi
GIT="${LAND_PUSH_GIT:-git}"
LIMIT="${LAND_PUSH_TIMEOUT:-60}"
WAIT="${LAND_PUSH_WAIT:-60}"
TRIES=3
LOCK="${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}"
TIMEOUT="$(command -v /usr/bin/timeout || command -v timeout)"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOCK.log" 2>/dev/null || true; }
short="$(printf '%s' "$sha" | cut -c1-9)"
said_file="$(mktemp)"
trap 'rm -f "$said_file"' EXIT

git cat-file -e "$sha^{commit}" 2>/dev/null || { echo "land_push: $sha is no commit here"; exit 2; }
base="$(git rev-parse -q --verify refs/remotes/origin/main)" || { echo "land_push: no origin/main here"; exit 2; }
git merge-base --is-ancestor "$base" "$sha" || {
	echo "land_push: $short is not on origin/main as last fetched ($(printf '%s' "$base" | cut -c1-9)): rebase and test again"; exit 2; }

# The lock is <tree>'s: 0; release's freeze: 3; anything else: 1.
ours() {
	owner="$(cat "$LOCK/owner" 2>/dev/null)"
	if [ -d "$LOCK" ] && [ "$owner" = "$tree" ]; then
		sh "$(dirname "$0")/land_lock.sh" beat "$tree" >/dev/null 2>&1
		return 0
	fi
	if [ -d "$LOCK" ] && grep -qi "main frozen" "$LOCK/what" 2>/dev/null; then
		echo "land_push: main is frozen ($(cat "$LOCK/what" 2>/dev/null)): not pushed"
		log "push by $tree stopped: main frozen"
		return 3
	fi
	echo "land_push: the land lock is not $tree's ($([ -d "$LOCK" ] && echo "held by $owner" || echo free)): not pushed"
	log "push by $tree stopped: the lock not its own ($([ -d "$LOCK" ] && echo "$owner" || echo free))"
	return 1
}
# What git's output says: a network fault (worth another try) or not.
network() {
	[ "$1" = 124 ] && return 0  # Cut at $LIMIT s.
	printf '%s' "$2" | grep -qiE 'rejected|non-fast-forward|hook declined|pre-receive|protected branch|permission|denied|authentication' && return 1
	printf '%s' "$2" | grep -qiE 'unable to access|could not resolve|timed out|failed to connect|connection (reset|refused|closed)|could ?n.t connect|recv failure|send failure|remote end hung up|early eof|rpc failed|ssl|gnutls|network is unreachable'
}

try=1
while :; do
	ours; code=$?
	[ "$code" = 0 ] || exit "$code"
	# To a file, not $(...): a command substitution waits for the pipe to close, and a hung
	# push's own children (git-remote-https) hold it past the cut.
	"$TIMEOUT" "$LIMIT" $GIT -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 push origin "$sha:refs/heads/main" >"$said_file" 2>&1 </dev/null; code=$?
	out="$(cat "$said_file" 2>/dev/null)"
	said="$(printf '%s\n' "$out" | grep -vE '^\s*$' | tail -1 | cut -c1-200)"
	if [ "$code" = 0 ]; then
		log "pushed by $tree: $short (try $try)"
		echo "pushed $sha"
		exit 0
	fi
	if ! network "$code" "$out"; then
		printf '%s\n' "$out"
		log "push by $tree refused: $short (try $try): $said"
		echo "land_push: refused (exit $code): not pushed"
		exit 1
	fi
	why="$([ "$code" = 124 ] && echo "no answer in $LIMIT s" || echo "$said")"
	log "push by $tree failed on the network: $short (try $try of $TRIES): $why"
	echo "land_push: try $try of $TRIES failed on the network: $why"
	if [ "$try" -ge "$TRIES" ]; then
		echo "land_push: the network down through $TRIES tries: not pushed"
		exit 1
	fi
	try=$((try + 1))
	sleep "$WAIT"
	ours; code=$?
	[ "$code" = 0 ] || exit "$code"
	if ! "$TIMEOUT" "$LIMIT" $GIT fetch -q origin main >"$said_file" 2>&1 </dev/null; then
		log "push by $tree stopped: the fetch before try $try failed"
		echo "land_push: the fetch before try $try failed: not pushed"
		exit 1
	fi
	now="$(git rev-parse -q --verify refs/remotes/origin/main)"
	if [ "$now" = "$sha" ]; then
		log "pushed by $tree: $short landed after all (its reply lost on try $((try - 1)))"
		echo "pushed $sha (landed after all: the push went through, its answer lost)"
		exit 0
	fi
	if [ "$now" != "$base" ]; then
		log "push by $tree stopped: main moved to $(printf '%s' "$now" | cut -c1-9)"
		echo "land_push: main moved to $(printf '%s' "$now" | cut -c1-9) since the tests: not pushed"
		exit 1
	fi
done
