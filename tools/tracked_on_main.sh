#!/usr/bin/env sh
# The paths that would stop this checkout's rebase onto origin/main (667 amended (2)):
#   sh tools/tracked_on_main.sh            name them; exit 1 if any
#   sh tools/tracked_on_main.sh --clear    remove the generated ones (*.import, *.uid) and say
#                                          so, one line each; exit 1 if any other is left
# A rebase stops ("untracked working tree files would be overwritten") on a path origin/main
# adds over HEAD that sits on disk, untracked and not ignored here: an ignored one git
# overwrites without asking (git 2.56, tried), and one in the index is the take's own. So
# the list is exactly those: git diff --diff-filter=A HEAD origin/main, kept if on disk, not
# in the index and not ignored, never every untracked path against main's whole tree (a
# fetch's worth of added paths, most not on disk, against thousands). Removed: only a
# file named *.import or *.uid, each by its path; never a directory, never a pattern.
# The land lock's take runs it with --clear once taken (tools/bench_lock.sh, as
# tools/land_lock.sh sets it): a path it can't remove refuses the take, exit 4, the lock
# given back. A fetch that fails or takes over 20 s checks nothing and refuses nothing:
# the rebase meets what it meets, as before. Each removal and refusal goes to the land
# lock's log when the take runs it (TRACKED_LOG; tree, path, origin/main's sha).
set -u
clear=0
[ "${1:-}" = "--clear" ] && clear=1
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "tracked_on_main: not in a git checkout: nothing checked"; exit 0; }
cd "$top" || exit 0
tree="${TRACKED_TREE:-$(basename "$top")}"
note() { [ -n "${TRACKED_LOG:-}" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$TRACKED_LOG" 2>/dev/null; return 0; }
limit="$(command -v timeout 2>/dev/null)"
if ! ${limit:+$limit 20} git fetch -q origin main </dev/null >/dev/null 2>&1; then
	echo "tracked_on_main: fetching origin/main failed or took over 20 s: nothing checked (the rebase meets what it meets)"
	exit 0
fi
main="$(git rev-parse --short origin/main 2>/dev/null)" || { echo "tracked_on_main: no origin/main: nothing checked"; exit 0; }
left=0
paths="$(git -c core.quotePath=false diff --no-renames --name-only --diff-filter=A HEAD origin/main 2>/dev/null)"
old_ifs="$IFS"
IFS='
'
for path in $paths; do
	IFS="$old_ifs"
	[ -e "$path" ] || [ -L "$path" ] || continue
	git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 && continue
	git check-ignore -q --no-index -- "$path" 2>/dev/null && continue
	case "$path" in
		*.import|*.uid)
			if [ "$clear" -eq 1 ] && [ -f "$path" ] && [ ! -L "$path" ]; then
				rm -f -- "$path"
				echo "tracked_on_main: removed $path: generated, untracked here, and origin/main ($main) tracks it (it would stop your rebase)"
				note "cleared $tree $path (origin/main $main; 667 amended (2))"
				continue
			fi ;;
	esac
	echo "tracked_on_main: $path is untracked here and tracked on origin/main ($main): your rebase would stop on it; commit, move or remove it"
	note "refused $tree $path (origin/main $main; 667 amended (2))"
	left=1
done
IFS="$old_ifs"
exit $left
