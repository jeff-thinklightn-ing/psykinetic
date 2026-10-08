# Runs the headless sim tests, one scene after another.
# Exit code 0 = every assertion in every scene passed, 1 = any failed.
# Godot is taken from $env:GODOT_PATH, or `godot` on PATH.
$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }

# The Windows GUI build detaches from the console (no output, no exit code);
# use the console build that ships next to it when there is one.
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

# A scene that has not finished in this many seconds (a parse error leaves
# Godot running, waiting) is killed and fails the run.
$timeout = if ($env:TEST_TIMEOUT) { [int]$env:TEST_TIMEOUT } else { 300 }

$scenes = @('tests/push_test.tscn', 'tests/respawn_test.tscn', 'tests/companion_test.tscn', 'tests/spawn_test.tscn', 'tests/mirror_test.tscn', 'tests/edge_test.tscn', 'tests/controls_test.tscn', 'tests/view_test.tscn')
$code = 0
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
	foreach ($scene in $scenes) {
		Write-Output "### $scene"
		# A script error aborts a test function without failing an assertion,
		# so treat any engine error as a failure too.
		$out = [System.IO.Path]::GetTempFileName()
		$err = [System.IO.Path]::GetTempFileName()
		$process = Start-Process -FilePath $godot -ArgumentList '--headless', '--path', '.', '--scene', $scene `
			-RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
		$null = $process.Handle  # Without it Windows PowerShell may lose the exit code.
		$finished = $process.WaitForExit($timeout * 1000)
		if (-not $finished) {
			$process | Stop-Process -Force
			$process.WaitForExit()
		}
		$output = @(Get-Content $out) + @(Get-Content $err) | ForEach-Object { "$_" }
		Remove-Item $out, $err -ErrorAction SilentlyContinue
		$output | Write-Output
		if (-not $finished) {
			Write-Output "FAIL  $scene did not finish within ${timeout}s (a parse error, or a hang): killed"
			$code = 1
		} elseif ($process.ExitCode -ne 0) { $code = 1 }
		if ($output | Select-String 'SCRIPT ERROR|^ERROR:') { $code = 1 }
	}
} finally {
	Pop-Location
}
exit $code
