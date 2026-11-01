#!/usr/bin/env sh
# A playtest tour (tests/tour/): a local headless server on the world's own
# levels, and one client that joins it as a player and plays the tour.
#   sh tools/tour.sh <tour> [--offscreen]
# Run it through the gate: sh tools/heavy_job.sh run <tree> scene -- sh tools/tour.sh <tour>
# The client is headless unless --offscreen (a window at 4000,4000, silent,
# for stills). Everything it writes goes in build/tours/<tour>/: report.md,
# server.log, client.log, stills, and the temp APPDATA both run under, so
# nothing touches the shared user:// folder or the box.
# Exit: the client's (0 every check passed, 1 one failed, 2 never joined).
set -u
cd "$(dirname "$0")/.."
TOUR="${1:-smoke}"
VIEW="${2:-}"

GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe)
		console="${GODOT%.exe}_console.exe"
		if [ -f "$console" ]; then GODOT="$console"; fi
		;;
esac

. tests/test_ports.sh
. tests/godot_log.sh  # Each launch its own log in build/logs (decision 664).
PORT=$((17800 + PORT_OFFSET))
ADMIN=$((PORT + 1))
TOKEN=tour-secret
# A local test player only, never a real one.
PLAYER=70a70000-0000-4000-8000-000000000001

DIR="build/tours/$TOUR"
rm -rf "$DIR"
mkdir -p "$DIR/appdata"

# The tour's scripts parsed first: one that will not load leaves the client
# with nothing to quit it. (--check-only has no autoloads, so only parse
# errors count here; "Identifier not found: World" is that, not a fault.)
for script in tests/tour/bot.gd tests/tour/tour.gd "tests/tour/tours/$TOUR.gd"; do
	if [ ! -f "$script" ]; then
		echo "tour: no $script"
		exit 2
	fi
	if /usr/bin/timeout 120 "$GODOT" --log-file "$(godot_log tour_parse)" --headless --audio-driver Dummy --path . --check-only --script "res://$script" </dev/null 2>&1 \
			| grep -A1 "SCRIPT ERROR: Parse Error" >"$DIR/parse.txt"; then
		echo "tour: $script does not parse:"
		cat "$DIR/parse.txt"
		exit 2
	fi
done
WIN_DIR="$(cygpath -w "$(pwd)/$DIR")"
APPDATA_DIR="$(cygpath -w "$(pwd)/$DIR/appdata")"
STOP="$DIR/stop"

# --regenerate as the box runs (server/psykinetic.service): the shifting
# levels laid when due; without it a fresh barrow is its rooms, unjoined.
APPDATA="$APPDATA_DIR" /usr/bin/timeout 2400 "$GODOT" --log-file "$(godot_log "tour_${TOUR}_server")" --headless --audio-driver Dummy --path . --server --regenerate --bind=127.0.0.1 \
	"--port=$PORT" "--admin-port=$ADMIN" "--state=$WIN_DIR\\world.json" "--token=$TOKEN" \
	"--test-exit-on=$WIN_DIR\\stop" --test-exit-after=2300 \
	</dev/null >"$DIR/server.log" 2>&1 &
server=$!
for _ in $(seq 1 960); do
	grep -q "\[admin\] console on" "$DIR/server.log" 2>/dev/null && break
	kill -0 "$server" 2>/dev/null || break
	sleep 0.25
done
if ! grep -q "\[admin\] console on" "$DIR/server.log"; then
	echo "tour: the server never opened its console (see $DIR/server.log)"
	touch "$STOP"
	wait "$server"
	exit 2
fi

if [ "$VIEW" = "--offscreen" ]; then
	DISPLAY_ARGS="--position 4000,4000 --audio-driver Dummy"
else
	DISPLAY_ARGS="--headless --audio-driver Dummy"
fi
# shellcheck disable=SC2086
APPDATA="$APPDATA_DIR" /usr/bin/timeout 1500 "$GODOT" --log-file "$(godot_log "tour_${TOUR}_client")" $DISPLAY_ARGS --path . --scene res://tests/tour/tour.tscn -- \
	--client --address=127.0.0.1 "--port=$PORT" "--token=$TOKEN" --name=Tourbot "--player-id=$PLAYER" \
	"--tour=$TOUR" "--tour-admin=$ADMIN" "--tour-out=$WIN_DIR" --test-exit-after=1450 \
	</dev/null >"$DIR/client.log" 2>&1
code=$?
touch "$STOP"
wait "$server"
grep -E "^\[tour\]|^RESULT" "$DIR/client.log"
grep -E "ERROR|SCRIPT ERROR" "$DIR/client.log" | head -20
echo "tour $TOUR: exit $code; report $DIR/report.md"
exit "$code"
