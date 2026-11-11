#!/bin/bash
# Walk probe on the Lenovo: real time, real window, no movie maker; [gait] lines in godot.log.
cd "$(dirname "$0")/.." || exit 1
SHA=$1; NAME=$2; shift 2
for try in $(seq 1 60); do
	out="$(sh tools/remote_shot.sh --runner lenovo --timeout 10 $SHA $NAME -- --max-fps 60 --scene res://tools/clip.tscn -- --host --scenario=walkreel --clip-max-seconds=40 "$@" 2>&1 | grep -v 'post-quantum\|store now\|openssh.com')"
	if printf '%s' "$out" | grep -q "runner is busy"; then echo "busy, waiting"; sleep 120; continue; fi
	printf '%s\n' "$out" | tail -8; break
done
grep -c '^\[gait\]' C:/dev/review/$NAME/godot.log
grep 'SCRIPT ERROR\|^ERROR' C:/dev/review/$NAME/godot.log | sort | uniq -c | head -5
grep "BENCH ran\|used during\|power" C:/dev/review/$NAME/runner.log 2>/dev/null | head -4
