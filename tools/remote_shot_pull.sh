# tools/remote_shot_pull.sh, sourced by tools/remote_shot.sh (828 amended (15), the coordinator's
# terms, 2026-11-16): whether a pull-back came back whole. pc-character's root3_12b on the Atlas
# came back with 61 of 112 stills and no godot.log while C: was nearly full; scp's errors went to
# /dev/null, the laptop's copy was then removed, and the joined check called a client that had
# joined "never connected" off the godot.log that never came.
#
# pull_short <folder>, the laptop runner's manifest on stdin (-Mode manifest: "out/<path>|<bytes>"
# and "godot.log|<bytes>", one a line): prints "<n> of <m> files" and what is short (the first
# five missing, the first five of a wrong size), and returns 0 only when every listed file is in
# <folder> at its size (out/<path> is <folder>/<path>, godot.log <folder>/godot.log). An empty
# manifest is never whole: nothing proves the copy.
pull_short() {
	local folder="$1" line path size here got total=0 have=0 nmiss=0 nwrong=0 missing="" wrong="" words
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		[ -n "$line" ] || continue
		case "$line" in *"|"*) ;; *) continue ;; esac
		path="${line%|*}"
		size="${line##*|}"
		case "$path" in
			out/*) here="$folder/${path#out/}" ;;
			godot.log) here="$folder/godot.log" ;;
			*) continue ;;
		esac
		total=$((total + 1))
		if [ ! -f "$here" ]; then
			nmiss=$((nmiss + 1))
			[ $nmiss -le 5 ] && missing="$missing${missing:+, }$path"
			continue
		fi
		got="$(wc -c < "$here" | tr -d ' ')"
		if [ "$got" != "$size" ]; then
			nwrong=$((nwrong + 1))
			[ $nwrong -le 5 ] && wrong="$wrong${wrong:+, }$path ($got of $size bytes)"
			continue
		fi
		have=$((have + 1))
	done
	words="$have of $total files"
	[ $total -gt 0 ] || words="no file listed by the laptop"
	[ $nmiss -eq 0 ] || words="$words; missing $nmiss: $missing$([ $nmiss -gt 5 ] && echo ", ...")"
	[ $nwrong -eq 0 ] || words="$words; a wrong size $nwrong: $wrong$([ $nwrong -gt 5 ] && echo ", ...")"
	printf '%s\n' "$words"
	[ $total -gt 0 ] && [ $have -eq $total ]
}
