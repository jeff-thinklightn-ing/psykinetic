#!/usr/bin/env bash
# A clip of a scenario (tools/clip.gd): played with a window and recorded
# by Godot's movie maker at FPS frames a second, then stitched by ffmpeg
# into <out>.mp4 (with the game's sound) and a smaller, silent <out>.gif;
# the per-tick log beside them as
# <out>.log. User data goes to a temp folder (never the shared user://).
#   tools/clip.sh <scenario> <out path without extension> [fps=30] [max seconds=60]
# Godot quits after max seconds of frames whatever the scenario does (--quit-after,
# so even a scenario whose script does not load stops), and clip.gd stops itself
# then too.
set -u
GODOT="${GODOT_PATH:-godot}"
case "$GODOT" in
	*_console.exe) ;;
	*.exe) console="${GODOT%.exe}_console.exe"; [ -f "$console" ] && GODOT="$console" ;;
esac
SCENARIO="$1"
OUT="$2"
FPS="${3:-30}"
MAX="${4:-60}"
cd "$(dirname "$0")/.."
FRAMES="$(mktemp -d)"
trap 'rm -rf "$FRAMES"' EXIT  # Frames are big: gone however this ends.
mkdir -p "$FRAMES/appdata" "$(dirname "$OUT")"
export APPDATA="$(cygpath -w "$FRAMES/appdata" 2>/dev/null || echo "$FRAMES/appdata")"
"$GODOT" --path . --resolution 1280x720 --write-movie "$FRAMES/frame.png" --fixed-fps "$FPS" --quit-after $((MAX * FPS)) \
	--scene res://tools/clip.tscn -- "--scenario=$SCENARIO" "--clip-max-seconds=$MAX" </dev/null 2>&1 | grep "^\[clip\]\|ERROR" >"$OUT.log"
# The movie maker writes the game's sound beside the frames (frame.wav): the
# mp4 carries it (the gif can't).
AUDIO=()
[ -f "$FRAMES/frame.wav" ] && AUDIO=(-i "$FRAMES/frame.wav" -c:a aac -b:a 160k -shortest)
ffmpeg -loglevel error -y -framerate "$FPS" -i "$FRAMES/frame%08d.png" "${AUDIO[@]}" -c:v libx264 -pix_fmt yuv420p "$OUT.mp4"
ffmpeg -loglevel error -y -i "$OUT.mp4" -vf "fps=15,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" "$OUT.gif"
echo "$(ls "$FRAMES"/frame*.png | wc -l) frames: $OUT.mp4, $OUT.gif, $OUT.log"
rm -rf "$FRAMES"
