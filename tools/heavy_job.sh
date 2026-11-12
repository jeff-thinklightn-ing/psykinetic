#!/usr/bin/env sh
# tools/heavy_job.py from sh (decision 394): the resource gate for heavy
# jobs, its commands as there.
#   sh tools/heavy_job.sh run <tree> <kind> -- <command...>
# A take names the shell that ran this as its caller (394 amended (37)): its
# guard, the process that lives while the take is held (this one is gone once
# python starts, and `take` ends at once). Windows' id where Git Bash has one.
if [ "${1:-}" = take ]; then
	caller="$(cat "/proc/$PPID/winpid" 2>/dev/null || echo "$PPID")"
	exec python "$(dirname "$0")/heavy_job.py" "$@" --caller "$caller"
fi
exec python "$(dirname "$0")/heavy_job.py" "$@"
