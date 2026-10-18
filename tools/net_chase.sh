#!/usr/bin/env bash
# A player chasing a deer in the wilds over a bad link (Jeff's "rubberbanding
# while trying to chase a wilds deer"): a headless server on the wilds (its
# herds seeded), one headless client joining through tools/net_proxy.gd and
# holding its move order on the nearest deer as it draws it
# (--test-chase), for SECONDS. Prints what the client drew (--test-smooth:
# its own jumps and back steps, and the others'), its chase, and the server's
# refusals of its steps (a push into the deer). Take the bench lock first.
#   tools/net_chase.sh [profile=wan] [seconds=60]
# Profiles as tools/net_smooth.sh: clean, wan (60 +-20 ms each way, 1% loss),
# bad (120 +-40 ms, 3% loss); NET_CHASE_PROXY overrides the proxy's arguments.
# The run's user data is a temp folder of its own (user:// is shared).
set -u
GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe) console="${GODOT%.exe}_console.exe"; [ -f "$console" ] && GODOT="$console" ;;
esac
PROFILE="${1:-wan}"
SECONDS_RUN="${2:-60}"
case "$PROFILE" in
	clean) LINK="--delay=0 --jitter=0 --loss=0" ;;
	wan) LINK="--delay=60 --jitter=20 --loss=1 --burst=1" ;;
	bad) LINK="--delay=120 --jitter=40 --loss=3 --burst=3" ;;
	*) echo "profile: clean, wan or bad"; exit 1 ;;
esac
LINK="${NET_CHASE_PROXY:-$LINK}"
cd "$(dirname "$0")/.."
. tests/test_ports.sh
PORT=$((17975 + PORT_OFFSET))
PROXY=$((17976 + PORT_OFFSET))
LOGS="$(mktemp -d)"
mkdir -p "$LOGS/appdata"
export APPDATA="$(cygpath -w "$LOGS/appdata" 2>/dev/null || echo "$LOGS/appdata")"
"$GODOT" --headless --path . --server --map=wilds --token=chase "--port=$PORT" --no-companions --test-wait-players=1 \
	--test-exit-after=$((SECONDS_RUN + 60)) </dev/null >"$LOGS/server.log" 2>&1 &
server=$!
"$GODOT" --headless --script res://tools/net_proxy.gd -- "--listen=$PROXY" "--server=$PORT" $LINK --seed=7 \
	"--seconds=$((SECONDS_RUN + 40))" </dev/null >"$LOGS/proxy.log" 2>&1 &
proxy=$!
sleep 5
"$GODOT" --headless --path . --client --address=127.0.0.1 "--port=$PROXY" --token=chase --no-companions \
	--player-id=c4a5e000-0000-4000-8000-00000000000a --name=Chaser --controls=click \
	"--test-chase=$SECONDS_RUN" --test-smooth "--test-exit-after=$((SECONDS_RUN + 5))" </dev/null >"$LOGS/chaser.log" 2>&1 &
client=$!
wait $client $proxy $server
echo "net_chase $PROFILE ($LINK), ${SECONDS_RUN} s:"
grep -h "^\[proxy\] carried" "$LOGS/proxy.log" | sed 's/^/  /'
grep -hE "^\[test\] chase|^\[smooth\] [0-9]" "$LOGS/chaser.log" | sed 's/^/  /'
echo "  steps refused by the server (pushes into the deer and the like): $(grep -c 'push: Chaser\|Player[0-9]* -> .* blocked' "$LOGS/server.log")"
grep -hE "SCRIPT ERROR|^ERROR" "$LOGS/chaser.log" "$LOGS/server.log" | sort | uniq -c | head -5 | sed 's/^/  /'
echo "  logs: $LOGS"
