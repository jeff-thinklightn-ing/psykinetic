# Sourced by tools/remote_shot.sh (828 amended (3)): which of a runner clone's
# untracked files a checkout of the run's commit would overwrite. A laptop's own
# import writes a script's .gd.uid or an image's .import before the tree that
# made it commits it; the checkout then refuses ("untracked working tree files
# would be overwritten"), and every run at a later main stopped there (maps,
# 2026-11-12: fish_click.gd.uid, committed in 29be1cf77).
#
# clashes TRACKED UNTRACKED: each file named in both (one path a line, forward
# slashes) on a line of its own, "remove <path>" for a generated kind (*.uid,
# *.import: made again by the next import, and the commit's own copy is the one
# wanted) and "stop <path>" for anything else (left alone, the run refused).
clashes() {
	sort -u "$1" > "$1.sorted"
	sort -u "$2" > "$2.sorted"
	comm -12 "$1.sorted" "$2.sorted" | while IFS= read -r path; do
		[ -n "$path" ] || continue
		case "$path" in
			*.uid|*.import) echo "remove $path" ;;
			*) echo "stop $path" ;;
		esac
	done
	rm -f "$1.sorted" "$2.sorted"
}
