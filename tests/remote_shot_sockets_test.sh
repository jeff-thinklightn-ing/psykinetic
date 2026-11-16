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
refused "--test-foe with a character past a-z, 0-9, _, +, : and ,: refused" "--test-foe=rat;bow: refused (foes and weapons" 	--tour smoke --server-args "--test-foe=rat;bow" "$sha" x --
refused "--sought-first without --tour: refused" "--sought-first: refused (only with --tour)" \
	--joined --server-args "--sought-first" "$sha" x --
refused "--test-hp without --tour: refused" "--test-hp: refused (only with --tour)" \
	--joined --server-args "--test-hp" "$sha" x --
refused "--test-visitor without --tour: refused" "--test-visitor=pedlar: refused (only with --tour)" \
	--joined --server-args "--test-visitor=pedlar" "$sha" x --
refused "--test-visitor of another kind: refused (pedlar alone)" "--test-visitor=pilgrim: refused (only --test-visitor=pedlar)" \
	--tour smoke --server-args "--test-visitor=pilgrim" "$sha" x --
refused "--run-marker asked for: refused (the runner names it, under --tour)" "--server-args --run-marker=x: refused" \
	--tour smoke --server-args "--run-marker=x" "$sha" x --
refused "--overlay-dir asked for: refused (the runner names it, under --tour)" "--server-args --overlay-dir=x: refused" \
	--tour smoke --server-args "--overlay-dir=x" "$sha" x --
refused "--regenerate asked for: refused (the runner adds it, under --tour)" "--server-args --regenerate: refused" \
	--tour smoke --server-args "--regenerate" "$sha" x --
refused "a tour with godot args of the caller's: refused" "--host: refused (a tour's args come from the runner" \
	--tour smoke "$sha" x -- --host
refused "a tour not at the sha: refused" "--tour no_such_tour: no tests/tour/tours/no_such_tour.gd at" \
	--tour no_such_tour "$sha" x --
refused "--tour-only without --tour: refused" "only with --tour" --tour-only beds --joined "$sha" x --
refused "--repeat with --tour: refused (one phase)" "--repeat: not with --tour" --tour smoke --repeat 2 "$sha" x --
refused "--tour-bots without --tour: refused (828 amended (10))" "only with --tour" --tour-bots 2 --joined "$sha" x --
refused "--tour-bots 3: refused (one or two)" "--tour-bots: 1 or 2" --tour smoke --tour-bots 3 "$sha" x --
# Builder mode's panel joined (828 amended (11)): --builders only beside --builder-stub, and only fixed test ids.
refused "--builders without --builder-stub: refused (a laptop's server never makes a real builder request)" \
	"--server-args --builders=70a70000-0000-4000-8000-000000000001: refused without --builder-stub (a laptop's server never makes a real builder request)" \
	--joined --server-args "--builders=70a70000-0000-4000-8000-000000000001" "$sha" x --
refused "--builders with an id not a fixed test id: refused, beside the stub too" "is not a fixed test id" \
	--joined --server-args "--builder-stub --builders=70a70000-0000-4000-8000-000000000001,3f2b9c1e-0000-4000-8000-000000000001" "$sha" x --
refused "--builders= empty: refused" "--server-args --builders=: refused (a test id" \
	--joined --server-args "--builder-stub --builders=" "$sha" x --
refused "--builder-stub without --joined: refused (--server-args only with --joined)" "--server-args: only with --joined" \
	--server-args "--builder-stub" "$sha" x --
rm -f "$tmp/reached"
sent="$(shot --dry-run --joined --server-args "--builders=70a70000-0000-4000-8000-000000000001,70a70000-0000-4000-8000-000000000002 --builder-stub" "$sha" builderx -- --player-id=70a70000-0000-4000-8000-000000000001)"
code=$?
got_args="$(printf '%s\n' "$sent" | grep -E '^server_args: ' | tr '\n' ';')"
wanted_args="server_args: --builders=70a70000-0000-4000-8000-000000000001,70a70000-0000-4000-8000-000000000002;server_args: --builder-stub;"
if [ $code -eq 0 ] && [ "$got_args" = "$wanted_args" ] && [ ! -f "$tmp/reached" ]; then
	echo "  PASS  --builder-stub with --builders=<test ids>, in either order: both sent to the joined server"
