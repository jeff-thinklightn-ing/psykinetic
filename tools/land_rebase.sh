#!/usr/bin/env bash
# A landing's fetch and rebase onto origin/main, in one place (394 amended (65), release's shape
# and the coordinator's terms, 2026-11-16). That night three landings took the lock and gave it
# back with no push: perf's slowline on a docs/voice_inventory.md conflict its own script would
# not let through (748 amended (8) regenerates that page in a commit of its own at each landing
# with a voice line, so most takes behind meet it), and dungeon's nichefix on a real conflict in
# main.gd that had sat unseen for ninety minutes in the queue. Each tree's land script ran its own
# `git rebase origin/main`; nothing between the lock's take and land.sh ran the resolver.
#
#   bash tools/land_rebase.sh <tree>
#       fetch, then rebase this checkout onto origin/main. At each stop, when every conflicted file
#       is one the resolvers own (CHANGELOG.md; the generated pages docs/voice_inventory.md,
#       docs/art_status.md and art/kit/status.json; THIRD_PARTY.md's slot spans; the lists'
#       client3d/room_fields.gd and net/net.gd), it runs `python -B tools/list_lines.py --fix` for
#       the lists and `python -B tools/changelog_resolve.py` for the rest, and continues. Anything
#       else, or a resolver's refusal: `git rebase --abort`, the checkout left as it was, the files
#       named ("REBASE CONFLICT onto <sha>: ..."), exit 1. A failed fetch is exit 1 too, nothing
#       rebased ("land_rebase: the fetch failed"): a land script reads the line as well as the code.
#       Exit 0: rebased (or already on origin/main). Exit 2: a usage fault, or the checkout not fit
#       to start (a rebase already stopped here, tracked changes uncommitted).
#
#   bash tools/land_rebase.sh --would [--no-fetch] <tree>
#       whether that rebase would stop, touching no working tree and no index: the commits a rebase
#       would pick (`git rev-list --cherry-pick`, so a stack's base landed under another sha drops
#       out) each replayed with `git merge-tree --write-tree --merge-base` (git 2.40 or later).
#       Prints "clean", "resolvable: <files>"
#       (exit 0), or "CONFLICT: <files>" (exit 1); exit 2 when it cannot tell. A waiter runs it when
#       it queues and each time origin/main's tip moves (no Godot, no gate take); --no-fetch reads
#       origin/main as last fetched (every checkout shares the ref, and a landing's push moves it).
#       About 1 to 2 s on this repository. It leaves nothing in the store (the coordinator's term:
#       nobody may gc or prune it, and C: filled on 11-16): the replay's trees, blobs and commits go
#       to a temp folder of its own (GIT_OBJECT_DIRECTORY, the common store read through
#       GIT_ALTERNATE_OBJECT_DIRECTORIES), removed by its exact path on every way out.
#
# It takes no lock and holds nothing. Every run writes one line to the land lock's log
# (C:/dev/land.lock.log), --would only when its answer for that tip of main changes, and its last
# answer to <lock>.would/<tree> ("<epoch> <main sha> <clean|resolvable|conflict|rebased> <files>"),
# which heavy_job status may show beside a queued row. A land script from before it is unchanged:
# it keeps its own rebase until its tree calls this instead.
# LAND_REBASE_ONTO, LAND_REBASE_RESOLVER and LAND_REBASE_LISTS are for tests/land_rebase_test.sh.
set -u
LOCK="${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}"
ONTO="${LAND_REBASE_ONTO:-origin/main}"
RESOLVER="${LAND_REBASE_RESOLVER:-python -B tools/changelog_resolve.py}"
LISTS_FIX="${LAND_REBASE_LISTS:-python -B tools/list_lines.py --fix}"
# The files a resolver owns: CHANGELOG.md, the generated pages and THIRD_PARTY.md
# (changelog_resolve.py, 539 amended (3), (5), (7)), the lists (list_lines.py, 944).
OWNED='^(CHANGELOG[.]md|docs/voice_inventory[.]md|docs/art_status[.]md|art/kit/status[.]json|THIRD_PARTY[.]md|client3d/room_fields[.]gd|net/net[.]gd)$'
LISTS='^(client3d/room_fields[.]gd|net/net[.]gd)$'
STOPS_MOST=60

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOCK.log" 2>/dev/null || true; }
words() { tr '\n' ' ' | sed 's/ *$//; s/ /, /g'; }

