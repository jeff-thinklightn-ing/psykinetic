# Snapshot test: a host run pushes a crate and writes --state; a second run
# must load the crate where it was left; a corrupt file must start fresh.
# Exit code 0 = all assertions passed, 1 = any failed.
# Godot is taken from $env:GODOT_PATH, or `godot` on PATH.
$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path ([IO.Path]::GetTempPath()) 'psykinetic-state-test'
New-Item -ItemType Directory -Force $dir | Out-Null
Remove-Item (Join-Path $dir '*') -Force -ErrorAction SilentlyContinue
$state = Join-Path $dir 'world.json'

function Run-Host($name, $extra) {
	$arguments = @('--headless', '--path', "`"$root`"", '--host', '--port=17781', "--state=`"$state`"") + $extra
	$p = Start-Process -FilePath $godot -ArgumentList $arguments -NoNewWindow -PassThru -Wait `
		-RedirectStandardOutput (Join-Path $dir "$name.log") -RedirectStandardError (Join-Path $dir "$name.err")
	@(Get-Content (Join-Path $dir "$name.log"))
}

$script:failures = 0
function Assert($ok, $label) {
	if ($ok) { Write-Output "  PASS  $label" }
	else { Write-Output "  FAIL  $label"; $script:failures++ }
}

# 1. Fresh start: the host walks three tiles west, pushing Crate1 to (7, 2).
$first = Run-Host 'first' @('--test-move=-3,0', '--test-exit-after=5')
Assert (@($first | Select-String 'no snapshot at').Count -eq 1) 'first run finds no snapshot and starts fresh'
Assert (@($first | Select-String 'tiles: .*Crate1=\(7, 2\)').Count -eq 1) 'first run ends with Crate1 pushed to (7, 2)'
Assert (Test-Path $state) 'snapshot file was written'
$json = $null
try { $json = Get-Content $state -Raw | ConvertFrom-Json } catch {}
Assert ($null -ne $json -and $json.version -eq 1) 'snapshot is valid JSON with version 1'
$crate = @($json.entities | Where-Object { $_.name -eq 'Crate1' })
Assert ($crate.Count -eq 1 -and $crate[0].tile[0] -eq 7 -and $crate[0].tile[1] -eq 2) 'snapshot has Crate1 at [7, 2]'
Assert (@($json.entities | Where-Object { $_.type -eq 'player' }).Count -eq 0) 'snapshot holds no players'
Assert ($json.entities.Count -eq 9) "snapshot holds the 9 level entities (saw $($json.entities.Count))"

# 2. Restart: entities come from the snapshot, so Crate1 is still at (7, 2).
$second = Run-Host 'second' @('--test-exit-after=2')
Assert (@($second | Select-String '\[state\] loaded 9 entities').Count -eq 1) 'second run loads 9 entities from the snapshot'
Assert (@($second | Select-String 'tiles: .*Crate1=\(7, 2\)').Count -eq 1) 'second run has Crate1 where the first left it'

# 3. Corrupt file: start fresh, and overwrite it with a good one on exit.
Set-Content $state 'this is not json' -Encoding ascii
$third = Run-Host 'third' @('--test-exit-after=2')
Assert (@($third | Select-String 'does not parse.*starting fresh').Count -eq 1) 'a corrupt snapshot is logged and ignored'
Assert (@($third | Select-String 'tiles: .*Crate1=\(8, 2\)').Count -eq 1) 'and the room is generated fresh (Crate1 back at (8, 2))'
try { $json = Get-Content $state -Raw | ConvertFrom-Json } catch { $json = $null }
Assert ($null -ne $json) 'the corrupt file was replaced by a good snapshot on exit'
$errors = @(Get-ChildItem $dir -Filter *.err | Where-Object { $_.Length -gt 0 } | ForEach-Object { $_.Name })
Assert ($errors.Count -eq 0) "no run printed errors ($($errors -join ', '))"

Write-Output ''
if ($script:failures -gt 0) {
	Write-Output "RESULT: FAIL ($($script:failures) failed) (logs in $dir)"
	exit 1
}
Write-Output "RESULT: PASS (logs in $dir)"
exit 0
