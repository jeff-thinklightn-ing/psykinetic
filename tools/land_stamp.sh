# Sourced by tests/land.sh (decision 883): the PASS stamp a push to main needs, and
# the pre-push hook's install. A bash stopped by its Windows PID reads as exit 0
# to its bash parent (TerminateProcess runs no trap; perf's probe, 2026-11-12),
# so a landing script's `bash tests/land.sh && push` pushed a stopped run
# (physics, 03:09). A stamp is written only at a whole run's end, all parts PASS
# and HEAD where it was when the run began; tools/hooks/pre-push refuses a push
# to main without one for the pushed commit.

# The folder every worktree of this clone shares (.git of the main checkout).
land_common_dir() {
	dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
	(cd "$dir" && pwd)
}

# land_stamp_write START_HEAD TREE LINE: the stamp for HEAD, if HEAD is still
# START_HEAD. Prints what it did; 1 when it wrote none.
land_stamp_write() {
	start="$1"; tree="$2"; line="$3"
	head="$(git rev-parse HEAD 2>/dev/null)" || { echo "push stamp: none (no HEAD)"; return 1; }
	if [ "$head" != "$start" ]; then
		echo "push stamp: none: HEAD moved during the run ($start to $head); run land.sh on the commit you push"
		return 1
	fi
	common="$(land_common_dir)" || { echo "push stamp: none (no git folder)"; return 1; }
	mkdir -p "$common/land_pass" || return 1
	# Stamps over two days old go (a commit not pushed by then is retested anyway).
	find "$common/land_pass" -type f -mtime +2 -delete 2>/dev/null
	printf 'tree=%s\ntime=%s\nline=%s\n' "$tree" "$(date +%Y-%m-%dT%H:%M:%S)" "$line" > "$common/land_pass/$head.tmp" \
		&& mv -f "$common/land_pass/$head.tmp" "$common/land_pass/$head" || return 1
	echo "push stamp: $head may be pushed to main (tools/hooks/pre-push)"
}

# The hook in the shared hooks folder, from origin/main's copy (never a
# branch's), when origin/main's tools/hooks/install says "on" and release has
# not lifted it (a file hooks/pre-push.lifted). Quiet unless it changes it.
land_hook_install() {
	common="$(land_common_dir)" || return 0
	[ "$(git show origin/main:tools/hooks/install 2>/dev/null | tr -d '\r' | head -1)" = "on" ] || return 0
	[ -e "$common/hooks/pre-push.lifted" ] && return 0
	mkdir -p "$common/hooks" || return 0
	git show origin/main:tools/hooks/pre-push > "$common/hooks/pre-push.new" 2>/dev/null || return 0
	if ! cmp -s "$common/hooks/pre-push.new" "$common/hooks/pre-push" 2>/dev/null; then
		mv -f "$common/hooks/pre-push.new" "$common/hooks/pre-push" && chmod +x "$common/hooks/pre-push" \
			&& echo "push guard: the pre-push hook installed from origin/main"
	fi
	rm -f "$common/hooks/pre-push.new"
}
