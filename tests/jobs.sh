# How many test processes to run at once (decision 278), for tests/run.sh and
# tests/land.sh. Sourced: test_jobs prints the number.
#   PSYKINETIC_TEST_JOBS, when set, decides.
#   Otherwise half the cores, less the Godot processes already running (other
#   trees' tests and benches: the machine is shared), 2 at least and 8 at most;
#   2 while another tree holds the bench lock, so its timings are not disturbed.
test_jobs() {
	if [ -n "${PSYKINETIC_TEST_JOBS:-}" ]; then
		echo "$PSYKINETIC_TEST_JOBS"
		return
	fi
	if sh tools/bench_lock.sh status 2>/dev/null | grep -q 'held by' \
			&& ! sh tools/bench_lock.sh status 2>/dev/null | grep -qF "held by $(basename "$(pwd)") ("; then
		echo 2
		return
	fi
	cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
	if command -v tasklist >/dev/null 2>&1; then
		# Windows: each console Godot runs a GUI one under it, so two a process.
		others=$(( ($(tasklist //NH 2>/dev/null | grep -ci '^godot') + 1) / 2 ))
	else
		others="$(pgrep -c -i godot 2>/dev/null || echo 0)"
	fi
	jobs=$(( cores / 2 - others ))
	[ "$jobs" -lt 2 ] && jobs=2
	[ "$jobs" -gt 8 ] && jobs=8
	echo "$jobs"
}
