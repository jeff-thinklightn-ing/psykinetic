# Sourced by the shell tests: PORT_OFFSET for this checkout, from tests/port_offsets.txt
# (see there), so worktrees can run their tests at the same time. Run from the repo root.
if [ -n "${PSYKINETIC_TEST_PORT_OFFSET:-}" ]; then
	PORT_OFFSET="$PSYKINETIC_TEST_PORT_OFFSET"
else
	folder="$(basename "$(pwd)")"
	PORT_OFFSET="$(awk -v f="$folder" '$1 == f && NF == 2 { print $2; exit }' tests/port_offsets.txt)"
	if [ -z "$PORT_OFFSET" ]; then
		# Not listed: 5600 + 200 * (the md5 of the name, lower-cased, mod 100), as test_ports.gd's
		# hashed() (278 amended (11)).
		digest=$(printf %s "$folder" | tr 'A-Z' 'a-z' | md5sum | cut -c1-8)
		PORT_OFFSET=$((5600 + 200 * (0x$digest % 100)))
	fi
fi
