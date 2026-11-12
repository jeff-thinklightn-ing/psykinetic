#!/usr/bin/env sh
# One landing on main at a time: take this before your final retest, push while holding it,
# release right after. Otherwise another tree lands between your retest and your push, and
# you rebase and retest again (or push untested code). Same lock folder mechanics as
# tools/bench_lock.sh (atomic mkdir), in its own folder; stale after 25 minutes (decision
# 667) since its take or its holder's last beat: tests/land.sh beats a lock its tree holds
# every minute while it runs (667 amended), so a long landing is never taken over.
#   sh tools/land_lock.sh beat <tree>
#   sh tools/land_lock.sh take <tree> "<what>"   exit 1 if another tree is landing (prints who);
#                                                exit 3 if release froze main ("main frozen" in its
#                                                what): release your gate take and requeue.
#                                                Each other try beats <tree>'s landing take (suite, suite_*), so
#                                                it never goes stale while you wait (394 amended (31)).
#   sh tools/land_lock.sh release <tree>
#   sh tools/land_lock.sh status
# If it's held, keep working; check again in a few minutes. Before pushing, always:
# take, fetch, rebase, retest, push, release.
PSYKINETIC_LOCK_FROZEN_EXIT=3 PSYKINETIC_LOCK_BEATS_GATE=1 PSYKINETIC_LOCK_STALE=1500 PSYKINETIC_LOCK_LABEL="land lock" PSYKINETIC_BENCH_LOCK="${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}" exec sh "$(dirname "$0")/bench_lock.sh" "$@"