else
	echo "  FAIL  --builder-stub and --builders: exit $code, got [$got_args], wanted [$wanted_args]"; failed=$((failed + 1))
fi
rm -f "$tmp/reached"
sent="$(shot --dry-run --joined --server-args "--builder-stub" "$sha" builderx --)"
code=$?
got_args="$(printf '%s\n' "$sent" | grep -E '^server_args: ' | tr '\n' ';')"
if [ $code -eq 0 ] && [ "$got_args" = "server_args: --builder-stub;" ] && [ ! -f "$tmp/reached" ]; then
	echo "  PASS  --builder-stub alone: sent (harmless: on a dedicated server no player builds without --builders)"
else
	echo "  FAIL  --builder-stub alone: exit $code, got [$got_args]"; failed=$((failed + 1))
fi
rm -f "$tmp/reached"
sent="$(shot --dry-run --tour kit --tour-only wall --tour-minutes 10 --server-args "--test-foe=robber+robber+great_bear,sword+shield,1,around --sought-first --test-hp --test-visitor=pedlar" "$sha" tourx --)"
code=$?
wanted_args="args: --disable-vsync;args: --scene;args: res://tests/tour/tour.tscn;args: --;args: --name=Tourbot;args: --player-id=70a70000-0000-4000-8000-000000000001;args: --tour=kit;args: --tour-out=D:/psykinetic-runs/tourx/out;args: --tour-minutes=10;args: --test-exit-after=850;args: --tour-phase=1;args: --bind=127.0.0.1;server_args: --test-foe=robber+robber+great_bear,sword+shield,1,around;server_args: --sought-first;server_args: --test-hp;server_args: --test-visitor=pedlar;server_args: --regenerate;server_args: --run-marker=tour-tourx;server_args: --overlay-dir=user://tour_overlay/;tour: tour=kit;tour: only=wall;tour: bots=1;timeout: 17 min;"
got_args="$(printf '%s\n' "$sent" | grep -E '^(args|server_args|tour|timeout): ' | tr '\n' ';')"
if [ $code -eq 0 ] && [ "$got_args" = "$wanted_args" ] && [ ! -f "$tmp/reached" ]; then
	echo "  PASS  --tour sends tour.sh's client args, the test player's fixed id, --regenerate, --run-marker, its own overlay dir, its foe, --sought-first, --test-hp and --test-visitor=pedlar; no mode, port or token"
else
	echo "  FAIL  --tour's args: exit $code, got [$got_args], wanted [$wanted_args]"; failed=$((failed + 1))
fi
if printf '%s' "$sent" | grep -qiE -- "--token|--admin-port|--address|--port=|--client|--host"; then
	echo "  FAIL  a tour's args name a token, an admin port, an address or a mode: [$sent]"; failed=$((failed + 1))
else
	echo "  PASS  and no token, admin port, address or mode of its own (the runner names those on the laptop)"
fi
rm -f "$tmp/reached"
sent="$(shot --dry-run --tour kit --server-args "--test-foe=imp:bold,,1,around,held" "$sha" tourx --)"
code=$?
got_args="$(printf '%s\n' "$sent" | grep -E '^server_args: --test-foe' | tr '\n' ';')"
if [ $code -eq 0 ] && [ "$got_args" = "server_args: --test-foe=imp:bold,,1,around,held;" ] && [ ! -f "$tmp/reached" ]; then
	echo "  PASS  --test-foe with a kind's temperament (imp:bold, 392 amended (9)): sent as written"
else
	echo "  FAIL  --test-foe=imp:bold,,1,around,held: exit $code, got [$got_args]"; failed=$((failed + 1))
fi

