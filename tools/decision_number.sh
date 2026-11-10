#!/usr/bin/env sh
# tools/decision_number.py from sh (decision 834): take a decision number or
# an amendment label before you commit, its commands as there.
#   sh tools/decision_number.sh new <tree> "<what>"
#   sh tools/decision_number.sh amend <tree> <decision> "<what>"
#   sh tools/decision_number.sh drop <tree> <number-or-label> "<why>"
#   sh tools/decision_number.sh status [--all]
exec python -B "$(dirname "$0")/decision_number.py" "$@"
