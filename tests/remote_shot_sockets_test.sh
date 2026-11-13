#!/usr/bin/env bash
# tools/remote_shot_run.ps1's joined-run socket check (828 amended (4), the coordinator's
# ruling 2026-11-12): loopback always fine; off loopback exactly one socket allowed, UDP, the
# client's own, unspecified address, ephemeral port, while it joins 127.0.0.1 (its ENet
# connection out); a second, a foreign owner, the server's, a TCP listener, a fixed port or a
# client not joining 127.0.0.1 stops the run. Judged by the runner's own -Mode judge; no laptop
# needed. Also: the runner parses. Windows only (the runner is PowerShell): SKIP elsewhere.
set -u
cd "$(dirname "$0")/.."
if ! command -v powershell >/dev/null 2>&1; then echo "  SKIP  no powershell here"; echo "RESULT: PASS"; exit 0; fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
runner="$(cygpath -w "$PWD/tools/remote_shot_run.ps1" 2>/dev/null || echo "$PWD/tools/remote_shot_run.ps1")"
# judge <label> <wanted OK|STOP> <wanted text in the line> <joining_local> <sockets json>
judge() {
	printf '{"low": 49152, "joining_local": %s, "sockets": [%s]}' "$4" "$5" > "$tmp/case.json"
	local got
	got="$(powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$runner" -Mode judge \
		-Dir "$(cygpath -w "$tmp/case.json" 2>/dev/null || echo "$tmp/case.json")" 2>&1 | tr -d '\r')"
	if [ "${got%% *}" = "$2" ] && printf '%s' "$got" | grep -qF -- "$3"; then
		echo "  PASS  $1"
	else
		echo "  FAIL  $1: got [$got], wanted $2 with [$3]"; failed=$((failed + 1))
	fi
}
server='{"owner": "server", "proto": "udp", "address": "::ffff:127.0.0.1", "port": 56138}'
status='{"owner": "client", "proto": "udp", "address": "127.0.0.1", "port": 51541}'
enet='{"owner": "client", "proto": "udp", "address": "::", "port": 51542}'
judge "loopback only: fine" OK "SOCKETS: server ::ffff:127.0.0.1:56138/udp; client 127.0.0.1:51541/udp" true "$server, $status"
judge "the client's one ENet socket on :: while joining 127.0.0.1: allowed and named" OK \
	"client ENet :::51542/udp (outgoing, allowed)" true "$server, $status, $enet"
judge "the same on 0.0.0.0: allowed" OK "client ENet 0.0.0.0:51542/udp (outgoing, allowed)" true \
	'{"owner": "client", "proto": "udp", "address": "0.0.0.0", "port": 51542}'
judge "a second client socket off loopback: refused" STOP "a second client socket off loopback: 0.0.0.0:51543/udp" true \
	"$server, $enet, "'{"owner": "client", "proto": "udp", "address": "0.0.0.0", "port": 51543}'
judge "the same socket owned by another process: refused" STOP "other socket off loopback: :::51544/udp" true \
	"$server, "'{"owner": "other", "proto": "udp", "address": "::", "port": 51544}'
judge "the server off loopback: refused" STOP "server socket off loopback: :::56138/udp" true \
	'{"owner": "server", "proto": "udp", "address": "::", "port": 56138}'
judge "a TCP listener off loopback: refused" STOP "client socket off loopback: 0.0.0.0:51545/tcp" true \
	"$enet, "'{"owner": "client", "proto": "tcp", "address": "0.0.0.0", "port": 51545}'
judge "a fixed port (not ephemeral): refused" STOP "client socket off loopback: :::7777/udp" true \
	'{"owner": "client", "proto": "udp", "address": "::", "port": 7777}'
judge "a client not joining 127.0.0.1: refused" STOP "not joining 127.0.0.1: :::51542/udp" false "$server, $enet"
judge "a socket on a real address: refused" STOP "client socket off loopback: 192.168.1.20:51546/udp" true \
	'{"owner": "client", "proto": "udp", "address": "192.168.1.20", "port": 51546}'
# A tour's admin console (828 amended (6)): a TCP listener on 127.0.0.1 is fine; anywhere else stops the run.
judge "a tour's admin console, the server's TCP listener on 127.0.0.1: fine" OK "server 127.0.0.1:50110/tcp" true \
	"$server, $enet, "'{"owner": "server", "proto": "tcp", "address": "127.0.0.1", "port": 50110}'
judge "the admin console on 0.0.0.0: refused" STOP "server socket off loopback: 0.0.0.0:50110/tcp" true \
	"$server, $enet, "'{"owner": "server", "proto": "tcp", "address": "0.0.0.0", "port": 50110}'

