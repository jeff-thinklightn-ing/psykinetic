#!/usr/bin/env bash
# What the server sends: a real headless server on map_bench's dungeon
# (saved as "netbench" by tools/net_bench_map.tscn into the user:// overlay
# of a user data folder of the bench's own: APPDATA points at a temp folder)
# and N real headless clients, all joining at its start. Prints the
# server's own count of bytes sent ("net" on its admin console): the
# minute after the clients join (the join's spawns), and the minute after
# that (steady). Per client is that over N.
#   tools/net_bench.sh [clients=1] [size=256] [monsters=2]
# NET_BENCH_SERVER_ARGS adds to the server's arguments (--no-interest: every
# client sent everything, as before decision 217).
set -u
GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe) console="${GODOT%.exe}_console.exe"; [ -f "$console" ] && GODOT="$console" ;;
esac
CLIENTS="${1:-1}"
SIZE="${2:-256}"
MONSTERS="${3:-2}"
cd "$(dirname "$0")/.."
. tests/test_ports.sh
PORT=$((17950 + PORT_OFFSET))
ADMIN=$((17951 + PORT_OFFSET))
LOGS="$(mktemp -d)"
# The bench's own user data: its level goes in an overlay nobody else reads
# (user:// is shared by every worktree and test otherwise).
SHARED="$APPDATA/Godot/app_userdata/Psykinetic/levels/netbench"
mkdir -p "$LOGS/appdata"
export APPDATA="$(cygpath -w "$LOGS/appdata" 2>/dev/null || echo "$LOGS/appdata")"
"$GODOT" --headless --path . --scene res://tools/net_bench_map.tscn -- "--size=$SIZE" "--monsters=$MONSTERS" 2>&1 | grep "\[net bench\]"
if [ -e "$SHARED" ]; then
	echo "the bench's level went to the shared user data ($SHARED): removed, stopping"
	rm -rf "$SHARED" "$LOGS"
	exit 1
fi
"$GODOT" --headless --path . --server --map=netbench --no-companions --token=bench "--port=$PORT" "--admin-port=$ADMIN" "--max-players=$CLIENTS" ${NET_BENCH_SERVER_ARGS:-} \
	--test-exit-after=200 </dev/null >"$LOGS/server.log" 2>&1 &
sleep 8
ask() {
	exec 3<>"/dev/tcp/127.0.0.1/$ADMIN" || return
	printf 'net\n' >&3
	timeout 3 head -c 2000 <&3 | head -1
	exec 3>&-
}
echo "before anyone joins: $(ask)"
for i in $(seq 1 "$CLIENTS"); do
	"$GODOT" --headless --path . --client --address=127.0.0.1 "--port=$PORT" --token=bench "--name=Bench$i" \
		"--player-id=be0c0000-0000-4000-8000-0000000000$(printf %02d "$i")" --test-exit-after=190 \
		</dev/null >"$LOGS/client$i.log" 2>&1 &
	sleep 0.5
done
sleep 60
echo "the minute of the join, $CLIENTS clients: $(ask)"
sleep 60
echo "the minute after, steady: $(ask)"
echo "joins: $(grep -c ') joined as Player' "$LOGS/server.log")"
echo "slow interest recomputes: $(grep -c '^.interest.' "$LOGS/server.log"); slowest: $(grep '^.interest.' "$LOGS/server.log" | awk '{ print $(NF-1), $0 }' | sort -n | tail -1)"
if [ -n "${NET_BENCH_VERBOSE:-}" ]; then
	grep -h "joined\|left\|timed\|refus\|kick" "$LOGS/server.log" | head -12
	grep -h "connect\|lost\|refus\|version\|ERROR" "$LOGS/client1.log" | head -12
fi
kill %1 2>/dev/null
wait 2>/dev/null
if [ -n "${NET_BENCH_KEEP:-}" ]; then echo "logs kept: $LOGS"; else rm -rf "$LOGS"; fi
