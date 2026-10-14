# Sourced by the shell tests: PORT_OFFSET for this checkout, from tests/port_offsets.txt
# (see there), so worktrees can run their tests at the same time. Run from the repo root.
if [ -n "${PSYKINETIC_TEST_PORT_OFFSET:-}" ]; then
	PORT_OFFSET="$PSYKINETIC_TEST_PORT_OFFSET"
else
	folder="$(basename "$(pwd)")"
	PORT_OFFSET="$(awk -v f="$folder" '$1 == f && NF == 2 { print $2; exit }' tests/port_offsets.txt)"
	if [ -z "$PORT_OFFSET" ]; then
		total=$(printf %s "$folder" | od -An -tu1 | tr -s ' ' '\n' | awk '{ s += $1 } END { print s + 0 }')
		PORT_OFFSET=$((1000 + 200 * (total % 20)))
	fi
fi