# Two bots (828 amended (10)): bot 1 says it is bot 1, tour.txt says two; the runner makes bot 2's
# args from bot 1's (its own -Mode bot2args): name, fixed id and number swapped, nothing else;
# refused when one of the three is missing (bot 2 would be bot 1's own player).
sent="$(shot --dry-run --tour kit --tour-bots 2 "$sha" tourx --)"; code=$?
got_args="$(printf '%s\n' "$sent" | grep -E '^(args|tour): ' | tr '\n' ';')"
wanted_two="args: --disable-vsync;args: --scene;args: res://tests/tour/tour.tscn;args: --;args: --name=Tourbot;args: --player-id=70a70000-0000-4000-8000-000000000001;args: --tour=kit;args: --tour-out=D:/psykinetic-runs/tourx/out;args: --tour-minutes=20;args: --test-exit-after=1450;args: --tour-phase=1;args: --tour-bot=1;args: --bind=127.0.0.1;tour: tour=kit;tour: only=;tour: bots=2;"
if [ $code -eq 0 ] && [ "$got_args" = "$wanted_two" ]; then
	echo "  PASS  --tour-bots 2 sends --tour-bot=1 to bot 1 and bots=2 in tour.txt"
else
	echo "  FAIL  --tour-bots 2: exit $code, got [$got_args], wanted [$wanted_two]"; failed=$((failed + 1))
fi
printf '%s\n' "$sent" | sed -n 's/^args: //p' >"$tmp/bot1.txt"
bot2="$(powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$runner" -Mode bot2args \
	-Dir "$(cygpath -w "$tmp/bot1.txt" 2>/dev/null || echo "$tmp/bot1.txt")" 2>&1 | tr -d '\r' | tr '\n' ';')"
wanted_bot2="--disable-vsync;--scene;res://tests/tour/tour.tscn;--;--name=Tourbot2;--player-id=70a70000-0000-4000-8000-000000000002;--tour=kit;--tour-out=D:/psykinetic-runs/tourx/out;--tour-minutes=20;--test-exit-after=1450;--tour-phase=1;--tour-bot=2;--bind=127.0.0.1;"
if [ "$bot2" = "$wanted_bot2" ]; then
	echo "  PASS  the runner's bot 2: Tourbot2, the second fixed id, --tour-bot=2, the rest bot 1's"
else
	echo "  FAIL  the runner's bot 2: got [$bot2], wanted [$wanted_bot2]"; failed=$((failed + 1))
fi
grep -v -- "--tour-bot=1" "$tmp/bot1.txt" >"$tmp/bot1_one.txt"
bot2="$(powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$runner" -Mode bot2args \
	-Dir "$(cygpath -w "$tmp/bot1_one.txt" 2>/dev/null || echo "$tmp/bot1_one.txt")" 2>&1 | tr -d '\r')"
if [ "$bot2" = "REFUSED" ]; then
	echo "  PASS  the runner's bot 2 refused when bot 1's args lack --tour-bot=1"
else
	echo "  FAIL  the runner's bot 2 without --tour-bot=1: got [$bot2], wanted REFUSED"; failed=$((failed + 1))
fi
if grep -qF '"\[net\] connected as peer" "$REVIEW/bot2/godot.log"' tools/remote_shot.sh; then
	echo "  PASS  remote_shot.sh voids a two-bot tour whose bot 2 never joined"
else
	echo "  FAIL  remote_shot.sh voids a two-bot tour whose bot 2 never joined"; failed=$((failed + 1))
fi

# A tour into a regenerating level with no generation laid is void (828 amended (9)): the barrow
# laid (look214_crouch2's lines), barrow_deep bare (look214_ossuary's), the forest not regenerating.
logs="$(mktemp -d -t bare_levels.XXXXXX)"
printf '%s\r\n' "[regen] barrow: generation 1 (seed 1829380510, 6 of 16 tries, every 3 days)" \
	"[level] barrow: 1294 cells, 20 entities, 1 starts, 4 links" "[level] forest: 40167 cells, 16 entities, 4 starts, 3 links" >"$logs/laid.log"
