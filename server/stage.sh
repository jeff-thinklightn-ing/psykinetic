#!/usr/bin/env bash
# Tries a freshly exported server build before it replaces the running one
# (decision 242). Run by `server/deploy.sh --staged`, after the export and
# before the running server is touched; exits non-zero if the build fails.
#   1. prints the running server's build and protocol beside the new one's,
#      and whether the clients must update (another protocol: release first)
#   2. starts the new build from build/ as this user, on UDP 7787 with its
#      console on 7788 (never the live 7777/7778, nor the box's Ollama on
#      11600), with a throwaway token and a copy of the live snapshot and
#      edited levels, writing only under a temp folder
#   3. a headless client (the Godot editor binary, on the repo) joins it,
#      walks a step and reports
#   4. the console's stop 0: the staged server must save and exit 0
# It passes when the server started, the client joined and saw its player,
# neither printed a script error, and the server stopped cleanly.
set -eu

REPO="${PSYKINETIC_REPO:-$HOME/psykinetic}"
GODOT="${GODOT_PATH:-$(ls -1 "$HOME"/godot/Godot_v*_linux.x86_64 2>/dev/null | sort -V | tail -n 1)}"
BUILD="$REPO/build/psykinetic-server.x86_64"
# What runs the build under test: the export, or (to try this script off the
# box) e.g. "$GODOT --path $REPO".
SERVER_CMD="${PSYKINETIC_STAGE_SERVER:-$BUILD}"
LIVE_STATE=/var/lib/psykinetic/world.json
LIVE_LEVELS=/var/lib/psykinetic/.local/share/godot/app_userdata/Psykinetic/levels
PORT="${PSYKINETIC_STAGE_PORT:-7787}"
ADMIN="${PSYKINETIC_STAGE_ADMIN:-7788}"
STAGE="$(mktemp -d -t psykinetic-stage.XXXXXX)"
SERVER=""
CLIENT=""
# Whatever happens, the staged processes (this script's own) go, then their folder.
cleanup() {
	for pid in $CLIENT $SERVER; do
		if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
	done
	rm -rf "$STAGE"
}
trap cleanup EXIT
fail() {
	echo "stage: FAILED: $1"
	for log in server client; do
		if [ -s "$STAGE/$log.log" ]; then
			echo "--- staged $log, last lines"
			tail -n 25 "$STAGE/$log.log"
		fi
	done
	exit 1
}
# Waits until <file> has a line matching <regex>, <seconds> at most, and no
# longer than the staged server runs.
wait_for() {
	waited=0
	until grep -qE "$2" "$1" 2>/dev/null; do
		waited=$((waited + 1))
		[ "$waited" -le $(($3 * 4)) ] || return 1
		if [ -n "$SERVER" ] && ! kill -0 "$SERVER" 2>/dev/null; then return 1; fi
		sleep 0.25
	done
}
admin() {
	exec 3<>"/dev/tcp/127.0.0.1/$1"
	printf '%s\n' "$2" >&3
	cat <&3
	exec 3<&-
}

[ -n "${PSYKINETIC_STAGE_SERVER:-}" ] || test -x "$BUILD" || fail "no exported build at $BUILD"
test -x "$GODOT" || fail "no Godot binary for the smoke client (GODOT_PATH)"

# 1. Which protocol: the clients stay, or must update.
new="$($SERVER_CMD --headless --print-protocol 2>/dev/null | grep -m 1 '^PROTOCOL' || true)"
test -n "$new" || fail "the new build did not print its protocol"
running="$(bash "$REPO/server/admin.sh" version 2>/dev/null || true)"
new_protocol="${new##* }"
running_protocol="$(printf '%s' "$running" | sed -n 's/.*protocol \([0-9a-f]*\).*/\1/p')"
echo "stage: running: ${running:-not running, or too old to say}"
echo "stage: new:     ${new#PROTOCOL }"
if [ -z "$running_protocol" ]; then
	echo "stage: protocol: the running server's is unknown"
elif [ "$running_protocol" = "$new_protocol" ]; then
	echo "stage: protocol: the same; players keep their build"
else
	echo "stage: protocol: CHANGED; clients must update, so the client release must be out first"
fi

# 2. The new build on staging ports, with copies of the live world.
cp "$LIVE_STATE" "$STAGE/world.json" 2>/dev/null || echo "stage: the live snapshot is not readable here; staging a fresh world"
GAME_DATA="$STAGE/home/.local/share/godot/app_userdata/Psykinetic"
mkdir -p "$GAME_DATA"
cp -r "$LIVE_LEVELS" "$GAME_DATA/" 2>/dev/null || true
TOKEN="stage-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
HOME="$STAGE/home" APPDATA="$STAGE/home" $SERVER_CMD --headless --server "--port=$PORT" "--admin-port=$ADMIN" \
	"--state=$STAGE/world.json" "--token=$TOKEN" "--mind-log=$STAGE/mind.log" \
	"--transcripts=$STAGE/transcripts" --test-exit-after=120 </dev/null >"$STAGE/server.log" 2>&1 &
SERVER=$!
wait_for "$STAGE/server.log" "listening on port $PORT" 60 || fail "the staged server did not start listening"
wait_for "$STAGE/server.log" "console on 127.0.0.1:$ADMIN" 10 || fail "the staged console did not open"

# 3. A client joins, walks and reports.
HOME="$STAGE/client" APPDATA="$STAGE/client" "$GODOT" --headless --path "$REPO" --client --address=127.0.0.1 "--port=$PORT" \
	"--token=$TOKEN" --name=Stager --player-id=57a6e000-0000-4000-8000-000000000057 --test-move=0,1 \
	"--test-exit-on=$STAGE/client.done" --test-exit-after=90 </dev/null >"$STAGE/client.log" 2>&1 &
CLIENT=$!
wait_for "$STAGE/server.log" 'Stager \(57a6e000\) joined as Player' 60 || fail "the client was not given a player"
wait_for "$STAGE/client.log" '\[test\] Player[0-9]+ (ordered|arrived)' 30 || fail "the client never saw its player"
touch "$STAGE/client.done" "$STAGE/client.done.quit"
wait "$CLIENT" || true
CLIENT=""

# 4. It stops cleanly, saving.
reply="$(admin "$ADMIN" 'stop 0 staged' 2>&1 || true)"
case "$reply" in
	restarting*) ;;
	*) fail "the staged console did not take stop: $reply" ;;
esac
code=0
wait "$SERVER" || code=$?
SERVER=""
test "$code" -eq 0 || fail "the staged server exited $code, not 0"
if grep -E 'SCRIPT ERROR|^ERROR:' "$STAGE/server.log" "$STAGE/client.log" >/dev/null; then
	fail "a script error (above)"
fi
echo "stage: passed: the new build started, took a player, and stopped cleanly"
