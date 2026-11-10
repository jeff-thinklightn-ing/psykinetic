#!/usr/bin/env sh
# Snapshot test: a host run pushes a crate and writes --state; a second run
# must load the crate where it was left; a corrupt file must start fresh.
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
. tests/godot_log.sh  # Its logs in build/logs (decision 664).
DIR="$(mktemp -d)"
STATE="$DIR/world.json"
. tests/test_ports.sh
PORT=$((17781 + PORT_OFFSET))

run_host() {
	name="$1"
	shift
	"$GODOT" --log-file "$(godot_log "state_$name")" --headless --path . --host --still-monsters --no-companions --map=test_room "--port=$PORT" "--state=$STATE" "$@" </dev/null >"$DIR/$name.log" 2>"$DIR/$name.err"
}

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
# The snapshot format's version, as net/snapshot.gd writes it.
VERSION=$(sed -n 's/^const VERSION := \([0-9]*\).*$/\1/p' net/snapshot.gd)

# 1. Fresh start: the host walks three tiles west, pushing Crate1 to (7, 2).
run_host first --test-move=-3,0 --test-exit-after=5
check "$(count 'no snapshot at' "$DIR/first.log")" 1 "first run finds no snapshot and starts fresh"
check "$(count 'tiles: .*Crate1=\(7, 2\)' "$DIR/first.log")" 1 "first run ends with Crate1 pushed to (7, 2)"
check "$([ -s "$STATE" ] && echo yes || echo no)" yes "snapshot file was written"
check "$(count "\"version\": $VERSION" "$STATE")" 1 "snapshot carries version $VERSION"
# Keys are sorted, so an entry runs from its "name" to its "type"; the tile
# is pretty-printed as "tile": [ then 7, then 2 on their own lines.
crate_tile=$(sed -n '/"name": "Crate1"/,/"type": "pushable"/p' "$STATE" | grep -A2 '"tile"' | grep -cE '^[[:space:]]*7,$' || true)
check "$crate_tile" 1 "snapshot has Crate1 at [7, 2]"
check "$(count '"script": "res://sim/player.gd"' "$STATE")" 0 "players are not among the entities"
check "$(count '"player_id": "dev-host"' "$STATE")" 1 "snapshot holds the dev host's player record"
check "$(count '"script": "res://sim/(monster|pushable|cargo|chest).gd"' "$STATE")" 10 "snapshot holds the 10 level entities"
check "$(count '\[state\] final save: 10 level entities, 10 keyed' "$DIR/first.log")" 1 "the stop's final save is said once, its 10 level entities by their keys (433 amended)"

# 2. Restart: entities come from the snapshot, so Crate1 is still at (7, 2).
run_host second --test-exit-after=2
check "$(count '\[state\] loaded 10 entities and 1 player records' "$DIR/second.log")" 1 "second run loads 10 entities and 1 player record from the snapshot"
check "$(count '\[state\] lockers: 0 players' "$DIR/second.log")" 1 "and counts the players' chests that hold something (722)"
check "$(count '\[net\] Player \(dev-host\) joined as Player1 at \(8, 2\) \(back\)' "$DIR/second.log")" 1 "the host comes back where it left off, as Player1"
check "$(count 'tiles: .*Crate1=\(7, 2\)' "$DIR/second.log")" 1 "second run has Crate1 where the first left it"

# 2b. The kit: chest -> the host's slots -> chest, each across a restart.
run_host take --test-chest=take --test-exit-after=5
check "$(count 'slots: Chest1=\[\] Player1=\[bandaging_kit\]$' "$DIR/take.log")" 1 "the host takes the kit from the chest"
run_host after_take --test-exit-after=2
check "$(count 'slots: Chest1=\[\] Player1=\[bandaging_kit\]$' "$DIR/after_take.log")" 1 "after a restart the host still holds it"
run_host put --test-chest=put --test-exit-after=4
run_host after_put --test-exit-after=2
check "$(count 'slots: Chest1=\[bandaging_kit\] Player1=\[\]$' "$DIR/after_put.log")" 1 "put back, it is in the chest after a restart"

