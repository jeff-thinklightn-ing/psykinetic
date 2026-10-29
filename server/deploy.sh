#!/usr/bin/env sh
# Deploys the dedicated server on this box: clean, pull, import, export,
# install, restart.
#   server/deploy.sh         once the build is made, the running server counts
#                            down 60 s (PSYKINETIC_RESTART_SECONDS), telling
#                            the players, saves and exits; the new build is
#                            installed and started, and the clients reconnect
#                            by themselves (decision 240)
#   server/deploy.sh --now   installs and restarts at once, without a countdown
#   server/deploy.sh --staged first tries the new build on staging ports
#                            (server/stage.sh, decision 242) and stops, the
#                            running server untouched, if it fails
#   server/deploy.sh --ref=v0.1.190   a rollback (decision 730): builds that
#                            release's tag instead of main, the repo left on
#                            it, detached, until the next deploy without
#                            --ref puts it back on main
# Expects the repo at ~/psykinetic (or $PSYKINETIC_REPO) on main, a Linux Godot
# editor binary with the Linux export templates installed (GODOT_PATH, or
# the newest ~/godot/Godot_v*_linux.x86_64 when that is not set, as over a
# non-interactive ssh where .bashrc is not read), and the unit from
# server/psykinetic.service already installed. See docs/server.md.
# Every sudo here is one the host's allowlist (/etc/sudoers.d/jequig-allowlist)
# runs without a password.
set -eu

NOW=0
STAGED=0
REF=""
for arg in "$@"; do
	case "$arg" in
		--now) NOW=1 ;;
		--staged) STAGED=1 ;;
		--ref=v[0-9]*.[0-9]*.[0-9]*) REF="${arg#--ref=}" ;;
		*) echo "usage: $0 [--staged] [--now] [--ref=vX.Y.Z]" >&2; exit 2 ;;
	esac
done
case "$REF" in *[!0-9v.]*) echo "deploy: --ref takes a release tag, vX.Y.Z" >&2; exit 2 ;; esac
# A checkout of the tag replaces this file while it runs, and sh reads a
# script as it goes: a rollback runs from a copy.
if [ -n "$REF" ] && [ -z "${PSYKINETIC_DEPLOY_COPY:-}" ]; then
	copy="$(mktemp -t psykinetic-deploy.XXXXXX)"
	cp "$0" "$copy"
	PSYKINETIC_DEPLOY_COPY="$copy" exec sh "$copy" "$@"
fi
# The shell holds the copy open, so it can go now (the EXIT traps below are
# the restart's).
if [ -n "${PSYKINETIC_DEPLOY_COPY:-}" ]; then
	rm -f "$PSYKINETIC_DEPLOY_COPY"
fi
COUNTDOWN="${PSYKINETIC_RESTART_SECONDS:-60}"

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
if [ -n "$REF" ]; then
	git fetch -q --tags origin
	git checkout -q --detach "refs/tags/$REF"
	echo "deploy: rollback to $REF ($(git rev-parse --short HEAD))"
else
	# After a rollback the repo sits on a tag; checking out main here would
	# replace this script mid-run, so the caller does it (deploy_box does).
	test "$(git rev-parse --abbrev-ref HEAD)" = main || { echo "deploy: the repo is not on main (a rollback left it on $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)): git checkout main first" >&2; exit 1; }
	git pull --ff-only
fi
# Import only now, on the pulled tree, never before: anything generated
# here is then for files the repo already has as they are.
"$GODOT" --headless --path . --import

mkdir -p build
"$GODOT" --headless --path . --export-release "$PRESET" build/psykinetic-server.x86_64
test -s build/psykinetic-server.x86_64
test -s build/psykinetic-server.pck

if [ "$STAGED" -eq 1 ]; then
	bash "$REPO/server/stage.sh" || { echo "deploy: the staged build failed; the running server is untouched" >&2; exit 1; }
fi

# The graceful restart (decision 240): the console's stop counts down,
# telling the players, saves and exits 0, which the unit's Restart=on-failure
# leaves down; the new build goes in only then (a running server reads its
# .pck as it goes) and is started. Clients reconnect by themselves. A server
# too old for it, none running, or --now: install and systemctl restart, as
# before.
graceful=0
if [ "$NOW" -eq 0 ] && systemctl is-active --quiet psykinetic; then
	reply="$(bash "$REPO/server/admin.sh" stop "$COUNTDOWN" update 2>&1 || true)"
	echo "deploy: $reply"
	case "$reply" in
		restarting*) graceful=1 ;;
	esac
fi
if [ "$graceful" -eq 1 ]; then
	# Whatever goes wrong from here, the server is started again.
	trap 'sudo systemctl restart psykinetic' EXIT
	waited=0
	while systemctl is-active --quiet psykinetic; do
		waited=$((waited + 1))
		if [ "$waited" -gt $((COUNTDOWN + 60)) ]; then
			echo "deploy: still running ${waited} s after its stop; installing and restarting it"
			break
		fi
		sleep 1
	done
fi

# Root-owned: the service must not be able to replace its own binary (decision 690).
sudo install -d -o root -g root "$INSTALL_DIR"
sudo install -m 755 build/psykinetic-server.x86_64 "$INSTALL_DIR/psykinetic-server"
sudo install -m 644 build/psykinetic-server.pck "$INSTALL_DIR/psykinetic-server.pck"

sudo systemctl restart psykinetic
trap - EXIT
# Piped, so systemctl uses no pager; the exact words sudoers allows.
sudo systemctl status psykinetic | head -n 12