printf '%s\n' "[level] umbrage: 900 cells, 3 entities, 1 starts, 2 links" "[level] barrow_deep: 715 cells, 2 entities, 1 starts, 1 links" >"$logs/bare.log"
out="$(sh tools/tour_bare_levels.sh "$sha" "$logs/laid.log")"; code=$?
if [ $code = 0 ] && [ -z "$out" ]; then echo "  PASS  a laid barrow and the forest: no bare level"; else echo "  FAIL  a laid barrow and the forest: no bare level ($code: $out)"; failed=$((failed + 1)); fi
out="$(sh tools/tour_bare_levels.sh "$sha" "$logs/bare.log")"; code=$?
if [ $code = 1 ] && [ "$out" = "barrow_deep" ]; then echo "  PASS  barrow_deep loaded with no [regen] line: named, exit 1"; else echo "  FAIL  barrow_deep loaded with no [regen] line: named, exit 1 ($code: $out)"; failed=$((failed + 1)); fi
rm -rf "$logs"
if grep -q 'tour_bare_levels.sh "$SHA" "$REVIEW/server.log"' tools/remote_shot.sh; then echo "  PASS  remote_shot.sh fails a tour on it"; else echo "  FAIL  remote_shot.sh fails a tour on it"; failed=$((failed + 1)); fi

# The pipeline cache kept and warmed, the GPU sampled (828 amended (12), the coordinator's bounds):
# opt-in, the source named by run (never a path), only that run's kept vulkan folder copied, the
# builds compared; remote_shot.sh's refusals and what it sends, then the runner's own two steps
# (-Mode cache) on a scratch runner folder.
refused "a run named caches: refused (the runner's own folder)" "name: caches is the runner's own folder" "$sha" caches --
refused "--warm-from a path: refused (a run's name only)" "--warm-from: a run's name" --warm-from "../x" "$sha" x --
refused "--warm-from its own name with --keep-cache: refused" "would keep over its own source" --warm-from x --keep-cache "$sha" x --
rm -f "$tmp/reached"
sent="$(shot --dry-run "$sha" x -- --host)"; code=$?
got_opts="$(printf '%s\n' "$sent" | grep -E '^opts: ' | tr '\n' ';')"
if [ $code -eq 0 ] && [ "$got_opts" = "opts: keep=0;opts: warm=;opts: gpu=0;" ] && [ ! -f "$tmp/reached" ]; then
	echo "  PASS  by default nothing kept, warmed or sampled (opts.txt: keep=0, warm=, gpu=0)"
else
	echo "  FAIL  the default opts: exit $code, got [$got_opts]"; failed=$((failed + 1))
fi
sent="$(shot --dry-run --keep-cache --warm-from idle_cold --gpu-sample --tour smoke "$sha" idle_warm --)"; code=$?
got_opts="$(printf '%s\n' "$sent" | grep -E '^opts: ' | tr '\n' ';')"
if [ $code -eq 0 ] && [ "$got_opts" = "opts: keep=1;opts: warm=idle_cold;opts: gpu=1;" ]; then
	echo "  PASS  --keep-cache --warm-from idle_cold --gpu-sample, with a tour: opts.txt says each"
else
	echo "  FAIL  the asked opts: exit $code, got [$got_opts]"; failed=$((failed + 1))
fi
runs="$tmp/runs"
win() { cygpath -w "$1" 2>/dev/null || echo "$1"; }
# cache <run> <opts lines...>: the runner's -Mode cache on <runs>/<run>; its lines in $tmp/cache.txt.
cache() {
	local run="$1"
	shift
	mkdir -p "$runs/$run"
	printf '%s\n' "$@" >"$runs/$run/opts.txt"
	powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$runner" -Mode cache -Root "$(win "$PWD")" \
		-Runs "$(win "$runs")" -Dir "$(win "$runs/$run")" 2>&1 | tr -d '\r' >"$tmp/cache.txt"
}
has() { grep -qxF -- "$1" "$tmp/cache.txt"; }
row() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2: [$(tr '\n' '|' <"$tmp/cache.txt")]"; failed=$((failed + 1)); fi; }
mkdir -p "$runs/idle_cold/appdata/Godot/app_userdata/Psykinetic/vulkan"
head -c 100 /dev/zero >"$runs/idle_cold/appdata/Godot/app_userdata/Psykinetic/vulkan/pipelines.test.cache"
cache idle_cold keep=1 warm= gpu=0
row $(has "cache: cold (bot 1's user://vulkan empty)" && has "state: cold" && has "cache kept as caches\\idle_cold: 1 files, 100 bytes, build $sha" && has "result: "; echo $?) \
	"a cold run with --keep-cache: cold, and its user://vulkan kept as caches\\idle_cold with its build"
