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
TOKEN=test-secret

start() {
	name="$1"
	shift
	"$GODOT" --headless --path . "$@" "--port=$PORT" >"$LOGS/$name.log" 2>"$LOGS/$name.err" &
}

start server --server "--token=$TOKEN" --test-exit-after=16
sleep 2
start client1 --client --address=127.0.0.1 "--token=$TOKEN" --test-move=-3,0 --test-contest=9,1,70 --test-exit-after=9
# Client 1 joins first so it is Player1 at (11, 2); three tiles west is Crate1,
# so its move ends by pushing the crate to (7, 2). Client 2 joins after that
# to the start tile client 1 left and walks to (9, 2). Both are then one step
# from (9, 1), and at server tick
# 70 both order a move into it. Each client predicts the step; the server lets
# only one of them have the tile.
sleep 1
start client2 --client --address=127.0.0.1 "--token=$TOKEN" --test-move=-2,0 --test-contest=9,1,70 --test-exit-after=9
# A third client with the wrong token must be rejected and never get a player.
sleep 1
start client3 --client --address=127.0.0.1 --token=wrong-secret --test-move=0,1 --test-exit-after=4
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

check "$joined" 2 "server spawned a player for each client with the right token"
check "$(count '\[net\] peer [0-9]+ authenticated' "$LOGS/server.log")" 2 "server authenticated the two right-token clients"
check "$(count '\[net\] rejected peer [0-9]+ from [^ ]+ \(wrong token\)' "$LOGS/server.log")" 1 "server rejected the wrong-token client with its address"
check "$(count 'authentication failed' "$LOGS/client3.log")" 1 "the wrong-token client reports authentication failed"
check "$(count '\[test\] Player' "$LOGS/client3.log")" 0 "and never got a player to order around"
check "$movers" 2 "server log shows both players moved"
check "$rejected" 0 "server rejected no orders"
check "$inconsistent" 0 "occupancy was consistent at every logged move, on server and clients"
check "$final" 1 "server occupancy consistent at exit"
check "$arrived1" 1 "client 1 saw its own move replicated"
check "$arrived2" 1 "client 2 saw its own move replicated"
pushed=$(count 'push: Player1 -> Crate1' "$LOGS/server.log")
check "$pushed" 1 "server log shows Player1 pushing Crate1"
for name in server client1 client2; do
	crate=$(count '\[test\] tiles: .*Crate1=\(7, 2\)' "$LOGS/$name.log")
	check "$crate" 1 "$name has the pushed crate at (7, 2)"
done
clients="$LOGS/client1.log $LOGS/client2.log"
contest=$(count 'moved .* -> \(9, 1\)' "$LOGS/server.log")
check "$contest" 1 "exactly one player took the contested tile (9, 1) on the server"
shown=$(cat $clients | grep -c 'display: .*server_tile=\(([^)]*)\) shown_tile=\1 ' || true)
check "$shown" 2 "both clients end up showing their player on the server's tile"
winner=$(cat $clients | grep -cE 'display: .*server_tile=\(9, 1\) .*mispredicts=0' || true)
check "$winner" 1 "the winner is on (9, 1) with no mispredictions"
loser=$(cat $clients | grep -E 'display: .*mispredicts=1' | grep -vc 'server_tile=(9, 1)' || true)
check "$loser" 1 "the loser is not on (9, 1) and counted exactly one misprediction"
predicted=$(cat $clients | grep -cE 'mispredict: Player[0-9]+ predicted \(9, 1\)' || true)
check "$predicted" 1 "the loser had predicted (9, 1) before snapping back"
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
