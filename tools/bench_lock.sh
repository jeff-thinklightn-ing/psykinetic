#!/usr/bin/env sh
# One timing run at a time on this machine: worktrees share its CPU, so a benchmark taken
# while another tree runs a bench (or a many-process network test) measures the load, not
# the change. Take the lock before any run whose numbers you will report; release it after.
#   tools/bench_lock.sh take <tree> "<what>"   exit 1 if another tree holds it (prints who)
#   tools/bench_lock.sh release <tree>
#   tools/bench_lock.sh status
#   tools/bench_lock.sh beat <tree>            the holder is alive (no-op unless <tree> holds it)
# The lock is the folder C:/dev/bench.lock (mkdir is atomic); one quiet for 30 minutes
# (PSYKINETIC_LOCK_STALE seconds) since its take or its holder's last beat is stale and may
# be taken over.
# As the land lock (tools/land_lock.sh sets these, 394 amended (31)):
# PSYKINETIC_LOCK_FROZEN_EXIT, the exit of a take refused by a lock whose "what"
# says "main frozen" (release's freeze), which is never beaten; and
# PSYKINETIC_LOCK_BEATS_GATE, each other take, refused or not, beats the
# caller's gate take of its landing kind (suite, suite_*; heavy_job beat), so it
# never goes stale here.
set -u
LOCK="${PSYKINETIC_BENCH_LOCK:-/c/dev/bench.lock}"
STALE_SECONDS="${PSYKINETIC_LOCK_STALE:-1800}"
LABEL="${PSYKINETIC_LOCK_LABEL:-bench lock}"

held() { [ -d "$LOCK" ]; }
# Seconds since the holder took it or last beat ("since"; 667 amended: a landing beats
# while its tests run, so a long one never goes stale, and every checkout's copy, old or
# new, reads the same file). A lock another tree has only just taken may not have its time
# written yet: count it as new.
age() {
	since=$(cat "$LOCK/since" 2>/dev/null)
	[ -n "$since" ] || since=$(date +%s)
	echo $(( $(date +%s) - since ))
}
# Minutes since the take itself ("taken"; a lock taken before the beat has only "since").
held_min() {
	taken=$(cat "$LOCK/taken" 2>/dev/null)
	[ -n "$taken" ] || { echo $(( $(age) / 60 )); return; }
	echo $(( ($(date +%s) - taken) / 60 ))
}
who() {
	beat=""
	[ -f "$LOCK/taken" ] && [ "$(cat "$LOCK/taken")" != "$(cat "$LOCK/since" 2>/dev/null)" ] && beat=", last beat $(age) s ago"
	echo "$(cat "$LOCK/owner" 2>/dev/null) ($(cat "$LOCK/what" 2>/dev/null)), $(held_min) min$beat"
}
# Every take, takeover and release, with the time, beside the lock (<lock>.log), so two
# landings that overlapped can be traced afterwards. Refusals are not logged (loops retry).
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOCK.log" 2>/dev/null || true; }
beat_gate() {
	[ -n "${PSYKINETIC_LOCK_BEATS_GATE:-}" ] || return 0
	# 0 beaten, 1 no take to beat (a docs push) or not this try's turn; anything
	# else a fault, told (394 amended (37)): in the gate's log, else beside the lock.
	if [ -n "${PSYKINETIC_LOCK_ORDERED:-}" ]; then
		# The land lock's order (394 amended (36)): the try recorded beside the lock, the take beaten.
		said="$(python -B "$(dirname "$0")/heavy_job.py" lock_turn "$1" "$LOCK" 2>&1)"; code=$?
	else
		said="$(python -B "$(dirname "$0")/heavy_job.py" beat "$1" 2>&1)"; code=$?
	fi
	if [ "$code" -gt 1 ] || printf '%s' "$said" | grep -q "Traceback"; then
		said="$(printf '%s' "$said" | tail -1)"
		python -B "$(dirname "$0")/heavy_job.py" note "$1" beat_failed "exit $code: $said" >/dev/null 2>&1 || log "beat_failed by $1: exit $code: $said"
	fi
	return 0
}
# A free (or stale) land lock goes to the first live landing in the order
# (394 amended (36); heavy_job.py lock_turn says why not, exit 1); only release's freeze,
# "main frozen" in its what, takes it past them.
turn_ok() {
	[ -n "${PSYKINETIC_LOCK_ORDERED:-}" ] || return 0
	printf '%s' "$2" | grep -qi "main frozen" && return 0
	python -B "$(dirname "$0")/heavy_job.py" lock_turn "$1" "$LOCK" --free
}

case "${1:-status}" in
	take)
		tree="${2:?tree name}"; what="${3:-bench}"
		if [ ! -d "$LOCK" ] && ! turn_ok "$tree" "$what"; then
			exit 1
		fi
		if ! mkdir "$LOCK" 2>/dev/null; then
			if [ "$(age)" -gt "$STALE_SECONDS" ]; then
				turn_ok "$tree" "$what" || exit 1
				echo "$LABEL: taking over a stale lock from $(who)"
				log "takeover by $tree from $(who)"
				rm -rf "$LOCK"; mkdir "$LOCK" || exit 1
			elif [ -n "${PSYKINETIC_LOCK_FROZEN_EXIT:-}" ] && grep -qi "main frozen" "$LOCK/what" 2>/dev/null; then
				echo "$LABEL: main frozen by $(who): release your suite take and requeue"
				exit "$PSYKINETIC_LOCK_FROZEN_EXIT"
			else
				beat_gate "$tree"
				echo "$LABEL: held by $(who); wait and retry"
				exit 1
			fi
		fi
		now=$(date +%s)
		echo "$tree" >"$LOCK/owner"; echo "$what" >"$LOCK/what"; echo "$now" >"$LOCK/taken"; echo "$now" >"$LOCK/since"
		# The checkout it was taken from (decision 883): tests/land.sh run there under
		# another name lands under the lock's (physics' second take under the lock, 11-12).
		git rev-parse --show-toplevel >"$LOCK/checkout" 2>/dev/null
		rm -f "$LOCK.waiters/$tree.json"  # 394 amended (36): in, no longer waiting.
		log "taken by $tree ($what)"
		PSYKINETIC_LOCK_ORDERED= beat_gate "$tree"  # A plain beat: no longer a waiter.
		echo "$LABEL: taken by $tree ($what)"
		;;
	release)
		tree="${2:?tree name}"
		if held && [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$tree" ]; then
			rm -rf "$LOCK"; log "released by $tree"; echo "$LABEL: released by $tree"
		elif held; then
			echo "$LABEL: held by $(who), not $tree; not released"; exit 1
		else
			echo "$LABEL: not held"
		fi
		;;
	beat)
		# The holder is alive: "since" moves to now, so staleness counts from here.
		# Silent and exit 0 unless <tree> holds it (a loop beats whatever happened).
		tree="${2:?tree name}"
		if held && [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$tree" ]; then
			date +%s >"$LOCK/since.tmp" 2>/dev/null && mv -f "$LOCK/since.tmp" "$LOCK/since" 2>/dev/null
		fi
		exit 0
		;;
	status)
		if held; then echo "$LABEL: held by $(who)"; else echo "$LABEL: free"; fi
		;;
	*) echo "usage: $0 take <tree> \"<what>\" | release <tree> | beat <tree> | status"; exit 2 ;;
esac
