# walkreel: walk, follow and townsfolk reels

`tools/clip.gd`'s `walkreel` scenario walks the host's player by clicks, a player's pace, and logs each frame
of its body (`[gait]` lines) and of any companion (`[wren]` lines) for `tools/gait_read.py`.

Without `--map` it walks an open floor of its own (the jog reels). With `--map` it walks a real map, the town
as a player meets it (the coordinator, 11-11: walk, follow and townsfolk reels on Umbrage's streets).

## Arguments (after the scene's `--`)

| | |
|---|---|
| `--host` | always: without it the game waits at the connect screen |
| `--scenario=walkreel` | |
| `--map=<level>` | the real map (`wilds` holds Umbrage) |
| `--start=x,y` | the player put there (its companion beside it) |
| `--route="x,y,pause_s;..."` | each leg one click to x,y, then that many seconds stood |
| `--hour=h` | the hour of day (12 for noon) |
| `--wren` | companions on: she follows |
| `--cam=near` | the play camera at its nearest zoom (else its usual) |
| `--yaw=<deg> --pitch=<deg>` | the camera held there, else the game's |
| `--jog=<clip>:<pace>` | another jog clip in Jog_Short's place, at its pace in m/s |
| `--clip-max-seconds=n` | the reel's longest |

## Two passes per reel

1. The play camera as the game has it (`--cam=near`, no yaw): what Jeff meets, walls and all.
2. The same route with the camera held at one yaw (`--yaw`, `--pitch`) so the main legs cross the screen
   side-on: for judging the legs.

## Example: Umbrage, the companions' route, on the Lenovo

```
sh tools/remote_shot.sh --runner lenovo --timeout 10 <sha> <name> -- \
  --write-movie '{out}/clip.avi' --fixed-fps 30 --quit-after 2400 --scene res://tools/clip.tscn -- \
  --host --scenario=walkreel --map=wilds --start=192,198 \
  '--route=181,196,0;180,196,0;179,196,0;183,196,2;212,198,1.5;212,208,0.6;181,196,0' \
  --hour=12 --wren --cam=near --clip-max-seconds=50
```

The film and its log come back to `C:/dev/review/<name>`. Grep `godot.log` for `ERROR` and look at a still
before reading any number.
