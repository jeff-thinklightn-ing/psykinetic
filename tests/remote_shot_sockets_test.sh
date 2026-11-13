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
# The whole runner parses (its run mode needs a laptop's session; its proof is a laptop run).
parsed="$(powershell -NoProfile -NonInteractive -Command "\$e = \$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$runner', [ref]\$null, [ref]\$e); \$e.Count" 2>&1 | tr -d '\r')"
if [ "$parsed" = "0" ]; then echo "  PASS  the runner parses"; else echo "  FAIL  the runner parses: $parsed"; failed=$((failed + 1)); fi
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
