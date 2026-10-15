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
. tests/test_ports.sh
# The phases run at once (decision 279), each group on ports of its own:
# phases 1 and 2 (2 reads 1's snapshot) on PORT, 3 on PORT + 1, 4 on PORT + 2,
# 5 on PORT + 3 with its console on PORT + 4.
PORT=$((17760 + PORT_OFFSET))
ADMIN=$((PORT + 4))
TOKEN=test-secret
STATE="$LOGS/world.json"
# Fixed identities for the players whose return we check.
ID_C=c0ffee00-0000-4000-8000-00000000000c
ID_D=d0d0d0d0-0000-4000-8000-00000000000d
ID_R=5e5e5e5e-0000-4000-8000-00000000000e

# Every instance quits when the script makes its file ($LOGS/<name>.done),
# once what the phase waits for is in the logs; nothing waits a fixed time,
# so a loaded machine only makes it slower.
# A client in the game sees 20 more ticks before it reports. --test-exit-after
# is only a backstop for a run that hangs.
start() {
	name="$1"
	shift
	"$GODOT" --headless --path . "$@" "--port=$P" "--test-exit-on=$LOGS/$name.done" \
		</dev/null >"$LOGS/$name.log" 2>"$LOGS/$name.err" &
	eval "pid_$name=$!"
}
# The phase's server, which quits last. Its world is test_room, not the
# world's start zone (levels/world_map.json, decision 300).
server() {
	SERVER="$1"
	start "$@" --map=test_room --test-exit-after=300
}
# A client of this phase.
client() {
	CLIENTS="$CLIENTS $1"
	start "$@" --test-exit-after=240
}
# Tells one instance to report and quit, and waits until it has.
quit() {
	touch "$LOGS/$1.done" "$LOGS/$1.done.quit"
	eval "wait \$pid_$1"
}
# The end of a phase: the clients report, and once all have (each one's last
# view still has the others) they quit; then the server.
finish() {
	for name in $CLIENTS; do touch "$LOGS/$name.done"; done
	for name in $CLIENTS; do wait_for "$name" '\[test\] slots: '; done
	for name in $CLIENTS; do quit "$name"; done
	quit "$SERVER"
	CLIENTS=""
}
# Waits until <name>.log has <count> (default 1) lines matching <regex>,
# for WAIT_LIMIT seconds at most; giving up only shows in the checks.
WAIT_LIMIT="${NET_TEST_WAIT:-120}"
wait_for() {
	waited=0
	until [ "$(grep -cE "$2" "$LOGS/$1.log" 2>/dev/null || true)" -ge "${3:-1}" ]; do
		waited=$((waited + 1))
		if [ "$waited" -gt $((WAIT_LIMIT * 4)) ]; then
			echo "  (gave up waiting for /$2/ in $1.log)"
			return 1
		fi
		sleep 0.25
	done
}
# The same, in any one of several logs: wait_any <regex> <name>...
wait_any() {
	regex="$1"
	shift
	waited=0
	while :; do
		for name in "$@"; do
			grep -qE "$regex" "$LOGS/$name.log" 2>/dev/null && return 0
		done
		waited=$((waited + 1))
		if [ "$waited" -gt $((WAIT_LIMIT * 4)) ]; then
			echo "  (gave up waiting for /$regex/ in $*)"
			return 1
		fi
		sleep 0.25
	done
}
# A line to the restart phase's console, its reply printed.
admin() {
	exec 3<>"/dev/tcp/127.0.0.1/$ADMIN"
	printf '%s\n' "$*" >&3
	cat <&3
	exec 3<&-
}
CLIENTS=""
GOOD="--client --address=127.0.0.1 --token=$TOKEN"