# 2c. A remade level (decision 756): a save on the hills' old grid, its
# player, a level entity and a herd there; the first boot moves the player
# to the hills' arrival, drops the rest and saves "remade"; the next does
# nothing. The save is the real one, edited: the host and a crate in the
# hills, and a deer herd at a home of the old grid.
python -B - "$STATE" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
room = data["zones"]["test_room"]
crate = [e for e in room["entities"] if e.get("name") == "Crate1"][0]
data["zones"]["hills"] = {"tick": 0, "entities": [crate], "respawns": [], "ground": [], "records": []}
for record in data["players"]:
    if record["player_id"] == "dev-host":
        record["zone"] = "hills"
        record["tile"] = [80, 30]
herds = data.setdefault("herds", {})
herds.setdefault("groups", {})["old-hills-deer"] = {"species": "deer", "area": "hills", "home": [80, 30], "count": 4.0, "out": 0, "made": 0}
herds["seeded"] = sorted(set(herds.get("seeded", [])) | {"hills"})
data.setdefault("clearing", {})["hills"] = {"80,30": [1, 0]}
data.pop("remade", None)
json.dump(data, open(path, "w", encoding="utf-8"), indent="\t")
PY
run_host remade --test-exit-after=2
check "$(count '\[level\] remade forest \(760\): 0 players moved' "$DIR/remade.log")" 1 "the forest, remade too, with nobody there"
check "$(count '\[level\] remade hills \(756\): 1 players moved; dropped 1 entities, 1 herd groups, 0 plots, 1 felled cells' "$DIR/remade.log")" 1 "a save on the hills' old grid: its player moved, its entity and herd dropped, said once by count (756)"
check "$(count 'joined as Player1 at \(7, 112\) \(back\)' "$DIR/remade.log")" 1 "the host comes back at the hills' arrival from the wilds"
check "$(sed -n '/"remade": {/,/}/p' "$STATE" | grep -c '"hills": 756' || true)" 1 "the save keeps the remake as done"
check "$(count 'old-hills-deer' "$STATE")" 0 "the old grid's herd is gone from the save"
run_host remade_again --test-exit-after=2
check "$(count '\[level\] remade' "$DIR/remade_again.log")" 0 "the next boot moves nothing"
check "$(count 'joined as Player1 at \(7, 112\) \(back\)' "$DIR/remade_again.log")" 1 "and the host is where it was left, in the hills"

# 2d. The forest remade (decision 760) the same way, the hills' remake
# already done in the save: only the forest is moved off, once.
python -B - "$STATE" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
room = data["zones"]["test_room"]
crate = [e for e in room["entities"] if e.get("name") == "Crate1"][0]
data["zones"]["forest"] = {"tick": 0, "entities": [crate], "respawns": [], "ground": [], "records": []}
for record in data["players"]:
    if record["player_id"] == "dev-host":
        record["zone"] = "forest"
        record["tile"] = [46, 34]
herds = data.setdefault("herds", {})
herds.setdefault("groups", {})["old-forest-deer"] = {"species": "deer", "area": "forest", "home": [46, 34], "count": 3.0, "out": 0, "made": 0}
herds["seeded"] = sorted(set(herds.get("seeded", [])) | {"forest"})
data.setdefault("clearing", {})["forest"] = {"46,34": [1, 0]}
data.setdefault("remade", {}).pop("forest", None)
json.dump(data, open(path, "w", encoding="utf-8"), indent="\t")
PY
run_host forest_remade --test-exit-after=2
check "$(count '\[level\] remade forest \(760\): 1 players moved; dropped 1 entities, 1 herd groups, 0 plots, 1 felled cells' "$DIR/forest_remade.log")" 1 "a save on the forest's old grid: its player moved, its entity and herd dropped, said once by count (760)"
check "$(count '\[level\] remade hills' "$DIR/forest_remade.log")" 0 "the hills, remade already, left be"
check "$(count 'joined as Player1 at \(220, 48\) \(back\)' "$DIR/forest_remade.log")" 1 "the host comes back at the forest's arrival from the wilds"
check "$(sed -n '/"remade": {/,/}/p' "$STATE" | grep -c '"forest": 760' || true)" 1 "the save keeps the forest's remake as done"
check "$(count 'old-forest-deer' "$STATE")" 0 "the forest's old herd is gone from the save"

# 2e. A level held back (Level.SHELVED, 820): the box's boar lair was live
# from v0.1.206, so a save may hold a player inside it and its zone's state.
# The boot puts the player back in the forest by its old mouth, drops the
# zone's state, says so by count, and never opens it.
python -B - "$STATE" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
room = data["zones"]["test_room"]
crate = [e for e in room["entities"] if e.get("name") == "Crate1"][0]
data["zones"]["boar_lair"] = {"tick": 0, "entities": [crate], "respawns": [], "ground": [], "records": []}
for record in data["players"]:
    if record["player_id"] == "dev-host":
        record["zone"] = "boar_lair"
        record["tile"] = [10, 10]