# remote_shot.sh's own refusals and what --tour sends (828 amended (6)), the laptop never
# reached: ssh and scp here are fakes that note being called and fail.
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho called >> "%s"\nexit 255\n' "$tmp/reached" > "$tmp/bin/ssh"
cp "$tmp/bin/ssh" "$tmp/bin/scp"
chmod +x "$tmp/bin/ssh" "$tmp/bin/scp"
shot() { PATH="$tmp/bin:$PATH" bash tools/remote_shot.sh "$@" 2>&1; }
sha="$(git rev-parse HEAD)"
# refused <label> <wanted text> <args...>: exit 2, the text said, the laptop not reached.
refused() {
	local label="$1" want="$2" got code
	shift 2
	rm -f "$tmp/reached"
	got="$(shot "$@")"; code=$?
	if [ $code -eq 2 ] && printf '%s' "$got" | grep -qF -- "$want" && [ ! -f "$tmp/reached" ]; then
		echo "  PASS  $label"
	else
		echo "  FAIL  $label: exit $code, [$got]$([ -f "$tmp/reached" ] && echo ', the laptop reached')"; failed=$((failed + 1))
	fi
}
refused "--admin-port in --server-args, joined: refused (the runner names it, under --tour only)" \
	"--server-args --admin-port=5000: refused" --joined --server-args "--admin-port=5000" "$sha" x --
refused "--admin-port in --server-args under --tour: refused too" \
	"--server-args --admin-port=5000: refused" --tour smoke --server-args "--admin-port=5000" "$sha" x --
refused "tour.tscn without --tour: refused (a test scene)" "res://tests/tour/tour.tscn: refused (a test scene" \
	--joined "$sha" x -- --scene res://tests/tour/tour.tscn
refused "--test-foe without --tour: refused" "--test-foe=rat,bow: refused (only with --tour)" \
	--joined --server-args "--test-foe=rat,bow" "$sha" x --
refused "--sought-first without --tour: refused" "--sought-first: refused (only with --tour)" \
	--joined --server-args "--sought-first" "$sha" x --
refused "--regenerate asked for: refused (the runner adds it, under --tour)" "--server-args --regenerate: refused" \
	--tour smoke --server-args "--regenerate" "$sha" x --
refused "a tour with godot args of the caller's: refused" "--host: refused (a tour's args come from the runner" \
	--tour smoke "$sha" x -- --host
refused "a tour not at the sha: refused" "--tour no_such_tour: no tests/tour/tours/no_such_tour.gd at" \
	--tour no_such_tour "$sha" x --
refused "--tour-only without --tour: refused" "only with --tour" --tour-only beds --joined "$sha" x --
refused "--repeat with --tour: refused (one phase)" "--repeat: not with --tour" --tour smoke --repeat 2 "$sha" x --
rm -f "$tmp/reached"
sent="$(shot --dry-run --tour kit --tour-only wall --tour-minutes 10 --server-args "--test-foe=draugr,giant_axe --sought-first" "$sha" tourx --)"
code=$?
wanted_args="args: --disable-vsync;args: --scene;args: res://tests/tour/tour.tscn;args: --;args: --name=Tourbot;args: --player-id=70a70000-0000-4000-8000-000000000001;args: --tour=kit;args: --tour-out=D:/psykinetic-runs/tourx/out;args: --tour-minutes=10;args: --test-exit-after=850;args: --tour-phase=1;args: --bind=127.0.0.1;server_args: --test-foe=draugr,giant_axe;server_args: --sought-first;server_args: --regenerate;tour: tour=kit;tour: only=wall;timeout: 17 min;"
got_args="$(printf '%s\n' "$sent" | grep -E '^(args|server_args|tour|timeout): ' | tr '\n' ';')"
if [ $code -eq 0 ] && [ "$got_args" = "$wanted_args" ] && [ ! -f "$tmp/reached" ]; then
	echo "  PASS  --tour sends tour.sh's client args, the test player's fixed id, --regenerate, its foe and --sought-first; no mode, port or token"
else
	echo "  FAIL  --tour's args: exit $code, got [$got_args], wanted [$wanted_args]"; failed=$((failed + 1))
fi
if printf '%s' "$sent" | grep -qiE -- "--token|--admin-port|--address|--port=|--client|--host"; then
	echo "  FAIL  a tour's args name a token, an admin port, an address or a mode: [$sent]"; failed=$((failed + 1))
else
	echo "  PASS  and no token, admin port, address or mode of its own (the runner names those on the laptop)"
fi

# The whole runner parses (its run mode needs a laptop's session; its proof is a laptop run).
parsed="$(powershell -NoProfile -NonInteractive -Command "\$e = \$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$runner', [ref]\$null, [ref]\$e); \$e.Count" 2>&1 | tr -d '\r')"
if [ "$parsed" = "0" ]; then echo "  PASS  the runner parses"; else echo "  FAIL  the runner parses: $parsed"; failed=$((failed + 1)); fi
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
