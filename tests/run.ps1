# Runs the headless sim tests: every tests/*_test.tscn, several at once
# (decision 278). Exit code 0 = every assertion in every scene passed, 1 = any
# failed: a scene's non-zero exit, a timeout, or SCRIPT ERROR / ERROR: in its
# output.
#   tests\run.ps1           in parallel: $env:PSYKINETIC_TEST_JOBS at once,
#                           else half the cores less the other Godot processes
#                           running (other trees' tests), 2 to 8; 2 while
#                           another tree holds the bench lock
#   tests\run.ps1 -Serial   one after another, each scene's output as it goes
# The slowest scenes start first (their last times are kept in
# .godot\test_durations.txt); a line prints as each finishes, and at the end
# the whole output of every scene that failed, then a summary.
# Godot is taken from $env:GODOT_PATH, or `godot` on PATH.
param([switch]$Serial)
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

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'jobs.ps1')
$durations = Join-Path $root '.godot\test_durations.txt'
# Logs of this run's own: other worktrees may be running the suite too.
$logs = Join-Path ([IO.Path]::GetTempPath()) ('psykinetic-run-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $logs | Out-Null

# Every tests/*_test.tscn, found by name, so a new test scene needs no edit here (a
# shared list made every tree adding a test conflict with the others). Slowest
# first by the last run's times; a scene not timed yet goes first too (it may be slow).
$last = @{}
if (Test-Path $durations) {
	foreach ($line in Get-Content $durations) {
		$fields = $line -split ' ', 2
		if ($fields.Count -eq 2 -and -not $last.ContainsKey($fields[1])) { $last[$fields[1]] = [int]$fields[0] }
	}
}
$scenes = @(Get-ChildItem (Join-Path $PSScriptRoot '*_test.tscn') | ForEach-Object { "tests/$($_.Name)" } |
	Sort-Object @{ Expression = { if ($last.ContainsKey($_)) { $last[$_] } else { 999 } }; Descending = $true })

function Get-Name($scene) { [IO.Path]::GetFileNameWithoutExtension($scene) }

# The scene's verdict once its process has ended (or been killed), its output
# put together in <name>.log: "PASS  name 12s" or "FAIL  name 3s: why".
function Get-Verdict($scene, $process, $killed, $took) {
	$log = Join-Path $logs "$(Get-Name $scene).log"
	$output = @(Get-Content "$log.out" -ErrorAction SilentlyContinue) + @(Get-Content "$log.err" -ErrorAction SilentlyContinue) | ForEach-Object { "$_" }
	$why = ''
	if ($killed) {
		$why = "did not finish within ${timeout}s (a parse error, or a hang): killed"
		$output += "FAIL  $scene $why"
	} elseif ($output | Select-String 'SCRIPT ERROR|^ERROR:') {
		$why = "an engine error: $(($output | Select-String 'SCRIPT ERROR|^ERROR:' | Select-Object -First 1).Line)"
	} elseif ($process.ExitCode -ne 0) {
		$result = $output | Select-String '^RESULT:' | Select-Object -First 1
		$why = if ($result) { $result.Line } else { "exit $($process.ExitCode)" }
	}
	$output | Set-Content $log
	if ($why -eq '') { "PASS  $(Get-Name $scene) ${took}s" } else { "FAIL  $(Get-Name $scene) ${took}s: $why" }
}

# What a scene that died at launch may show (decision 530): Godot's banner,
# blank lines and, since 530 amended, the engine's crash-handler block. Any
# other line is the game's own (tests/run.sh's LAUNCH_ONLY).
$launchOnly = '^Godot Engine v|^\s*$|^=+$|^CrashHandlerException:|^Engine version:|^Dumping the backtrace|^Load address:|^\[[0-9]+\] |^-- END OF .*BACKTRACE --$'

function Get-SceneOutput($scene) {
	$log = Join-Path $logs "$(Get-Name $scene).log"
	@(Get-Content "$log.out" -ErrorAction SilentlyContinue) + @(Get-Content "$log.err" -ErrorAction SilentlyContinue) | ForEach-Object { "$_" }
}

# Whether a scene died at launch (decision 530): a non-zero exit within 10 s
# with nothing but $launchOnly's lines in its output (no line of the game's
# own, no RESULT). A scene that ran any of its own code is never retried.
function Test-LaunchFailed($scene, $process, $killed, $took) {
	if ($killed -or $process.ExitCode -eq 0 -or $took -gt 10) { return $false }
	return -not (Get-SceneOutput $scene | Where-Object { $_ -notmatch $launchOnly })
}

# A launch failure's diagnosis, logged in the gate's log too (heavy_job
# summary counts them): the exit code, where Godot resolves, free RAM and
# commit; a crash's top frame and whole backtrace (summary groups by top frame).
function Get-LaunchNote($scene, $process) {
	$detail = "$(Get-Name $scene) exit $($process.ExitCode) at launch; godot: $(if (Test-Path $godot) { $godot } else { "$godot not found" })"
	$output = Get-SceneOutput $scene
	$crash = $output | Where-Object { $_ -match '^CrashHandlerException: ' } | Select-Object -First 1
	if ($crash) {
		$frames = @($output | Where-Object { $_ -match '^\[[0-9]+\] ' } | ForEach-Object { $_ -replace '^\[[0-9]+\] [0-9a-fx]+ \(([^)]*)\).*', '$1' })
		$detail += "; crashed ($($crash -replace '^CrashHandlerException: ', '')) at $($frames[0]); backtrace: $($frames -join ' ')"
	}
	$noted = & python -B (Join-Path $root 'tools/heavy_job.py') note (Split-Path $root -Leaf) launch $detail 2>$null
	$note = if ($LASTEXITCODE -eq 0 -and $noted) { "$noted" } else { $detail }
	$note -replace '; backtrace:.*$', ''  # The whole one is in the gate's log.
}

# Stops a scene's process and the game it runs under it (the console build's child).
function Stop-Scene($process) {
	Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)" -ErrorAction SilentlyContinue |
		ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
	$process | Stop-Process -Force -ErrorAction SilentlyContinue
	$process.WaitForExit()
}

