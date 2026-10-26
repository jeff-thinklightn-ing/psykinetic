#!/usr/bin/env bash
# How smooth the game looks over a bad link: a headless server on the castle,
# two headless clients joining it through tools/net_proxy.gd (delay, jitter
# and loss each way), one steering and fighting with the mouse
# (--test-steer, --test-fight), one walking with WASD and fighting, for
# SECONDS. Each client measures what it draws (--test-smooth,
# net/smooth_meter.gd) and its corrections (NetStats); the summary is one
# line each, for before/after tables. Take the bench lock first.
#   tools/net_smooth.sh [profile=wan] [seconds=60] [--no-companions]
# The players have companions unless --no-companions is given (a server
# flag: before 678's trace it went to the clients, where it does nothing).
# Profiles: clean (no proxy delay), wan (60 +-20 ms each way, 1% loss),
# bad (120 +-40 ms, 3% loss in bursts of 3). NET_SMOOTH_PROXY overrides the
# proxy's arguments ("--delay=80 --jitter=30 --loss=2 --burst=2").
# The run's user data is a temp folder of its own (user:// is shared).
set -u
GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe) console="${GODOT%.exe}_console.exe"; [ -f "$console" ] && GODOT="$console" ;;
esac
PROFILE="${1:-wan}"
COMPANIONS="${3:-}"
SECONDS_RUN="${2:-60}"
case "$PROFILE" in
	clean) LINK="--delay=0 --jitter=0 --loss=0" ;;
	wan) LINK="--delay=60 --jitter=20 --loss=1 --burst=1" ;;
	bad) LINK="--delay=120 --jitter=40 --loss=3 --burst=3" ;;
	*) echo "profile: clean, wan or bad"; exit 1 ;;
esac
LINK="${NET_SMOOTH_PROXY:-$LINK}"
cd "$(dirname "$0")/.."
. tests/godot_log.sh  # Its logs in build/logs (decision 664).
. tests/test_ports.sh
PORT=$((17970 + PORT_OFFSET))
PROXY=$((17971 + PORT_OFFSET))
LOGS="$(mktemp -d)"
mkdir -p "$LOGS/appdata"
export APPDATA="$(cygpath -w "$LOGS/appdata" 2>/dev/null || echo "$LOGS/appdata")"
pids=""
"$GODOT" --log-file "$(godot_log smooth_server)" --headless --path . --server --map=castle $COMPANIONS --token=smooth "--port=$PORT" --test-wait-players=2 \
	--test-exit-after=$((SECONDS_RUN + 60)) </dev/null >"$LOGS/server.log" 2>&1 &
server=$!
"$GODOT" --log-file "$(godot_log smooth_proxy)" --headless --script res://tools/net_proxy.gd -- "--listen=$PROXY" "--server=$PORT" $LINK --seed=7 \
	"--seconds=$((SECONDS_RUN + 40))" </dev/null >"$LOGS/proxy.log" 2>&1 &
proxy=$!
sleep 3
WALK="w:2,d:2,s:2,a:2,wd:1.5,sa:1.5,w:2,d:2,s:2,a:2,wd:1.5,sa:1.5,w:2,d:2,s:2,a:2,wd:1.5,sa:1.5,w:2,d:2,s:2,a:2,wd:1.5,sa:1.5"
"$GODOT" --log-file "$(godot_log smooth_client_a)" --headless --path . --client --address=127.0.0.1 "--port=$PROXY" --token=smooth \
	--player-id=5300e000-0000-4000-8000-00000000000a --name=Steer --controls=click \
	--test-steer=1.5 --test-fight=3 --test-smooth "--test-exit-after=$SECONDS_RUN" </dev/null >"$LOGS/steer.log" 2>&1 &
a=$!
"$GODOT" --log-file "$(godot_log smooth_client_b)" --headless --path . --client --address=127.0.0.1 "--port=$PROXY" --token=smooth \
	--player-id=5300e000-0000-4000-8000-00000000000b --name=Keys --controls=wasd \
	"--test-walk=$WALK" --test-smooth "--test-exit-after=$SECONDS_RUN" </dev/null >"$LOGS/keys.log" 2>&1 &
b=$!
# Each quits by itself (--test-exit-after, --seconds).
wait $a $b $proxy $server
echo "net_smooth $PROFILE ($LINK), ${SECONDS_RUN} s${COMPANIONS:+, $COMPANIONS}:"
grep -h "^\[proxy\] carried" "$LOGS/proxy.log" | sed 's/^/  /'
for name in steer keys; do
	echo "  $name:"
	grep -hE "^\[smooth\] [0-9rb]|^\[test\] display" "$LOGS/$name.log" | tail -4 | sed 's/^/    /'
	grep -hE "SCRIPT ERROR|^ERROR" "$LOGS/$name.log" | sort | uniq -c | head -5 | sed 's/^/    /'
done
echo "  logs: $LOGS"
