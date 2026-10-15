# Everything a landing runs (decision 278): the suite (tests\run.ps1), the
# network test and the state test, at the same time; one summary and one exit
# code: 0 when all three pass. Their ports and folders are their own
# (tests/suite_test checks), so they do not meet.
#   tests\land.ps1
# The suite takes the job count (tests\jobs.ps1) less the two the others use
# most of the time; each part's whole output is shown if it fails, else only
# its result line. tests/land.sh is the same; one of them is enough.
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'jobs.ps1')
$logs = Join-Path ([IO.Path]::GetTempPath()) ('psykinetic-land-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $logs | Out-Null

$suiteJobs = [Math]::Max(2, (Get-TestJobs $root) - 2)
Write-Output "landing tests: the suite ($suiteJobs at once), net_test and state_test together"
$started = Get-Date
$parts = [ordered]@{ suite = 'run.ps1'; net_test = 'net_test.ps1'; state_test = 'state_test.ps1' }
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
foreach ($name in $failed) {
	Write-Output ''
	Write-Output "### $name (failed)"
	Get-Content (Join-Path $logs "$name.out"), (Join-Path $logs "$name.err") -ErrorAction SilentlyContinue | Write-Output
}
Remove-Item $logs -Recurse -Force -ErrorAction SilentlyContinue
$seconds = [int]((Get-Date) - $started).TotalSeconds
Write-Output ''
if ($failed.Count -eq 0) {
	Write-Output "LANDING TESTS: PASS (suite, net_test, state_test; ${seconds}s)"
	exit 0
}
Write-Output "LANDING TESTS: FAIL ($($failed -join ', '); ${seconds}s)"
exit 1