check_kept="$( [ -f "$runs/caches/idle_cold/vulkan/pipelines.test.cache" ] && [ "$(tr -d '\r\n' <"$runs/caches/idle_cold/build.txt")" = "$sha" ]; echo $?)"
row "$check_kept" "the kept folder holds the cache file and build.txt"
cache idle_warm keep=0 warm=idle_cold gpu=0
row $(has "cache: warm from idle_cold, 1 files, 100 bytes copied into bot 1's user://vulkan; the builds match ($sha)" && has "state: warm from idle_cold" && has "result: " \
	&& [ -f "$runs/idle_warm/appdata/Godot/app_userdata/Psykinetic/vulkan/pipelines.test.cache" ]; echo $?) "--warm-from idle_cold: its files and bytes copied into bot 1's user data, the builds match"
row $( [ ! -d "$runs/caches/idle_warm" ]; echo $?) "a warm run without --keep-cache keeps nothing"
echo "0123abc" >"$runs/caches/idle_cold/build.txt"
cache idle_warm2 warm=idle_cold
row $(grep -qF "the builds DIFFER (0123abc kept, $sha now)" "$tmp/cache.txt"; echo $?) "another build's cache: warm, and the builds said to differ"
cache idle_none warm=no_such_run
row $(has "result: warm from no_such_run: refused, no pipeline cache kept by a run of that name on this laptop (a run keeps its own with --keep-cache)" \
	&& [ ! -d "$runs/idle_none/appdata/Godot/app_userdata/Psykinetic/vulkan" ]; echo $?) "--warm-from a run that kept nothing: refused, nothing copied"
mkdir -p "$runs/caches/empty_run/vulkan"
cache idle_empty warm=empty_run
row $(has "result: warm from empty_run: refused, 0 files copied into bot 1's user://vulkan (the kept cache holds none)"; echo $?) \
	"a kept cache with no files: refused, never a cold run under a warm line"
rm -rf "$runs/caches/empty_run"
cache idle_path 'warm=..\idle_cold' keep=1
row $(has "cache: cold (bot 1's user://vulkan empty)" && has "cache: nothing to keep (the game wrote no user://vulkan; a game stopped, not quit, may not save it)"; echo $?) \
	"a path in opts.txt is no run's name: read as cold; and a game that wrote no cache keeps nothing"
for i in 1 2 3 4 5 6; do mkdir -p "$runs/caches/old$i/vulkan"; touch -d "2026-11-0$i 12:00" "$runs/caches/old$i"; done
mkdir -p "$runs/idle_new/appdata/Godot/app_userdata/Psykinetic/vulkan"
head -c 10 /dev/zero >"$runs/idle_new/appdata/Godot/app_userdata/Psykinetic/vulkan/pipelines.test.cache"
cache idle_new keep=1
row $(has "cache removed: caches\\old1 (past the six newest)" && has "cache removed: caches\\old2 (past the six newest)" && [ ! -d "$runs/caches/old2" ] \
	&& [ -d "$runs/caches/old3" ] && [ -d "$runs/caches/idle_new" ] && [ "$(ls "$runs/caches" | wc -l)" -eq 6 ]; echo $?) \
	"the six newest kept, the older ones removed and named"
