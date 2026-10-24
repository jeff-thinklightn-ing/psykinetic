# Where a Godot the tooling runs writes its log (decision 664): this
# checkout's build/logs/<name>.log, never the shared user:// logs folder,
# whose few kept files are Jeff's client's (a test's godot.log rotated his
# draugr fight's out). Sourced from the checkout's root, after its cd:
#   . tests/godot_log.sh
#   "$GODOT" --log-file "$(godot_log net_host)" --headless ...
# Each Godot running at the same time takes a name of its own.
godot_log() {
	mkdir -p build/logs
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -w "$(pwd)/build/logs/$1.log"
	else
		echo "$(pwd)/build/logs/$1.log"
	fi
}
