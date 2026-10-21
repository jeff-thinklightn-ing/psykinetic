#!/usr/bin/env bash
# The server as the box runs it (decision 450): the "Linux Server" preset
# exported as a pack (the box's own export: dedicated_server, art/audio left
# out, scripts as binary tokens) and booted by this Godot's Windows release
# template, the same runtime as the box's, beside it under the pack's name,
# on a fresh user:// with no snapshot; a headless client joins so a zone
# wakes and ticks. Fails on a failed export or boot, no client joining, or
# any "SCRIPT ERROR" / "ERROR:" line: what only the exported pack hits (a
# resource the filters leave out, a script that loads only in the editor)
# turned up first on the box. The server listens on 127.0.0.1 only (--bind)
# and runs from one path per checkout (build/server_boot), so Windows'
# firewall, which asks once per program path for a listener on every
# address, doesn't ask on each landing (450 amended; Jeff had about twenty
# prompts in an evening from a fresh temp folder each time).
#   tests/server_boot_test.sh   exit 0 = it boots clean
# Godot is taken from $GODOT_PATH, or `godot` on PATH; the templates from
# Godot's export_templates folder for its version.
set -u

GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe)
		console="${GODOT%.exe}_console.exe"
		if [ -f "$console" ]; then GODOT="$console"; fi
		;;
esac

cd "$(dirname "$0")/.."
. tests/test_ports.sh
PORT=$((17892 + PORT_OFFSET))
ADMIN=$((PORT + 1))
STATUS=$((PORT + 2))
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
BIN=build/server_boot
mkdir -p "$BIN"

fail() {
	echo "FAIL  $1"
	for log in "$DIR"/*.log; do
		[ -f "$log" ] && { echo "--- $(basename "$log")"; grep -v "savepack\|^\[test\] \(tiles\|slots\)" "$log" | tail -40; }
	done
	echo
	echo "RESULT: FAIL"
	exit 1
}

version="$("$GODOT" --version | cut -d. -f1-4)"
templates="${APPDATA:-}/Godot/export_templates/$version"
[ -f "$templates/windows_release_x86_64.exe" ] || fail "no Windows release template for $version in $templates (the editor's Export > Manage Export Templates)"

started=$(date +%s)
"$GODOT" --headless --path . --export-pack "Linux Server" "$(cygpath -w "$DIR/server.pck")" </dev/null >"$DIR/export.log" 2>&1 \
	|| fail "the Linux Server pack did not export"
[ -s "$DIR/server.pck" ] || fail "the export made no pack"
echo "PASS  the Linux Server pack exported ($(( $(date +%s) - started )) s, $(du -k "$DIR/server.pck" | cut -f1) KB)"

# The template finds server.pck beside server.exe; release templates refuse
# --main-pack. The console wrapper runs server.exe and passes its output.
cp "$DIR/server.pck" "$BIN/server.pck" || fail "could not copy the pack to $BIN (a server from an earlier run still running?)"
cp "$templates/windows_release_x86_64.exe" "$BIN/server.exe" || fail "could not copy the template to $BIN"
cp "$templates/windows_release_x86_64_console.exe" "$BIN/server.console.exe" || fail "could not copy the console template to $BIN"
mkdir -p "$DIR/appdata"
started=$(date +%s)
# Waits on lines, not times: beside the suite a client took over 6 s to join
# (perf's first landing of this). The server's own exit bounds the run.
APPDATA="$(cygpath -w "$DIR/appdata")" timeout 120 "$BIN/server.console.exe" --headless --server --bind=127.0.0.1 "--port=$PORT" "--admin-port=$ADMIN" \
	"--status-port=$STATUS" "--state=$(cygpath -w "$DIR/world.json")" --token=boottest --test-exit-after=45 </dev/null >"$DIR/server.log" 2>&1 &
server=$!
for _ in $(seq 1 120); do
	grep -q "server listening" "$DIR/server.log" 2>/dev/null && break
	kill -0 "$server" 2>/dev/null || break
	sleep 0.25
done
# Where it listens, while it runs: 127.0.0.1, not every address.
netstat -an -p UDP 2>/dev/null | grep -E "[:.]$PORT[[:space:]]" >"$DIR/bound.txt"
APPDATA="$(cygpath -w "$DIR/appdata")" timeout 60 "$GODOT" --headless --path . --client --address=127.0.0.1 "--port=$PORT" --token=boottest \
	--name=BootTest --player-id=b0070000-0000-4000-8000-000000000001 --test-exit-after=25 </dev/null >"$DIR/client.log" 2>&1 &
client=$!
wait "$client"
wait "$server"
code=$?
[ "$code" -eq 0 ] || fail "the exported server exited $code"
echo "PASS  the exported server booted and quit cleanly ($(( $(date +%s) - started )) s)"
grep -q "server listening on port $PORT" "$DIR/server.log" || fail "the server never listened"
grep -q "joined as" "$DIR/server.log" || fail "no client joined the exported server"
echo "PASS  a client joined it"
grep -q "127.0.0.1:$PORT" "$DIR/bound.txt" || fail "the server's UDP $PORT was not seen on 127.0.0.1 ($(tr -s ' ' <"$DIR/bound.txt" | head -2))"
grep -q "0.0.0.0:$PORT\|\*:$PORT\|\[::\]:$PORT" "$DIR/bound.txt" && fail "the server listens on every address on UDP $PORT, not 127.0.0.1 alone"
echo "PASS  it listened on 127.0.0.1 alone"
errors="$(grep -h -E "SCRIPT ERROR|^ERROR:" "$DIR/export.log" "$DIR/server.log")"
[ -z "$errors" ] || { echo "$errors" | head -20; fail "errors in the export or the exported server's log"; }
echo "PASS  no errors in the export or the server's log"
echo
echo "RESULT: PASS"