phase_1_2() {
	P=$PORT
	# Phase 1. The server's sim waits until both players are in, so its ticks
	# count from the same start whenever each process got going. Client 1 joins
	# first, as Player1 at (11, 2); three tiles west is Crate1, so its move ends
	# by pushing the crate to (7, 2). Client 2 joins as Player2 on the next start
	# tile, (12, 1), and walks to (10, 1). Both are then one step from (9, 1), and
	# at server tick 70 both order a move into it; the server holds tick 70 until
	# both orders are in, so they land on one tick. Each client predicts the
	# step; the server lets only one of them have the tile.
	server server --server --still-monsters --no-companions "--token=$TOKEN" "--state=$STATE" \
		--test-wait-players=2 --test-hold=70,2
	wait_for server 'listening on port'
	client client1 $GOOD --test-move=-3,0 --test-contest=9,1,70
	wait_for server 'joined as Player1 '
	client client2 $GOOD --test-move=-2,0 --test-contest=9,1,70
	wait_any 'reached the contested tile \(9, 1\)' client1 client2
	wait_any 'mispredict: Player[0-9]+ step into \(9, 1\) refused' client1 client2
	# A third client with the wrong token must be rejected and never get a player.
	client client3 --client --address=127.0.0.1 --token=wrong-secret --test-move=0,1
	# A fourth joins with no mode argument, from a settings file like an exported
	# client: once the contest is over, so it is Player3 on (11, 2), which client 1
	# left, and walks to (11, 3).
	printf 'address=127.0.0.1\nport=%s\ntoken=%s\nplayer_id=%s\nname=Casey\n' "$PORT" "$TOKEN" "$ID_C" >"$LOGS/settings.cfg"
	client client4 "--settings=$LOGS/settings.cfg" --test-move=0,1
	# A fifth has the right token but is an older build with another protocol:
	# turned away as out of date (decision 239: only the protocol decides).
	client client5 $GOOD --test-version=0.0.1 --test-protocol=old-build
	# A sixth has the right token and version number but is a different build.
	client client6 $GOOD --test-protocol=stale-build
	# A seventh is a newer build with another protocol: the server is the one out of date.
	client client7 $GOOD --test-version=99.0.0 --test-protocol=new-build
	wait_for client4 '\[test\] Player[0-9]+ arrived'
	wait_for client3 'authentication failed'
	wait_for client5 'client out of date'
	wait_for client6 'build mismatch'
	wait_for client7 'server out of date'
	finish

	# Phase 2: the server restarts from its snapshot. Casey (client 4's id) must
	# come back where she left, a second Casey is turned away while she is on,
	# and Dana is new.
	server server2 --server --still-monsters --no-companions "--token=$TOKEN" "--state=$STATE"
	wait_for server2 'listening on port'
	client clientC "--settings=$LOGS/settings.cfg"
	wait_for server2 'Casey \(c0ffee00\) joined'
	client clientE $GOOD "--player-id=$ID_C" --name=Impostor
	wait_for clientE 'already connected'
	client clientD $GOOD "--player-id=$ID_D" --name=Dana
	wait_for server2 'Dana \(d0d0d0d0\) joined'
	finish
}

phase_3() {
	P=$((PORT + 1))
	# Phase 3: Fay and Gus walk to opposite ends of the two-wide passage along
	# the bottom of the room, then at tick 70 cross it toward each other. Fay is
	# Player1 from (11, 2), Gus Player2 from (12, 1), the sim waiting for both.
	server server3 --server --still-monsters --no-companions "--token=$TOKEN" \
		--test-wait-players=2 --test-hold=70,2
	wait_for server3 'listening on port'
	# Fay is another build with the same protocol: she plays (decision 239).
	client clientF $GOOD --name=Fay --test-version=0.0.2 --test-move=-6,9 --test-contest=12,12,70
	wait_for server3 'Fay \([a-z0-9-]+\) joined as Player1 '
	client clientG $GOOD --name=Gus --test-move=0,10 --test-contest=5,12,70
	wait_for clientF 'reached the contested tile'
	wait_for clientG 'reached the contested tile'
	finish
}

phase_4() {
	P=$((PORT + 2))
	# Phase 4: any player may reset the room. Hal pushes Crate1 west as client 1
	# did; at tick 70 Ivy asks for a reset, as her R key would.
	server server4 --server --still-monsters --no-companions "--token=$TOKEN" --test-wait-players=2
	wait_for server4 'listening on port'
	client clientH $GOOD --name=Hal --test-move=-3,0
	wait_for server4 'Hal \([a-z0-9-]+\) joined as Player1 '
	client clientI $GOOD --name=Ivy --test-reset=70
	wait_for server4 '\[world\] Ivy reset the room'
	wait_for server4 '\[net\] (Hal|Ivy) \([a-z0-9-]+\) joined as Player' 4
	finish
}

phase_5() {
	P=$((PORT + 3))
	# Phase 5: the console's restart (decision 240). Rex walks two tiles west;
	# the server is told to restart in 3 s: it tells him, saves, and exits 75,
	# which systemd would start again: here the script starts it again from the
	# same snapshot. Rex's client reconnects by itself and is put back where he
	# stood.
	server server5 --server --still-monsters --no-companions "--token=$TOKEN" "--state=$LOGS/restart.json" "--admin-port=$ADMIN"
	wait_for server5 'console on'
	client clientR $GOOD --name=Rex "--player-id=$ID_R" --test-move=-2,0
	wait_for clientR '\[test\] Player[0-9]+ arrived'
	# It holds three zones when it goes, as the box does (decision 299).
	admin zone reset sample >/dev/null 2>&1
	admin zone reset castle >/dev/null 2>&1
	admin restart 3 a test >"$LOGS/admin.txt" 2>&1
	restart_code=0
	eval "wait \$pid_server5" || restart_code=$?
	echo "$restart_code" >"$LOGS/restart_code"
	server server6 --server --still-monsters --no-companions "--token=$TOKEN" "--state=$LOGS/restart.json" "--admin-port=$ADMIN"
	wait_for server6 'Rex \(5e5e5e5e\) joined'
	wait_for clientR '\[net\] reconnected'
	finish
	# A server stopped the moment its console is up (its stdin thread still
	# waiting out stdin's end) must exit cleanly too (decision 299).
	server server7 --server --still-monsters --no-companions "--token=$TOKEN" "--admin-port=$ADMIN"
	wait_for server7 'console on'
	admin stop 0 at once >/dev/null 2>&1
	quick_code=0
	eval "wait \$pid_server7" || quick_code=$?
	echo "$quick_code" >"$LOGS/quick_code"
}

