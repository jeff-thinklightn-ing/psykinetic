#!/usr/bin/env bash
# A player's own wind-up given up on a real client (392 amended): a headless
# server on test_room gives the joining player WEAPON in hand and a FOE three
# cells east (--test-foe); one headless WASD client strikes it (--test-fight)
# and, once its own wind-up begins, holds KEYS (--test-walk-on-wind). Prints
# the client's wind-walk lines (each winding, each hurt, where it is shown
# every few frames) and the server's wind-up lines (began, given up, struck).
#   tools/net_wind.sh <keys:secs,...> [foe=skeleton] [weapon=battle_axe]
# At the camera's start yaw S is (+1,+1)/sqrt 2, A (-1,+1), W (-1,-1), D (+1,-1).
# The run's user data is a temp folder of its own (user:// is shared).
set -u
GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe) console="${GODOT%.exe}_console.exe"; [ -f "$console" ] && GODOT="$console" ;;
esac
KEYS="${1:?keys:secs, e.g. s:2}"
cd "$(dirname "$0")/.."
. tests/godot_log.sh  # Its logs in build/logs (decision 664).
. tests/test_ports.sh
PORT=$((17980 + PORT_OFFSET))
LOGS="$(mktemp -d)"
mkdir -p "$LOGS/appdata"
export APPDATA="$(cygpath -w "$LOGS/appdata" 2>/dev/null || echo "$LOGS/appdata")"
timeout 120 "$GODOT" --log-file "$(godot_log wind_server)" --headless --path . --server --map=test_room --no-companions --token=wind \
	"--port=$PORT" --test-wait-players=1 "--test-foe=${2:-skeleton},${3:-battle_axe}" --test-exit-after=60 </dev/null >"$LOGS/server.log" 2>&1 &
server=$!
waited=0
until grep -q "listening on port" "$LOGS/server.log" 2>/dev/null; do
	waited=$((waited + 1))
	[ "$waited" -gt 240 ] && { echo "the server never listened"; kill "$server" 2>/dev/null; exit 1; }
	sleep 0.25
done
timeout 100 "$GODOT" --log-file "$(godot_log wind_client)" --headless --path . --client --address=127.0.0.1 --token=wind "--port=$PORT" \
	--controls=wasd --test-fight=0.5 "--test-walk=$KEYS" --test-walk-on-wind --test-exit-after=25 </dev/null >"$LOGS/client.log" 2>&1
wait "$server"
echo "client:"
grep -E "^\[test\] (wind-walk|walk:)|SCRIPT ERROR|^ERROR" "$LOGS/client.log"
echo "server:"
grep -E "^\[test\] foe|windup:|SCRIPT ERROR|^ERROR" "$LOGS/server.log"
rm -rf "$LOGS"