would=0
fetch=1
while [ $# -gt 0 ]; do
	case "$1" in
		--would) would=1 ;;
		--no-fetch) fetch=0 ;;
		-*) echo "land_rebase: no option $1"; exit 2 ;;
		*) break ;;
	esac
	shift
done
tree="${1:-}"
if [ -z "$tree" ] || [ $# -ne 1 ]; then
	echo "usage: bash tools/land_rebase.sh [--would [--no-fetch]] <tree>"; exit 2
fi
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "land_rebase: not in a git checkout"; exit 2; }
cd "$top" || exit 2
mark() {
	mkdir -p "$LOCK.would" 2>/dev/null || return 0
	printf '%s %s %s %s\n' "$(date +%s)" "$(git rev-parse -q --verify "$ONTO")" "$1" "$2" >"$LOCK.would/$tree.tmp" 2>/dev/null &&
		mv -f "$LOCK.would/$tree.tmp" "$LOCK.would/$tree" 2>/dev/null
	return 0
}
if [ $fetch = 1 ]; then
	git fetch -q origin 2>/dev/null || { echo "land_rebase: the fetch failed"; log "land_rebase $tree: the fetch failed"; exit $([ $would = 1 ] && echo 2 || echo 1); }
fi
onto="$(git rev-parse -q --verify "$ONTO")" || { echo "land_rebase: no $ONTO here"; exit 2; }
short="$(printf '%s' "$onto" | cut -c1-9)"

if [ $would = 1 ]; then
	common="$(cd "$(git rev-parse --git-common-dir)" && { pwd -W 2>/dev/null || pwd; })" || { echo "land_rebase: no common git folder"; exit 2; }
	scratch="$(mktemp -d "${TEMP:-${TMPDIR:-/tmp}}/land_rebase_would_$(basename "$top")_XXXXXX")" || { echo "land_rebase: no temp folder for the replay"; exit 2; }
	trap 'rm -rf "$scratch"' EXIT
	trap 'exit 2' HUP INT TERM
	export GIT_OBJECT_DIRECTORY="$scratch" GIT_ALTERNATE_OBJECT_DIRECTORIES="$common/objects"
	# The rebase replayed, as git would pick it: the commits not on origin/main less those whose
	# patch is there already (a stack whose base landed under another sha), each merged onto the
	# last with its parent as the base. Only objects are written (trees and unreferenced commits);
	# no ref, index or file moves. A stop the resolvers own goes on from merge-tree's tree, as the
	# rebase goes on once they have written theirs.
	picks="$(git rev-list --reverse --cherry-pick --right-only --no-merges "$onto...HEAD" 2>/dev/null)" ||
		{ echo "land_rebase: could not list the commits to replay"; exit 2; }
	cur="$onto"
	files=""
	for pick in $picks; do
		out="$(git merge-tree --write-tree --name-only --no-messages --merge-base="$pick^" "$cur" "$pick" 2>&1)"; code=$?
		case $code in
			0|1) ;;
			*) echo "land_rebase: merge-tree could not tell at $(printf '%s' "$pick" | cut -c1-9) (exit $code): $(printf '%s' "$out" | head -c 200)"; exit 2 ;;
		esac
		if [ $code = 1 ]; then
			here="$(printf '%s\n' "$out" | sed 1d | sed '/^$/d')"
			files="$(printf '%s\n%s\n' "$files" "$here" | sed '/^$/d' | sort -u)"
			printf '%s\n' "$here" | grep -qvE "$OWNED" && break
		fi
		cur="$(git commit-tree "$(printf '%s\n' "$out" | head -1)" -p "$cur" -m "land_rebase --would" 2>/dev/null)" ||
			{ echo "land_rebase: could not replay $(printf '%s' "$pick" | cut -c1-9)"; exit 2; }
	done
	if [ -z "$files" ]; then
		state=clean
	elif printf '%s\n' "$files" | grep -qvE "$OWNED"; then
		state=conflict
	else
		state=resolvable
	fi
	listed="$(printf '%s\n' "$files" | sed '/^$/d' | words)"
	before="$(cut -d' ' -f2,3 "$LOCK.would/$tree" 2>/dev/null)"
	mark $state "$listed"
	case $state in
		clean) echo "clean (onto $short)" ;;
		resolvable) echo "resolvable: $listed (onto $short)" ;;
		conflict) echo "CONFLICT: $(printf '%s\n' "$files" | grep -vE "$OWNED" | words) (onto $short)$(printf '%s\n' "$files" | grep -qE "$OWNED" && printf '; and the resolvers'"'"' %s' "$(printf '%s\n' "$files" | grep -E "$OWNED" | words)")" ;;
	esac
	if [ "$before" != "$onto $state" ]; then
		case $state in
			conflict) log "land_rebase $tree: would conflict onto $short in $listed: rebase before its turn (394 amended (65))" ;;
			resolvable) log "land_rebase $tree: would stop onto $short on $listed only, which the resolvers take" ;;
			clean) [ -n "$before" ] && log "land_rebase $tree: clean onto $short" ;;
		esac
	fi
	[ $state = conflict ] && exit 1
	exit 0