# All the groups at once, each in a shell of its own (its instances and
# helpers' state its own); what each printed (a wait given up) after.
for group in phase_1_2 phase_3 phase_4 phase_5; do
	( "$group" ) >"$LOGS/$group.out" 2>&1 &
done
wait
cat "$LOGS"/phase_*.out
restart_code="$(cat "$LOGS/restart_code" 2>/dev/null || echo none)"
quick_code="$(cat "$LOGS/quick_code" 2>/dev/null || echo none)"

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
check "$(count '\[net\] rejected peer [0-9]+ from [^ ]+ \(client v0\.0\.1 protocol old-build, server v[0-9.]+ protocol [0-9a-f]+\)' "$LOGS/server.log")" 1 "server rejected the out-of-date client, naming both builds and protocols"
check "$(count '\[net\] client out of date' "$LOGS/client5.log")" 1 "the out-of-date client was told so"
check "$(count '\[update\] not updating itself: not an exported game' "$LOGS/client5.log")$(count '\[update\]' "$LOGS/client7.log")" 10 "it would update itself if it were an exported game; the newer client, never (decision 241)"
check "$(count '\[net\] server out of date' "$LOGS/client7.log")$(count '\[test\] Player' "$LOGS/client7.log")" 10 "a newer client with another protocol is told the server is out of date, and gets no player"
check "$(count '\[net\] rejected peer [0-9]+ from [^ ]+ \(client v[0-9.]+ protocol stale-build, server v[0-9.]+ protocol [0-9a-f]+\)' "$LOGS/server.log")" 1 "server rejected the same-version, different-build client"
check "$(count '\[net\] build mismatch: this client and the server are different builds' "$LOGS/client6.log")$(count '\[test\] Player' "$LOGS/client6.log")" 10 "that client was told it is a build mismatch and never got a player"
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
predicted=$(cat $clients | grep -cE 'mispredict: Player[0-9]+ step into \(9, 1\) refused' || true)
check "$predicted" 1 "the loser was told its step into (9, 1) was refused and re-planned"
check "$(count '\[net\] Casey \(c0ffee00\) joined as Player3 at ' "$LOGS/server.log")" 1 "phase 1: Casey joined as Player3"
check "$(count '\[net\] Casey \(c0ffee00\) left' "$LOGS/server.log")" 1 "phase 1: her leaving was logged with her name and id"
check "$(count '\[state\] loaded 10 entities and 3 player records' "$LOGS/server2.log")" 1 "phase 2: the restarted server loads three player records"
color_before=$(grep -oE 'display: Player3 .*color=[0-9a-f]+' "$LOGS/client4.log" | grep -oE 'color=[0-9a-f]+' | head -1)
color_after=$(grep -oE 'display: Player3 server_tile=\(11, 3\).*color=[0-9a-f]+' "$LOGS/clientC.log" | grep -oE 'color=[0-9a-f]+' | head -1)
check "$([ -n "$color_before" ] && echo "$color_after")" "$color_before" "phase 2: Casey is back on (11, 3) as Player3 in her colour"
check "$(count '\[net\] Casey \(c0ffee00\) joined as Player3 at \(11, 3\) \(back\)' "$LOGS/server2.log")" 1 "phase 2: the server says she joined back"
check "$(count '\[net\] Dana \(d0d0d0d0\) joined as Player4 at \([0-9]+, [0-9]+\)$' "$LOGS/server2.log")" 1 "phase 2: a new id gets a fresh spawn as Player4"
check "$(count '\[net\] rejected peer [0-9]+ from [^ ]+ \(already connected as c0ffee00\)' "$LOGS/server2.log")" 1 "phase 2: a second connection with an online id is rejected"
check "$(count '\[net\] already connected' "$LOGS/clientE.log")" 1 "phase 2: and told so"
check "$(count '\[test\] Player[0-9]+ arrived' "$LOGS/clientF.log")$(count '\[test\] Player[0-9]+ arrived' "$LOGS/clientG.log")" 11 "phase 3: both reached their ends of the passage"
check "$(count '\[test\] display: .*server_tile=\(12, 12\)' "$LOGS/clientF.log")" 1 "phase 3: Fay crossed to (12, 12)"
check "$(count '\[net\] peer [0-9]+ is v0\.0\.2, the server v[0-9.]+: the same protocol' "$LOGS/server3.log")" 1 "phase 3: Fay is another build with the same protocol, and the server let her play"
check "$(count '\[test\] display: .*server_tile=\(5, 12\)' "$LOGS/clientG.log")" 1 "phase 3: Gus crossed to (5, 12)"
check "$(count '\[update\] the server runs v[0-9.]+, newer than this v0\.0\.2: launch\.bat updates it' "$LOGS/clientF.log")$(count '\[update\]' "$LOGS/clientG.log")" 10 "phase 3: Fay is told once that a newer game is out; Gus, the same build, is not"
check "$(cat "$LOGS/clientF.log" "$LOGS/clientG.log" | grep -c 'display: .*snaps=0 ' || true)" 2 "phase 3: neither client snapped more than 2 tiles"
check "$(count 'push: Player1 -> Crate1' "$LOGS/server4.log")$(count '\[world\] Ivy reset the room' "$LOGS/server4.log")" 11 "phase 4: Hal pushed the crate, then Ivy's reset reached the server"
check "$(count '\[net\] (Hal|Ivy) \([a-z0-9-]+\) joined as Player' "$LOGS/server4.log")" 4 "phase 4: both players were put back into the rebuilt room"
# Hal stood on the crate's spawn tile, so he is put on the nearest free one.
check "$(count '\[test\] tiles: .*Crate1=\(8, 2\).*Player1=\(9, 2\) Player2=' "$LOGS/clientI.log")" 1 "phase 4: Ivy sees Crate1 back at (8, 2), Hal beside it and herself"
check "$(count '\[test\] tiles: .*Crate1=\(8, 2\).*Player1=\(9, 2\)' "$LOGS/clientH.log")" 1 "phase 4: Hal, who did not ask, sees the same room"
check "$(count 'restarting in 3 s \(a test\), 1 connected' "$LOGS/admin.txt")" 1 "phase 5: the console says the restart is due"
check "$(count "\\[party\\] Server: Restarting in 3 s \\(a test\\); you'll be reconnected\\." "$LOGS/clientR.log")$(count '\[party\] Server:' "$LOGS/clientR.log")" 11 "phase 5: Rex is told once (a countdown of 3 s has no later warnings)"
check "$(count '\[admin\] restarting \(a test\): saving, letting 1 players go, exiting 75' "$LOGS/server5.log")" 1 "phase 5: the server saves and lets him go"
check "$restart_code" 75 "phase 5: and exits 75, for systemd to start it again"
check "$(cat "$LOGS/server5.log" "$LOGS/server5.err" | grep -c '^ERROR' || true)" 0 "phase 5: holding three zones, it went without an ERROR (decision 299)"
check "$quick_code" 0 "phase 5: a server stopped as soon as its console is up exits 0"
check "$(count '\[net\] lost the server; reconnecting' "$LOGS/clientR.log")$(count '\[net\] reconnected \(try [0-9]+\)' "$LOGS/clientR.log")" 11 "phase 5: Rex's client reconnects by itself"
check "$(count '\[net\] Rex \(5e5e5e5e\) joined as Player1 at \(9, 2\) \(back\)' "$LOGS/server6.log")" 1 "phase 5: the restarted server puts him back on (9, 2)"
check "$(count '\[test\] display: Player1 server_tile=\(9, 2\) shown_tile=\(9, 2\)' "$LOGS/clientR.log")" 1 "phase 5: and his client shows him there"
check "$(count '\[test\] tiles: .*Crate1=\(8, 2\).*Player1=\(9, 2\)$' "$LOGS/clientR.log")" 1 "phase 5: and the room as it was, its entities sent again"
errors=$(cat "$LOGS"/*.err 2>/dev/null | wc -l | tr -d ' ')
check "$errors" 0 "no instance printed errors"

# A failed run's logs, kept where they survive the run: .godot/test_failures
# (per checkout, never committed), the last ten. Prints where.
keep_failure() {
	kept=".godot/test_failures/$(date +%Y%m%d-%H%M%S)-$1"
	mkdir -p "$kept"
	shift
	cp -r "$@" "$kept"/ 2>/dev/null
	ls -1d .godot/test_failures/*/ 2>/dev/null | sort | head -n -10 | while read -r old; do rm -rf "$old"; done
	echo "kept in $kept"
}

echo
if [ "$failures" -gt 0 ]; then
	echo "--- server log ($LOGS) ---"
	cat "$LOGS/server.log"
	keep_failure net_test "$LOGS"/.
	echo "RESULT: FAIL ($failures failed)"
	exit 1
fi
echo "RESULT: PASS (logs in $LOGS)"
exit 0
