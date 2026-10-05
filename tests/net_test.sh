#!/usr/bin/env sh
# Network test: one headless --server and two headless --client instances on
# localhost. Each client orders its player to move; the server's log must show
# both players moving with a consistent occupancy map.
# Exit code 0 = all assertions passed, 1 = any failed.
# Godot is taken from $GODOT_PATH, or `godot` on PATH.
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
LOGS="$(mktemp -d)"
PORT=17777

start() {
	name="$1"
	shift
	"$GODOT" --headless --path . "$@" "--port=$PORT" >"$LOGS/$name.log" 2>"$LOGS/$name.err" &
}

start server --server --test-exit-after=12
sleep 2
start client1 --client --address=127.0.0.1 --test-move=-2,0 --test-exit-after=7
start client2 --client --address=127.0.0.1 --test-move=0,1 --test-exit-after=8
wait

failures=0
check() {
	if [ "$1" = "$2" ]; then
		echo "  PASS  $3"
	else
		echo "  FAIL  $3 (got $1, want $2)"
		failures=$((failures + 1))
	fi
}
count() { grep -cE "$1" "$2" 2>/dev/null || true; }

joined=$(count '\[net\] peer [0-9]+ joined as Player' "$LOGS/server.log")
movers=$(grep -oE '\[net\] Player[0-9]+ \(peer [0-9]+\) moved' "$LOGS/server.log" 2>/dev/null |
	grep -oE 'Player[0-9]+' | sort -u | wc -l | tr -d ' ')
rejected=$(count 'rejected order' "$LOGS/server.log")
inconsistent=$(cat "$LOGS"/*.log 2>/dev/null | grep -c 'occupancy_consistent=false' || true)
final=$(count '\[test\] final .*occupancy_consistent=true' "$LOGS/server.log")
arrived1=$(count '\[test\] Player[0-9]+ arrived' "$LOGS/client1.log")
arrived2=$(count '\[test\] Player[0-9]+ arrived' "$LOGS/client2.log")

check "$joined" 2 "server spawned a player for each client"
check "$movers" 2 "server log shows both players moved"
check "$rejected" 0 "server rejected no orders"
check "$inconsistent" 0 "occupancy was consistent at every logged move, on server and clients"
check "$final" 1 "server occupancy consistent at exit"
check "$arrived1" 1 "client 1 saw its own move replicated"
check "$arrived2" 1 "client 2 saw its own move replicated"
errors=$(cat "$LOGS"/*.err 2>/dev/null | wc -l | tr -d ' ')
check "$errors" 0 "no instance printed errors"

echo
if [ "$failures" -gt 0 ]; then
	echo "--- server log ($LOGS) ---"
	cat "$LOGS/server.log"
	echo "RESULT: FAIL ($failures failed)"
	exit 1
fi
echo "RESULT: PASS (logs in $LOGS)"
exit 0
