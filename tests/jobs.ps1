# How many test processes to run at once (decision 278), for tests\run.ps1 and
# tests\land.ps1; tests/jobs.sh is the same for the shell scripts. Dot-sourced:
# Get-TestJobs <repo root> returns the number.
#   $env:PSYKINETIC_TEST_JOBS, when set, decides.
#   Otherwise half the cores, less the Godot processes already running (other
#   trees' tests and benches: the machine is shared), 2 at least and 8 at most;
#   2 while another tree holds the bench lock, so its timings are not disturbed.
function Get-TestJobs($root) {
	if ($env:PSYKINETIC_TEST_JOBS) { return [int]$env:PSYKINETIC_TEST_JOBS }
	$lock = 'C:\dev\bench.lock'
	if ($env:PSYKINETIC_BENCH_LOCK) { $lock = $env:PSYKINETIC_BENCH_LOCK -replace '^/c/', 'C:\' -replace '/', '\' }
	$owner = Join-Path $lock 'owner'
	if ((Test-Path $lock) -and ((Get-Content $owner -Raw -ErrorAction SilentlyContinue) + '').Trim() -ne (Split-Path $root -Leaf)) { return 2 }
	$cores = [Environment]::ProcessorCount
	# Each console Godot runs a GUI one under it: two processes a test.
	$others = [int][Math]::Ceiling(@(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue).Count / 2)
	return [Math]::Max(2, [Math]::Min(8, [int]($cores / 2) - $others))
}
