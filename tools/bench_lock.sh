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

case "${1:-status}" in
	take)
		tree="${2:?tree name}"; what="${3:-bench}"
		if ! mkdir "$LOCK" 2>/dev/null; then
			if [ "$(age)" -gt "$STALE_SECONDS" ]; then
				echo "$LABEL: taking over a stale lock from $(who)"
				log "takeover by $tree from $(who)"
				rm -rf "$LOCK"; mkdir "$LOCK" || exit 1
			else
				echo "$LABEL: held by $(who); wait and retry"
				exit 1
			fi
		fi
		now=$(date +%s)
		echo "$tree" >"$LOCK/owner"; echo "$what" >"$LOCK/what"; echo "$now" >"$LOCK/taken"; echo "$now" >"$LOCK/since"
		log "taken by $tree ($what)"
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
