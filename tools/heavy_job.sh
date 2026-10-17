#!/usr/bin/env sh
# tools/heavy_job.py from sh (decision 394): the resource gate for heavy
# jobs, its commands as there.
#   sh tools/heavy_job.sh run <tree> <kind> -- <command...>
exec python "$(dirname "$0")/heavy_job.py" "$@"
