# The commit a landing's tests ran (278 amended (1), the coordinator's approval, 2026-11-12):
# sourced by tests/land.sh. land_tested_begin, once after the voice inventory's own commit
# and before any part starts, reads HEAD and the tracked tree's state; land_tested_end
# <line> prints the result line to use: a PASS line ends "tested <sha>" when nothing moved,
# "tested <sha> and uncommitted changes" when the run began with tracked changes (no bare sha
# at the end, so no script pushes it), and becomes a FAIL line when HEAD or the tracked files
# changed during the run. Any other line is printed as it came. The line's start is unchanged:
# a script that greps "LANDING TESTS: PASS" still matches, and one that pushes the sha the
# line names pushes what ran:
#   sha=$(sed -n 's/^LANDING TESTS: PASS.* tested \([0-9a-f]\{40\}\)$/\1/p' out)
# Before it, land.sh committed docs/voice_inventory.md itself (748 amended (8)), so HEAD at
# a PASS line could be one commit past the tip a script read, and ui's take passed and was
# not pushed (2026-11-12).

## HEAD and a hash of the tracked files' difference from it: equal before and after means
## the same commit and the same uncommitted tracked changes (none, for a landing).
land_tree_state() {
	printf '%s %s' "$(git rev-parse HEAD 2>/dev/null)" "$(git diff HEAD 2>/dev/null | git hash-object --stdin)"
}

land_tested_begin() {
	LAND_TESTED="$(git rev-parse HEAD 2>/dev/null)"
	LAND_STATE_BEFORE="$(land_tree_state)"
	LAND_DIRTY_BEFORE="$(git status --porcelain --untracked-files=no 2>/dev/null)"
}

land_tested_end() {
	local line="$1"
	case "$line" in
	"LANDING TESTS: PASS"*)
		if [ -z "${LAND_TESTED:-}" ]; then
			printf '%s\n' "$line"
		elif [ "$(land_tree_state)" != "$LAND_STATE_BEFORE" ]; then
			printf 'LANDING TESTS: FAIL (the tree moved during the tests: %s to %s, or its tracked files changed; 278 amended (1))\n' \
				"$LAND_TESTED" "$(git rev-parse HEAD 2>/dev/null)"
		elif [ -n "$LAND_DIRTY_BEFORE" ]; then
			printf '%s tested %s and uncommitted changes\n' "$line" "$LAND_TESTED"
		else
			printf '%s tested %s\n' "$line" "$LAND_TESTED"
		fi
		;;
	*) printf '%s\n' "$line" ;;
	esac
}
