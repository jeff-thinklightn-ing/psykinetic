#!/usr/bin/env sh
# One timing run at a time on this machine: worktrees share its CPU, so a benchmark taken
# while another tree runs a bench (or a many-process network test) measures the load, not
# the change. Take the lock before any run whose numbers you will report; release it after.
#   tools/bench_lock.sh take <tree> "<what>"   exit 1 if another tree holds it (prints who)
#   tools/bench_lock.sh release <tree>
#   tools/bench_lock.sh status
# The lock is the folder C:/dev/bench.lock (mkdir is atomic); one older than 30 minutes is
# stale and may be taken over.
set -u
LOCK="${PSYKINETIC_BENCH_LOCK:-/c/dev/bench.lock}"
STALE_SECONDS=1800
LABEL="${PSYKINETIC_LOCK_LABEL:-bench lock}"

held() { [ -d "$LOCK" ]; }
# A lock another tree has only just taken may not have its time written yet: count it as new.
age() {
	since=$(cat "$LOCK/since" 2>/dev/null)
	[ -n "$since" ] || since=$(date +%s)
	echo $(( $(date +%s) - since ))
}
who() { echo "$(cat "$LOCK/owner" 2>/dev/null) ($(cat "$LOCK/what" 2>/dev/null)), $(( $(age) / 60 )) min"; }

case "${1:-status}" in
	take)
		tree="${2:?tree name}"; what="${3:-bench}"
		if ! mkdir "$LOCK" 2>/dev/null; then
			if [ "$(age)" -gt "$STALE_SECONDS" ]; then
				echo "$LABEL: taking over a stale lock from $(who)"
				rm -rf "$LOCK"; mkdir "$LOCK" || exit 1
			else
				echo "$LABEL: held by $(who); wait and retry"
				exit 1
			fi
		fi
		echo "$tree" >"$LOCK/owner"; echo "$what" >"$LOCK/what"; date +%s >"$LOCK/since"
		echo "$LABEL: taken by $tree ($what)"
		;;
	release)
		tree="${2:?tree name}"
		if held && [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$tree" ]; then
			rm -rf "$LOCK"; echo "$LABEL: released by $tree"
		elif held; then
			echo "$LABEL: held by $(who), not $tree; not released"; exit 1
		else
			echo "$LABEL: not held"
		fi
		;;
	status)
		if held; then echo "$LABEL: held by $(who)"; else echo "$LABEL: free"; fi
		;;
	*) echo "usage: $0 take <tree> \"<what>\" | release <tree> | status"; exit 2 ;;
esac
