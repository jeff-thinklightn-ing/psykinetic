#!/usr/bin/env sh
# Deploys the dedicated server on this box: clean, pull, import, export,
# install, restart.
# Expects the repo at ~/psykinetic (or $PSYKINETIC_REPO), a Linux Godot
# editor binary with the Linux export templates installed (GODOT_PATH, or
# the newest ~/godot/Godot_v*_linux.x86_64 when that is not set, as over a
# non-interactive ssh where .bashrc is not read), and the unit from
# server/psykinetic.service already installed. See docs/server.md.
# Every sudo here is covered by /etc/sudoers.d/psykinetic-deploy.
set -eu

REPO="${PSYKINETIC_REPO:-$HOME/psykinetic}"
GODOT="${GODOT_PATH:-$(ls -1 "$HOME"/godot/Godot_v*_linux.x86_64 2>/dev/null | sort -V | tail -n 1)}"
test -n "$GODOT" || { echo "deploy: set GODOT_PATH to a Linux Godot binary (none under ~/godot)" >&2; exit 1; }
test -x "$GODOT" || { echo "deploy: $GODOT is not executable" >&2; exit 1; }
echo "deploy: godot $GODOT"
PRESET="Linux Server"
INSTALL_DIR=/opt/psykinetic

cd "$REPO"
# Untracked files the engine generates (a .uid or .import left by an
# import here) would block the pull as soon as the repo brings its own
# copy. Only untracked ones go; tracked and ignored files are untouched.
git clean -f -- '*.uid' '*.import'
git pull --ff-only
# Import only now, on the pulled tree, never before: anything generated
# here is then for files the repo already has as they are.
"$GODOT" --headless --path . --import

mkdir -p build
"$GODOT" --headless --path . --export-release "$PRESET" build/psykinetic-server.x86_64
test -s build/psykinetic-server.x86_64
test -s build/psykinetic-server.pck

sudo install -d -o psykinetic -g psykinetic "$INSTALL_DIR"
sudo install -m 755 build/psykinetic-server.x86_64 "$INSTALL_DIR/psykinetic-server"
sudo install -m 644 build/psykinetic-server.pck "$INSTALL_DIR/psykinetic-server.pck"

sudo systemctl restart psykinetic
# Piped, so systemctl uses no pager; the exact words sudoers allows.
sudo systemctl status psykinetic | head -n 12
