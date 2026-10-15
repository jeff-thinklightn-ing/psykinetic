#!/usr/bin/env sh
# One landing on main at a time: take this before your final retest, push while holding it,
# release right after. Otherwise another tree lands between your retest and your push, and
# you rebase and retest again (or push untested code). Same lock folder mechanics as
# tools/bench_lock.sh (atomic mkdir; stale after 30 minutes), in its own folder.
#   sh tools/land_lock.sh take <tree> "<what>"   exit 1 if another tree is landing (prints who)
#   sh tools/land_lock.sh release <tree>
#   sh tools/land_lock.sh status
# If it's held, keep working; check again in a few minutes. Before pushing, always:
# take, fetch, rebase, retest, push, release.
PSYKINETIC_LOCK_LABEL="land lock" PSYKINETIC_BENCH_LOCK="${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}" exec sh "$(dirname "$0")/bench_lock.sh" "$@"
