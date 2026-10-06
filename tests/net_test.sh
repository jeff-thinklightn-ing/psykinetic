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
STATE="$LOGS/world.json"
# Fixed identities for the players whose return we check.
ID_C=c0ffee00-0000-4000-8000-00000000000c
ID_D=d0d0d0d0-0000-4000-8000-00000000000d

start() {
	name="$1"
	shift
	"$GODOT" --headless --path . "$@" "--port=$PORT" >"$LOGS/$name.log" 2>"$LOGS/$name.err" &
}

start server --server "--token=$TOKEN" "--state=$STATE" --test-exit-after=16
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
# A fourth joins with no mode argument, from a settings file like an exported client.
printf 'address=127.0.0.1\nport=%s\ntoken=%s\nplayer_id=%s\nname=Casey\n' "$PORT" "$TOKEN" "$ID_C" >"$LOGS/settings.cfg"
sleep 1
start client4 "--settings=$LOGS/settings.cfg" --test-move=0,1 --test-exit-after=4
# A fifth has the right token but claims another version: turned away as out of date.
start client5 --client --address=127.0.0.1 "--token=$TOKEN" --test-version=0.0.1 --test-exit-after=4
wait

# Phase 2: the server restarts from its snapshot. Casey (client 4's id) must
# come back where she left, Dana is new, and a second Casey is turned away.
start server2 --server "--token=$TOKEN" "--state=$STATE" --test-exit-after=10
sleep 2
start clientC "--settings=$LOGS/settings.cfg" --test-exit-after=6
sleep 1
start clientD --client --address=127.0.0.1 "--token=$TOKEN" "--player-id=$ID_D" --name=Dana --test-exit-after=4
start clientE --client --address=127.0.0.1 "--token=$TOKEN" "--player-id=$ID_C" --name=Impostor --test-exit-after=3
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

joined=$(count '\[net\] .+ \([a-z0-9-]+\) joined as Player' "$LOGS/server.log")
movers=$(grep -oE '\[net\] Player[12] \(peer [0-9]+\) moved' "$LOGS/server.log" 2>/dev/null |
	grep -oE 'Player[0-9]+' | sort -u | wc -l | tr -d ' ')
rejected=$(count 'rejected order' "$LOGS/server.log")
inconsistent=$(cat "$LOGS"/*.log 2>/dev/null | grep -c 'occupancy_consistent=false' || true)
final=$(count '\[test\] final .*occupancy_consistent=true' "$LOGS/server.log")
arrived1=$(count '\[test\] Player[0-9]+ arrived' "$LOGS/client1.log")
arrived2=$(count '\[test\] Player[0-9]+ arrived' "$LOGS/client2.log")

check "$joined" 3 "server spawned a player for each client with the right token and version"
check "$(count '\[net\] peer [0-9]+ authenticated' "$LOGS/server.log")" 3 "server authenticated the three good clients"
check "$(count '\[net\] using .*settings\.cfg' "$LOGS/client4.log")$(count '\[test\] Player[0-9]+ arrived' "$LOGS/client4.log")" 11 "a client with no arguments joins from settings.cfg and plays"
check "$(count '\[net\] rejected peer [0-9]+ from [^ ]+ \(client 0\.0\.1, server ' "$LOGS/server.log")" 1 "server rejected the out-of-date client, naming both versions"
check "$(count '\[net\] client out of date' "$LOGS/client5.log")" 1 "the out-of-date client was told so"
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
check "$(count '\[net\] Casey \(c0ffee00\) joined as Player3 at ' "$LOGS/server.log")" 1 "phase 1: Casey joined as Player3"
check "$(count '\[net\] Casey \(c0ffee00\) left' "$LOGS/server.log")" 1 "phase 1: her leaving was logged with her name and id"
check "$(count '\[state\] loaded 9 entities and 3 player records' "$LOGS/server2.log")" 1 "phase 2: the restarted server loads three player records"
color_before=$(grep -oE 'display: Player3 .*color=[0-9a-f]+' "$LOGS/client4.log" | grep -oE 'color=[0-9a-f]+' | head -1)
color_after=$(grep -oE 'display: Player3 server_tile=\(11, 3\).*color=[0-9a-f]+' "$LOGS/clientC.log" | grep -oE 'color=[0-9a-f]+' | head -1)
check "$([ -n "$color_before" ] && echo "$color_after")" "$color_before" "phase 2: Casey is back on (11, 3) as Player3 in her colour"
check "$(count '\[net\] Casey \(c0ffee00\) joined as Player3 at \(11, 3\) \(back\)' "$LOGS/server2.log")" 1 "phase 2: the server says she joined back"
check "$(count '\[net\] Dana \(d0d0d0d0\) joined as Player4 at \([0-9]+, [0-9]+\)$' "$LOGS/server2.log")" 1 "phase 2: a new id gets a fresh spawn as Player4"
check "$(count '\[net\] rejected peer [0-9]+ from [^ ]+ \(already connected as c0ffee00\)' "$LOGS/server2.log")" 1 "phase 2: a second connection with an online id is rejected"
check "$(count '\[net\] already connected' "$LOGS/clientE.log")" 1 "phase 2: and told so"
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