$jobs = if ($Serial) { 1 } else { Get-TestJobs $root }
$started = Get-Date
if (-not $Serial) { Write-Output "running $($scenes.Count) scenes, $jobs at once" }
$verdicts = @{}
$times = @()
$queue = New-Object Collections.Queue
$scenes | ForEach-Object { $queue.Enqueue($_) }
$running = @{}
$retried = @{}
$code = 1
Push-Location $root
try {
	while ($queue.Count -gt 0 -or $running.Count -gt 0) {
		while ($queue.Count -gt 0 -and $running.Count -lt $jobs) {
			$scene = $queue.Dequeue()
			$log = Join-Path $logs "$(Get-Name $scene).log"
			$process = Start-Process -FilePath $godot -ArgumentList '--headless', '--path', '.', '--scene', $scene `
				-RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err" -NoNewWindow -PassThru
			$null = $process.Handle  # Without it Windows PowerShell may lose the exit code.
			$running[$scene] = @{ Process = $process; Started = Get-Date }
			# Not all in the same instant (decision 530): two scenes died at launch
			# in a suite's first burst of nine Godots.
			Start-Sleep -Milliseconds 200
		}
		Start-Sleep -Milliseconds 200
		foreach ($scene in @($running.Keys)) {
			$entry = $running[$scene]
			$took = [int]((Get-Date) - $entry.Started).TotalSeconds
			$killed = $false
			if (-not $entry.Process.HasExited) {
				if ($took -lt $timeout) { continue }
				Stop-Scene $entry.Process
				$killed = $true
			}
			$entry.Process.WaitForExit()
			if (Test-LaunchFailed $scene $entry.Process $killed $took) {
				$note = Get-LaunchNote $scene $entry.Process
				if (-not $retried.ContainsKey($scene)) {
					# Noted with what the machine had, then run once more.
					$retried[$scene] = $note
					$running.Remove($scene)
					Start-Sleep -Seconds 2
					$queue.Enqueue($scene)
					continue
				}
				$retried[$scene] = "$($retried[$scene]); the retry too: $note"
			}
			$verdict = Get-Verdict $scene $entry.Process $killed $took
			if ($retried.ContainsKey($scene)) { $verdict += " (retried after a launch failure: $($retried[$scene]))" }
			$verdicts[$scene] = $verdict
			$times += "$took $scene"
			$running.Remove($scene)
			if ($Serial) {
				Write-Output "### $scene"
				Get-Content (Join-Path $logs "$(Get-Name $scene).log") | Write-Output
			} else {
				Write-Output $verdict
			}
		}
	}
	# The times, for the next run's order.
	$times | Sort-Object { [int]($_ -split ' ')[0] } -Descending | Set-Content $durations
	$failed = @($scenes | Where-Object { $verdicts[$_] -notmatch '^PASS' })
	if (-not $Serial) {
		foreach ($scene in $failed) {
			Write-Output ''
			Write-Output "### $scene (failed)"
			Get-Content (Join-Path $logs "$(Get-Name $scene).log") | Write-Output
		}
	}
	$seconds = [int]((Get-Date) - $started).TotalSeconds
	$again = if ($retried.Count -gt 0) { "; $($retried.Count) retried after a launch failure" } else { '' }
	Write-Output ''
	if ($failed.Count -eq 0) {
		Write-Output "SUITE: PASS ($($scenes.Count) scenes, $jobs at once, ${seconds}s$again)"
		$scenes | Where-Object { $retried.ContainsKey($_) } | ForEach-Object { $verdicts[$_] } | Write-Output
		$code = 0
	} else {
		Write-Output "SUITE: FAIL ($($failed.Count) of $($scenes.Count) failed: $(($failed | ForEach-Object { Get-Name $_ }) -join ' '); ${seconds}s$again)"
		$failed | ForEach-Object { $verdicts[$_] } | Write-Output
	}
} finally {
	foreach ($entry in $running.Values) { Stop-Scene $entry.Process }
	Pop-Location
	Remove-Item $logs -Recurse -Force -ErrorAction SilentlyContinue
}
exit $code
