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
TOUR_SERVER_ARGS="${TOUR_SERVER_ARGS:-}"
# TOUR_MINUTES: the tour's own watchdog (tour.gd), the client's and server's limits after it.
TOUR_MINUTES="${TOUR_MINUTES:-20}"
CLIENT_SECONDS=$((TOUR_MINUTES * 60 + 250))
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
WIN_DIR="$(cygpath -w "$(pwd)/$DIR")"
APPDATA_DIR="$(cygpath -w "$(pwd)/$DIR/appdata")"
# Every Godot this script starts runs with APPDATA in this checkout's own
# build/tours/<tour>/appdata (the coordinator, 11-01: a barrow level reached
# the shared overlay at 13:01 and failed every tree's level_test); never the
# shared user:// with its edited-level overlay.
case "$APPDATA_DIR" in
	"$(cygpath -w "$(pwd)")"*build*tours*appdata) ;;
	*) echo "tour: APPDATA $APPDATA_DIR is not this checkout's own; not starting"; exit 2 ;;
esac
[ -d "$DIR/appdata" ] || { echo "tour: no $DIR/appdata; not starting"; exit 2; }

# The tour's scripts parsed first: one that will not load leaves the client
# with nothing to quit it. (--check-only has no autoloads, so only parse
# errors count here; "Identifier not found: World" is that, not a fault.)
for script in tests/tour/bot.gd tests/tour/tour.gd "tests/tour/tours/$TOUR.gd"; do
	if [ ! -f "$script" ]; then
		echo "tour: no $script"
		exit 2
	fi
	if APPDATA="$APPDATA_DIR" /usr/bin/timeout 120 "$GODOT" --log-file "$(godot_log tour_parse)" --headless --audio-driver Dummy --path . --check-only --script "res://$script" </dev/null 2>&1 \
			| grep -A1 "SCRIPT ERROR: Parse Error" >"$DIR/parse.txt"; then
		echo "tour: $script does not parse:"
		cat "$DIR/parse.txt"
		exit 2
	fi
done
STOP="$DIR/stop"

# TOUR_PHASES: the server and the client run this many times on the same
# save (the restart tour: a restart between, as the box's is); each phase
# after the first keeps the one before's logs and report as *_<n>.
TOUR_PHASES="${TOUR_PHASES:-1}"
phase=1
code=0
while [ "$phase" -le "$TOUR_PHASES" ]; do
	if [ "$phase" -gt 1 ]; then
		for f in server.log client.log report.md; do
			[ -f "$DIR/$f" ] && mv "$DIR/$f" "$DIR/${f%.*}_$((phase - 1)).${f##*.}"
		done
		rm -f "$STOP"
		# A tour's seed (the restart tour's: a felled cell and a plot, in the
		# server's own save shape) laid into this run's own local save, the
		# server stopped; never a real world's.
		if [ -f "$DIR/seed.json" ] && [ -f "$DIR/world.json" ]; then
			python -I -B - "$DIR/world.json" "$DIR/seed.json" <<'PY'
import json, sys
world_path, seed_path = sys.argv[1], sys.argv[2]
world = json.load(open(world_path, encoding="utf-8"))
seed = json.load(open(seed_path, encoding="utf-8"))
for zone, cells in seed.get("clearing", {}).items():
    world.setdefault("clearing", {}).setdefault(zone, {}).update(cells)
for zone, plots in seed.get("plots", {}).items():
    world.setdefault("plots", {}).setdefault(zone, []).extend(plots)
with open(world_path, "w", encoding="utf-8", newline="\n") as out:
    json.dump(world, out)
print("tour: seed laid into the save")
PY
		fi
	fi
	# TOUR_SERVER_ARGS: more flags for the server, word-split (e.g.
	# --test-foe=draugr,giant_axe: that weapon in hand, that monster beside).
	# --regenerate as the box runs (server/psykinetic.service): the shifting
	# levels laid when due; without it a fresh barrow is its rooms, unjoined.
	# shellcheck disable=SC2086
	APPDATA="$APPDATA_DIR" /usr/bin/timeout $((CLIENT_SECONDS + 900)) "$GODOT" --log-file "$(godot_log "tour_${TOUR}_server")" --headless --audio-driver Dummy --path . --server --regenerate --bind=127.0.0.1 \
		"--port=$PORT" "--admin-port=$ADMIN" "--state=$WIN_DIR\\world.json" "--token=$TOKEN" \
		"--test-exit-on=$WIN_DIR\\stop" "--test-exit-after=$((CLIENT_SECONDS + 800))" $TOUR_SERVER_ARGS \
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
	# Off-screen (--offscreen, a renderer for stills) or headless; silent either way.
	DISPLAY_ARGS="--headless"; [ "$VIEW" = "--offscreen" ] && DISPLAY_ARGS="--position 4000,4000"
	# shellcheck disable=SC2086
	APPDATA="$APPDATA_DIR" /usr/bin/timeout $((CLIENT_SECONDS + 50)) "$GODOT" --log-file "$(godot_log "tour_${TOUR}_client")" $DISPLAY_ARGS --audio-driver Dummy --path . --scene res://tests/tour/tour.tscn -- \
		--client --address=127.0.0.1 "--port=$PORT" "--token=$TOKEN" --name=Tourbot "--player-id=$PLAYER" \
		"--tour=$TOUR" "--tour-admin=$ADMIN" "--tour-out=$WIN_DIR" "--tour-minutes=$TOUR_MINUTES" "--test-exit-after=$CLIENT_SECONDS" \
		"--tour-phase=$phase" </dev/null >"$DIR/client.log" 2>&1
	phase_code=$?
	[ "$phase_code" -ne 0 ] && code=$phase_code
	touch "$STOP"
	wait "$server"
	phase=$((phase + 1))
done
grep -E "^\[tour\]|^RESULT" "$DIR/client.log"
grep -E "ERROR|SCRIPT ERROR" "$DIR/client.log" | head -20
# Each run kept (coordinator, 11-01: owners match a stall to its logs later):
# build/tours/kept/<tour>_<stamp>, without the temp APPDATA; the newest 30.
KEPT="build/tours/kept/${TOUR}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$KEPT"
find "$DIR" -maxdepth 1 -type f ! -name "world.json*" -exec cp {} "$KEPT/" \;
ls -1d build/tours/kept/*/ 2>/dev/null | sort | head -n -30 | xargs -r rm -rf
echo "tour $TOUR: exit $code; report $DIR/report.md; kept in $KEPT"
exit "$code"
