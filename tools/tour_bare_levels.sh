#!/usr/bin/env bash
# The regenerating levels a tour's server loaded with no generation laid (828 amended (9)):
#   sh tools/tour_bare_levels.sh <sha> <server.log>
# prints each such level, one a line, and exits 1 when there is one; 0 and nothing when none.
# A level regenerates when its level.json at <sha> is marked "regenerate"; it was laid when the
# log has "[regen] <level>: generation" (main.gd's line). Unlaid, a tour's stills show the
# template no player meets: from 409fad948 every laptop tour's barrow and Ossuary did, unseen
# (look214_ossuary: "[level] barrow_deep: 715 cells", no [regen] line).
set -u
sha="$1"
log="$2"
bare=0
for level in $(tr -d '\r' <"$log" 2>/dev/null | sed -n 's/^\[level\] \([a-z0-9_]*\): [0-9]* cells.*/\1/p' | sort -u); do
	git show "$sha:levels/$level/level.json" 2>/dev/null | grep -q '"regenerate"' || continue
	tr -d '\r' <"$log" | grep -q "^\[regen\] $level: generation " && continue
	echo "$level"
	bare=1
done
exit $bare
