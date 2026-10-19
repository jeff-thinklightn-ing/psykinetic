# Everything a landing runs (decision 278): the suite (tests\run.ps1), the
# network test, the state test and the exported server's boot (decision
# 450), at the same time; one summary and one exit code: 0 when all pass. Their ports and folders are their own
# (tests/suite_test checks), so they do not meet.
#   tests\land.ps1
# The suite takes the job count (tests\jobs.ps1) less the two the others use
# most of the time; each part's whole output is shown if it fails, else only
# its result line. tests/land.sh is the same; one of them is enough.
# A heavy job (decision 394): through the gate as <checkout> suite, adopting
# this checkout's take of suite if it holds one (see tests/land.sh);
# heavy_job_test first.
$root = Split-Path $PSScriptRoot -Parent
$tree = Split-Path $root -Leaf
$gate = Join-Path $root 'tools\heavy_job.py'
if (-not $env:HEAVY_JOB_INSIDE) {
	Write-Output "landing tests: through the heavy-job gate as $tree suite (decision 394)"
	$env:HEAVY_JOB_INSIDE = '1'
	try {
		& python $gate run $tree suite -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
		exit $LASTEXITCODE
	} finally {
		Remove-Item Env:HEAVY_JOB_INSIDE -ErrorAction SilentlyContinue
	}
}
. (Join-Path $PSScriptRoot 'jobs.ps1')
$logs = Join-Path ([IO.Path]::GetTempPath()) ('psykinetic-land-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $logs | Out-Null

$suiteJobs = [Math]::Max(2, (Get-TestJobs $root) - 2)
Write-Output "landing tests: the suite ($suiteJobs at once), net_test, state_test and server_boot_test together"
$started = Get-Date
$gateTest = & python (Join-Path $root 'tests\heavy_job_test.py') 2>&1
$gateOk = $LASTEXITCODE -eq 0
Write-Output "$(if ($gateOk) { 'PASS' } else { 'FAIL' })  heavy_job_test"
$parts = [ordered]@{ suite = 'run.ps1'; net_test = 'net_test.ps1'; state_test = 'state_test.ps1'; server_boot_test = 'server_boot_test.ps1' }
$running = @{}
$env:PSYKINETIC_TEST_JOBS = "$suiteJobs"  # Only the suite reads it.
try {
	foreach ($name in $parts.Keys) {
		$process = Start-Process -FilePath 'powershell.exe' -NoNewWindow -PassThru `
			-ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $parts[$name]) `
			-RedirectStandardOutput (Join-Path $logs "$name.out") -RedirectStandardError (Join-Path $logs "$name.err")
		$null = $process.Handle  # Without it Windows PowerShell may lose the exit code.
		$running[$name] = @{ Process = $process; Started = Get-Date }
	}
} finally {
	Remove-Item Env:PSYKINETIC_TEST_JOBS -ErrorAction SilentlyContinue
}
$failed = @()
if (-not $gateOk) {
	$failed += 'heavy_job_test'
	$gateTest | Write-Output
}
$done = @{}
while ($done.Count -lt $parts.Count) {
	Start-Sleep -Milliseconds 500
	foreach ($name in $parts.Keys) {
		$entry = $running[$name]
		if ($done.ContainsKey($name) -or -not $entry.Process.HasExited) { continue }
		$entry.Process.WaitForExit()
		$done[$name] = $true
		$took = [int]((Get-Date) - $entry.Started).TotalSeconds
		$ok = $entry.Process.ExitCode -eq 0
		if (-not $ok) { $failed += $name }
		Write-Output "$(if ($ok) { 'PASS' } else { 'FAIL' })  $name ${took}s"
	}
}
# A failed run's logs, kept where they survive the run: .godot\test_failures
# (per checkout, never committed), the last ten. Prints where.
function Save-Failure($what, $from) {
	$folder = Join-Path $root '.godot\test_failures'
	$kept = Join-Path $folder ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $what)
	New-Item -ItemType Directory -Force $kept | Out-Null
	Copy-Item $from $kept -Recurse -Force -ErrorAction SilentlyContinue
	Get-ChildItem $folder -Directory | Sort-Object Name | Select-Object -SkipLast 10 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
	Write-Output "kept in $kept"
}
foreach ($name in $failed) {
	Write-Output ''
	Write-Output "### $name (failed)"
	Get-Content (Join-Path $logs "$name.out"), (Join-Path $logs "$name.err") -ErrorAction SilentlyContinue | Write-Output
}
if ($failed.Count -gt 0) { Save-Failure 'land' (Join-Path $logs '*') }
Remove-Item $logs -Recurse -Force -ErrorAction SilentlyContinue
$seconds = [int]((Get-Date) - $started).TotalSeconds
Write-Output ''
if ($failed.Count -eq 0) {
	Write-Output "LANDING TESTS: PASS (suite, net_test, state_test, server_boot_test; ${seconds}s)"
	exit 0
}
Write-Output "LANDING TESTS: FAIL ($($failed -join ', '); ${seconds}s)"
exit 1