json.dump(data, open(path, "w", encoding="utf-8"), indent="\t")
PY
run_host shelved --test-exit-after=2
check "$(count '\[level\] shelved boar_lair: 1 moved to forest, 1 saved states dropped' "$DIR/shelved.log")" 1 "a player saved in a held-back level moved to its land, its zone's state dropped, said once by count (820)"
check "$(count 'joined as Player1 at \(124, 175\) \(back\)' "$DIR/shelved.log")" 1 "the host comes back in the forest by the lair's old mouth"
check "$(count '"boar_lair"' "$STATE")" 0 "the save no longer names the held-back level"

# 2f. A record saved before the pack's third row (decision 819): 18 slots, a
# ration in the pack and a hood on the head. It loads as 27 (the satchel's
# slot and row after the third row, 819 amended), nothing moved, the new
# rows empty, and is saved back so.
python -B - "$STATE" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for record in data["players"]:
    if record["player_id"] == "dev-host":
        slots = [""] * 18
        slots[0] = "ration"
        slots[11] = "hood"
        record["slots"] = slots
        record.pop("items", None)
json.dump(data, open(path, "w", encoding="utf-8"), indent="	")
PY
run_host old_slots --test-exit-after=2
old_slots=$(python -B - "$STATE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
record = [r for r in data["players"] if r["player_id"] == "dev-host"][0]
slots = record["slots"]
print("ok" if len(slots) == 27 and slots[0] == "ration" and slots[11] == "hood" and all(s == "" for s in slots[18:]) else "bad %d" % len(slots))
PY
)
check "$old_slots" ok "an 18-slot record (before 819) loads and saves as 27: the ration and the hood where they were, the third row empty"

# 2g. A record in today's shape (819 amended): 22 slots, a ration in the pack,
# a sword in the right hand, robes worn, a hood on the head and arrows in
# the third row's last. It loads as 27, everything where it was, still in
# hand and worn, the satchel's slot and row empty, and is saved back so.
python -B - "$STATE" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for record in data["players"]:
    if record["player_id"] == "dev-host":
        slots = [""] * 22
        slots[0] = "ration"
        slots[4] = "sword"
        slots[6] = "robes"
        slots[11] = "hood"
        slots[21] = "arrows"
        record["slots"] = slots
        record.pop("items", None)
json.dump(data, open(path, "w", encoding="utf-8"), indent="	")
PY
run_host today_slots --test-exit-after=2
today_slots=$(python -B - "$STATE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
record = [r for r in data["players"] if r["player_id"] == "dev-host"][0]
slots = record["slots"]
want = {0: "ration", 4: "sword", 6: "robes", 11: "hood", 21: "arrows"}
print("ok" if len(slots) == 27 and all(slots[i] == want.get(i, "") for i in range(27)) else "bad %s" % slots)
PY
)
check "$today_slots" ok "a 22-slot record (today's, before 819 amended) loads and saves as 27: the ration, the sword in hand, the robes, the hood and the arrows where they were; the bag and its row empty"

# 3. Corrupt file: start fresh, and overwrite it with a good one on exit.
echo 'this is not json' >"$STATE"
run_host third --test-exit-after=2
check "$(count 'does not parse.*starting fresh' "$DIR/third.log")" 1 "a corrupt snapshot is logged and ignored"
check "$(count 'tiles: .*Crate1=\(8, 2\)' "$DIR/third.log")" 1 "and the room is generated fresh (Crate1 back at (8, 2))"
check "$(count 'tiles: .*Player1=\(11, 2\)' "$DIR/third.log")" 1 "with the host at a start tile"
check "$(count "\"version\": $VERSION" "$STATE")" 1 "the corrupt file was replaced by a good snapshot on exit"
check "$(cat "$DIR"/*.err 2>/dev/null | wc -l | tr -d ' ')" 0 "no run printed errors"

echo
if [ "$failures" -gt 0 ]; then
	echo "RESULT: FAIL ($failures failed) (logs in $DIR)"
	exit 1
fi
echo "RESULT: PASS (logs in $DIR)"
exit 0
