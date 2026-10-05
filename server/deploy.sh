#!/usr/bin/env sh
# Deploys the dedicated server on this box: pull, export, install, restart.
# Expects the repo at ~/psykinetic (or $PSYKINETIC_REPO), GODOT_PATH pointing
# at a Linux Godot editor binary with the Linux export templates installed,
# and the unit from server/psykinetic.service already installed.
# See docs/server.md.
set -eu

REPO="${PSYKINETIC_REPO:-$HOME/psykinetic}"
GODOT="${GODOT_PATH:?set GODOT_PATH to a Linux Godot binary}"
PRESET="Linux Server"
INSTALL_DIR=/opt/psykinetic

cd "$REPO"
git pull --ff-only

mkdir -p build
"$GODOT" --headless --path . --export-release "$PRESET" build/psykinetic-server.x86_64
test -s build/psykinetic-server.x86_64
test -s build/psykinetic-server.pck

sudo install -d -o psykinetic -g psykinetic "$INSTALL_DIR"
sudo install -m 755 build/psykinetic-server.x86_64 "$INSTALL_DIR/psykinetic-server"
sudo install -m 644 build/psykinetic-server.pck "$INSTALL_DIR/psykinetic-server.pck"

sudo systemctl restart psykinetic
sudo systemctl --no-pager --lines=5 status psykinetic