row $(has "caches folder now: 6 caches, 4 files, 160 bytes"; echo $?) "and the caches folder's total said after the keep (6 caches; the two caches' 110 bytes and their build.txt files, 160)"
if grep -qF 'cache if cache != "" else "unknown (not a laptop runner' tools/map_bench.gd && grep -qF 'SHOT cache: %s%s' tools/remote_shot.sh; then
	echo "  PASS  a bench's BENCH ran: line and runner.log's SHOT line say the cache"
else
	echo "  FAIL  a bench's BENCH ran: line and runner.log's SHOT line say the cache"; failed=$((failed + 1))
fi

# The laptop's load (828 amended (14)): totals read before a run's Godots start, no process
# named; starved under the available-memory mark or over the CPU mark. Read here on this PC by
# the runner's own -Mode load (read-only).
load() { powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$runner" -Mode load ${1:+-Dir "$1"} 2>&1 | tr -d '\r'; }
got="$(load)"
if printf '%s' "$got" | grep -qE '^LOAD available [0-9]+ MB of [0-9]+ MB RAM; commit [0-9]+ of [0-9]+ MB; CPU busy [0-9]+% over 2 s \| starved \['; then
	echo "  PASS  the load line: available, RAM, commit and CPU busy, all totals ($got)"
else
	echo "  FAIL  the load line: got [$got]"; failed=$((failed + 1))
fi
avail="$(printf '%s' "$got" | sed -n 's/^LOAD available \([0-9]*\) MB.*/\1/p')"
cpu="$(printf '%s' "$got" | sed -n 's/.*CPU busy \([0-9]*\)%.*/\1/p')"
flag="$(printf '%s' "$got" | sed -n 's/.*starved \[\(.*\)\]$/\1/p')"
want=""
if { [ -n "$avail" ] && [ "$avail" -lt 2048 ]; } || { [ -n "$cpu" ] && [ "$cpu" -gt 50 ]; }; then want="flag"; fi
if { [ -n "$want" ] && [ -n "$flag" ]; } || { [ -z "$want" ] && [ -z "$flag" ]; }; then
	echo "  PASS  starved as its figures say (available $avail MB against 2048, CPU $cpu% against 50: [$flag])"
else
	echo "  FAIL  starved as its figures say: available $avail, CPU $cpu, flag [$flag]"; failed=$((failed + 1))
fi
got="$(load 99999999)"
if printf '%s' "$got" | grep -qE 'starved \[[0-9]+ MB available, under 99999999'; then
	echo "  PASS  a mark above what is available: starved, the figure named"
else
	echo "  FAIL  a mark above what is available: got [$got]"; failed=$((failed + 1))
fi
if sed -n '/^function Load-State/,/^function Wait-Stop/p' tools/remote_shot_run.ps1 | grep -q "Get-Process\|ProcessName\|Win32_Process\b"; then
	echo "  FAIL  the load read names no process"; failed=$((failed + 1))
else
	echo "  PASS  the load read names no process (no process list in Load-State or Avail-Mb)"
fi
if grep -qF 'grep -h "^STARVED" "$REVIEW/runner.log"' tools/remote_shot.sh && grep -qF '"STARVED AT START: ' tools/remote_shot_run.ps1 \
	&& grep -qF '"STARVED DURING THE GAME: ' tools/remote_shot_run.ps1 && grep -qF '[Job]::Peaks()' tools/remote_shot_run.ps1; then
	echo "  PASS  runner.log carries the start, during and end loads and the job's peak; remote_shot.sh says a STARVED line first and heads a tour's report with it"
else
	echo "  FAIL  runner.log's load lines or remote_shot.sh's STARVED relay missing"; failed=$((failed + 1))
fi

# The whole runner parses (its run mode needs a laptop's session; its proof is a laptop run).
parsed="$(powershell -NoProfile -NonInteractive -Command "\$e = \$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$runner', [ref]\$null, [ref]\$e); \$e.Count" 2>&1 | tr -d '\r')"
if [ "$parsed" = "0" ]; then echo "  PASS  the runner parses"; else echo "  FAIL  the runner parses: $parsed"; failed=$((failed + 1)); fi
if [ "$failed" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($failed failed)"; exit 1
