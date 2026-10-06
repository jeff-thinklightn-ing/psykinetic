#!/usr/bin/env bash
# Sends one console command to the running server and prints its reply.
#   server/admin.sh players
#   server/admin.sh respawn
#   server/admin.sh reset
#   server/admin.sh save
# Talks to --admin-port on localhost (7778 in the unit), so run it on the box.
# Needs bash for /dev/tcp; no netcat required.
set -eu
PORT="${PSYKINETIC_ADMIN_PORT:-7778}"
if [ $# -eq 0 ]; then
	echo "usage: $0 <reset|respawn|players|save|help>" >&2
	exit 2
fi
exec 3<>"/dev/tcp/127.0.0.1/$PORT"
printf '%s\n' "$*" >&3
cat <&3
exec 3<&-