fi

# A rebase stopped here is read from its folders: REBASE_HEAD stays behind after a finished rebase.
stopped_here() { [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; }
if stopped_here; then
	echo "land_rebase: a rebase is already stopped in this checkout: finish or abort it first"; exit 2
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
	echo "land_rebase: tracked changes not committed here: commit them first"; git status --short --untracked-files=no | head -5; exit 2
fi
start="$(git rev-parse HEAD)"
give_up() {
	git rebase --abort >/dev/null 2>&1
	if [ "$(git rev-parse HEAD)" != "$start" ]; then git reset -q --hard "$start" 2>/dev/null; fi
	echo "REBASE CONFLICT onto $short: $1"
	log "land_rebase $tree: stopped onto $short: $1; aborted, the checkout as it was"
	mark conflict "$2"
	exit 1
}
if git rebase -q "$onto" >/dev/null 2>&1; then
	echo "rebased onto $short"
	log "land_rebase $tree: rebased onto $short"
	mark rebased ""
	exit 0
fi
resolved=""
stops=0
while :; do
	stops=$((stops + 1))
	[ $stops -le $STOPS_MOST ] || give_up "more than $STOPS_MOST stops" ""
	stopped_here || break
	at="$(git rev-parse -q --verify REBASE_HEAD)" || give_up "the rebase stopped on no commit" ""
	conflicted="$(git diff --name-only --diff-filter=U)"
	if [ -n "$conflicted" ]; then
		others="$(printf '%s\n' "$conflicted" | grep -vE "$OWNED" | words)"
		[ -z "$others" ] || give_up "$others, at $(printf '%s' "$at" | cut -c1-9) (not the resolvers' files)" "$(printf '%s\n' "$conflicted" | words)"
		lists="$(printf '%s\n' "$conflicted" | grep -E "$LISTS")"
		if [ -n "$lists" ]; then
			$LISTS_FIX >/dev/null 2>&1 || give_up "the lists' merge refused $(printf '%s\n' "$lists" | words) at $(printf '%s' "$at" | cut -c1-9)" "$(printf '%s\n' "$conflicted" | words)"
			git add -- $lists || give_up "could not stage $(printf '%s\n' "$lists" | words)" ""
		fi
		rest="$(git diff --name-only --diff-filter=U)"
		if [ -n "$rest" ]; then
			said="$($RESOLVER 2>&1)" || give_up "the resolver refused $(printf '%s\n' "$rest" | words) at $(printf '%s' "$at" | cut -c1-9): $(printf '%s' "$said" | tail -1 | head -c 200)" "$(printf '%s\n' "$conflicted" | words)"
		fi
		[ -z "$(git diff --name-only --diff-filter=U)" ] || give_up "$(git diff --name-only --diff-filter=U | words) still in conflict after the resolvers" ""
		resolved="$resolved$(printf '%s\n' "$conflicted")
"
	fi
	if GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then
		break
	fi
	stopped_here || give_up "the rebase could not go on" ""
	now="$(git rev-parse -q --verify REBASE_HEAD)" || give_up "the rebase could not go on" ""
	if [ "$now" = "$at" ] && [ -z "$(git diff --name-only --diff-filter=U)" ]; then
		# A commit the resolvers left empty (it only touched a page main has made again): dropped,
		# as the rebase drops one already on main. Never a commit with anything staged.
		if git diff --cached --quiet && GIT_EDITOR=true git rebase --skip >/dev/null 2>&1; then
			break
		fi
		stopped_here || break
		[ "$(git rev-parse -q --verify REBASE_HEAD)" != "$at" ] && continue
		give_up "the rebase would not go past $(printf '%s' "$at" | cut -c1-9)" ""
	fi
done
listed="$(printf '%s' "$resolved" | sed '/^$/d' | sort -u | words)"
echo "rebased onto $short${listed:+; resolved: $listed}"
log "land_rebase $tree: rebased onto $short${listed:+, resolved $listed}"
mark rebased "$listed"
exit 0
