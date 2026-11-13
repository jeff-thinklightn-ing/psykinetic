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
# PSYKINETIC_TREE, else the folder's name; a take under another name is still
# adopted by its process (394 amended (11)).
$tree = if ($env:PSYKINETIC_TREE) { $env:PSYKINETIC_TREE } else { Split-Path $root -Leaf }
$gate = Join-Path $root 'tools\heavy_job.py'
# The commit this run tests (decision 883, as tests/land.sh): a PASS stamps it only if
# HEAD is still here at the end; tools/hooks/pre-push wants the stamp for a push to main.
if (-not $env:LAND_HEAD) { $env:LAND_HEAD = (& git -C $root rev-parse HEAD 2>$null) }
if (-not $env:HEAVY_JOB_INSIDE) {
	# The CHANGELOG first, no Godot, before any wait at the gate (decision
	# 539): released sections as tagged, no bullet both unreleased and released.
	& python -B (Join-Path $root 'tools\changelog_check.py')
	if ($LASTEXITCODE -ne 0) {
		Write-Output "LANDING TESTS: FAIL (CHANGELOG.md, decision 539: fix it as above)"
		exit 1
	}
	# Every Godot the tooling starts writes its own log in build/logs, never
	# the shared user:// logs folder (decision 664).
	& python -B (Join-Path $root 'tools\godot_log_check.py')
	if ($LASTEXITCODE -ne 0) {
		Write-Output "LANDING TESTS: FAIL (a Godot launch without --log-file, decision 664: fix it as above)"
		exit 1
	}
	# docs/voice_inventory.md is generated: a changed player's line means
	# re-running its tool, never a hand edit (748 amended (6)). Under this
	# tree's land lock, clean and ahead of origin/main, a stale page is
	# regenerated as a commit of its own that goes out with the landing, its sha
	# named; elsewhere a stale page is a warning, said again before the result
	# line; a generator that fails stops the landing here (748 amended (8)).
	$inventoryOut = @(& python -B (Join-Path $root 'tools\voice_inventory.py') --land $tree --lock 'C:\dev\land.lock' 2>&1 | ForEach-Object { "$_" })
	$inventoryCode = $LASTEXITCODE
	$inventoryOut | Write-Output
	if ($inventoryCode -ne 0 -and $inventoryCode -ne 3) {
		Write-Output "LANDING TESTS: FAIL (voice inventory, 748 amended (8): the generator failed, exit $inventoryCode; run python -B tools/voice_inventory.py --check to see it)"
		exit 1
	}
	$inventoryStale = (@($inventoryOut | Where-Object { $_ -like 'VOICE INVENTORY*' }) -join "`n")
	# The commit these tests run, read once here, after the inventory's own commit and before
	# any part starts; the result line names it, or fails if it moved (278 amended (1), as
	# tools/land_tested.sh for tests/land.sh).
	function Tree-State { "$(& git rev-parse HEAD 2>$null) $((& git diff HEAD 2>$null | Out-String))".GetHashCode() }
	$tested = (& git rev-parse HEAD 2>$null)
	$stateBefore = Tree-State
	$dirtyBefore = (& git status --porcelain --untracked-files=no 2>$null | Out-String).Trim()
	Write-Output "landing tests: through the heavy-job gate as $tree suite (decision 394)"
	# The result line said again last, after the gate's own lines (its
	# memory table): a check reading the log's tail reads the result. No
	# result line written is a fail, whatever the exit (a killed run).
	$env:HEAVY_JOB_INSIDE = '1'
	$result = [IO.Path]::GetTempFileName()
	$env:LAND_RESULT = $result
	# While the tests run, a land lock this tree holds is beaten each minute (667
	# amended, as tests/land.sh does): its "since" moves to now. The job ends
	# with this script, or by itself once this process is gone.
	$lock = if ($env:PSYKINETIC_LAND_LOCK) { $env:PSYKINETIC_LAND_LOCK } else { 'C:\dev\land.lock' }  # As tools/land_lock.sh.
	$beater = Start-Job -ArgumentList $lock, $tree, $PID -ScriptBlock {
		param($lock, $tree, $parent)
		while (Get-Process -Id $parent -ErrorAction SilentlyContinue) {
			$owner = (Get-Content (Join-Path $lock 'owner') -ErrorAction SilentlyContinue | Select-Object -First 1)
			if ($owner -eq $tree) {
				$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
				try { [IO.File]::WriteAllText((Join-Path $lock 'since'), "$now`n") } catch {}  # Released meanwhile.
			}
			Start-Sleep -Seconds 60
		}
	}
	try {
		# Holding the land lock, never queue at the gate (394 amended (31), as tests/land.sh).
		& python $gate run $tree suite --no-queue-under-lock $lock -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
		$code = $LASTEXITCODE
	} finally {
		Stop-Job $beater -ErrorAction SilentlyContinue
		Remove-Job $beater -Force -ErrorAction SilentlyContinue
		Remove-Item Env:HEAVY_JOB_INSIDE -ErrorAction SilentlyContinue
		Remove-Item Env:LAND_RESULT -ErrorAction SilentlyContinue
	}
	$line = (Get-Content $result -ErrorAction SilentlyContinue | Select-Object -First 1)
	Remove-Item $result -ErrorAction SilentlyContinue
	if (-not $line -and $code -eq 6) { $line = "LANDING TESTS: FAIL (lost the gate take while holding the land lock: release the lock, take the gate, then the lock again; 394 amended (31))" }
	if (-not $line) { $line = "LANDING TESTS: FAIL (the gated run ended, exit $code, with no result)" }
	if ($line.StartsWith('LANDING TESTS: PASS') -and $tested) {
		if ((Tree-State) -ne $stateBefore) {
			$line = "LANDING TESTS: FAIL (the tree moved during the tests: $tested to $(& git rev-parse HEAD 2>$null), or its tracked files changed; 278 amended (1))"
		} elseif ($dirtyBefore) {
			$line = "$line tested $tested and uncommitted changes"
		} else {
			$line = "$line tested $tested"
		}
	}
	Write-Output ''
	if ($inventoryStale) { Write-Output $inventoryStale }
	Write-Output $line
	if ($line.StartsWith('LANDING TESTS: PASS')) { exit $code }
	if ($code -ne 0) { exit $code }
	exit 1
}
. (Join-Path $PSScriptRoot 'jobs.ps1')
$logs = Join-Path ([IO.Path]::GetTempPath()) ('psykinetic-land-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $logs | Out-Null

$suiteJobs = [Math]::Max(2, (Get-TestJobs $root) - 2)
# The gate ran it lean (394 amended (9), (10)): memory was short, fewer at
# once, and net_test after the suite, not beside it (state_test and
# server_boot_test beside it since 394 amended (19)).
$lean = "$env:HEAVY_JOB_KIND" -like 'suite_lean*'
if ($lean) { $suiteJobs = [Math]::Min($suiteJobs, 3) }
Write-Output "landing tests: the suite ($suiteJobs at once), net_test, state_test and server_boot_test together"
$started = Get-Date
$gateTest = & python -B (Join-Path $root 'tests\heavy_job_test.py') 2>&1
$gateOk = $LASTEXITCODE -eq 0
Write-Output "$(if ($gateOk) { 'PASS' } else { 'FAIL' })  heavy_job_test"
$changelogTest = & python -B (Join-Path $root 'tests\changelog_check_test.py') 2>&1
$changelogOk = $LASTEXITCODE -eq 0
Write-Output "$(if ($changelogOk) { 'PASS' } else { 'FAIL' })  changelog_check_test"
$resolveTest = & python -B (Join-Path $root 'tests\changelog_resolve_test.py') 2>&1
$resolveOk = $LASTEXITCODE -eq 0
Write-Output "$(if ($resolveOk) { 'PASS' } else { 'FAIL' })  changelog_resolve_test"
$inventoryTest = & python -B (Join-Path $root 'tests\voice_inventory_test.py') 2>&1
$inventoryOk = $LASTEXITCODE -eq 0
Write-Output "$(if ($inventoryOk) { 'PASS' } else { 'FAIL' })  voice_inventory_test"
# Each font's .fontdata before the Godot parts (278 amended (3)): one more import if one is
# missing; still missing, it fails naming the font.
Push-Location $root
$fontImport = & bash tools/fonts_imported.sh . 2>&1
$fontOk = $LASTEXITCODE -eq 0
Pop-Location
$fontImport | Where-Object { "$_" -like 're-imported: *' } | Write-Output
Write-Output "$(if ($fontOk) { 'PASS' } else { 'FAIL' })  font_import"
$parts =[ordered]@{ suite = 'run.ps1'; net_test = 'net_test.ps1'; state_test = 'state_test.ps1'; server_boot_test = 'server_boot_test.ps1' }
if ($lean) {
	# Lean (394 amended (19)): state_test and server_boot_test (a Godot or two
	# each) beside the suite, net_test (many) after it.
	$parts = [ordered]@{ state_test = 'state_test.ps1'; server_boot_test = 'server_boot_test.ps1'; suite = 'run.ps1'; net_test = 'net_test.ps1' }
}
$running = @{}
$env:PSYKINETIC_TEST_JOBS = "$suiteJobs"  # Only the suite reads it.
# A lean landing's net_test runs its groups one after another (394 amended (12)).
if ($lean) { $env:NET_TEST_SERIAL = '1' }
try {
	foreach ($name in $parts.Keys) {
		$process = Start-Process -FilePath 'powershell.exe' -NoNewWindow -PassThru `
			-ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $parts[$name]) `
			-RedirectStandardOutput (Join-Path $logs "$name.out") -RedirectStandardError (Join-Path $logs "$name.err")
		$null = $process.Handle  # Without it Windows PowerShell may lose the exit code.
		$running[$name] = @{ Process = $process; Started = Get-Date }
		if ($lean -and $name -eq 'suite') { $process.WaitForExit() }
		Start-Sleep -Milliseconds 300  # A little apart (decision 530), as the suite starts its scenes.
	}
} finally {
	Remove-Item Env:PSYKINETIC_TEST_JOBS -ErrorAction SilentlyContinue
	Remove-Item Env:NET_TEST_SERIAL -ErrorAction SilentlyContinue
}
$failed = @()
if (-not $gateOk) {
	$failed += 'heavy_job_test'
	$gateTest | Write-Output
}
if (-not $changelogOk) {
	$failed += 'changelog_check_test'
	$changelogTest | Write-Output
}
if (-not $inventoryOk) {
	$failed += 'voice_inventory_test'
	$inventoryTest | Write-Output
}
if (-not $resolveOk) {
	$failed += 'changelog_resolve_test'
	$resolveTest | Write-Output
}
if (-not $fontOk) {
	$failed += 'font_import'
	$fontImport | Write-Output
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
	$line = "LANDING TESTS: PASS (suite, net_test, state_test, server_boot_test, heavy_job_test, changelog_check_test, changelog_resolve_test, voice_inventory_test; ${seconds}s)"
} else {
	$line = "LANDING TESTS: FAIL ($($failed -join ', '); ${seconds}s)"
}
Write-Output $line
if ($failed.Count -eq 0) {
	# The PASS stamp (tools/land_stamp.sh's land_stamp_write, the same file).
	$head = (& git -C $root rev-parse HEAD 2>$null)
	if ($head -and $head -eq $env:LAND_HEAD) {
		$common = (& git -C $root rev-parse --path-format=absolute --git-common-dir 2>$null)
		$dir = Join-Path $common 'land_pass'
		New-Item -ItemType Directory -Force $dir | Out-Null
		Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | Remove-Item -Force -ErrorAction SilentlyContinue
		$text = "tree=$tree`ntime=$((Get-Date).ToString('s'))`nline=$line`n"
		[IO.File]::WriteAllText((Join-Path $dir "$head.tmp"), $text)
		Move-Item -Force (Join-Path $dir "$head.tmp") (Join-Path $dir $head)
		Write-Output "push stamp: $head may be pushed to main (tools/hooks/pre-push)"
	} else {
		Write-Output "push stamp: none: HEAD moved during the run ($($env:LAND_HEAD) to $head); run land.ps1 on the commit you push"
	}
}
if ($env:LAND_RESULT) { Set-Content -Path $env:LAND_RESULT -Value $line -Encoding utf8 }
if ($failed.Count -eq 0) { exit 0 }
exit 1
