# Snapshot test: a host run pushes a crate and writes --state; a second run
# must load the crate where it was left; the bandaging kit taken from the
# chest, and put back, must stay where it was left across restarts; a
# corrupt file must start fresh.
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
$noStdin = Join-Path $dir 'stdin.empty'
Set-Content $noStdin '' -NoNewline

function Run-Host($name, $extra) {
	$arguments = @('--headless', '--path', "`"$root`"", '--host', '--no-companions', '--port=17781', "--state=`"$state`"") + $extra
	$p = Start-Process -FilePath $godot -ArgumentList $arguments -NoNewWindow -PassThru -Wait `
		-RedirectStandardInput $noStdin -RedirectStandardOutput (Join-Path $dir "$name.log") -RedirectStandardError (Join-Path $dir "$name.err")
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
Assert ($null -ne $json -and $json.version -eq 2 -and $null -ne $json.zones.test_room) 'snapshot is valid JSON, version 2, with the test room zone'
$room = $json.zones.test_room
$crate = @($room.entities | Where-Object { $_.name -eq 'Crate1' })
Assert ($crate.Count -eq 1 -and $crate[0].tile[0] -eq 7 -and $crate[0].tile[1] -eq 2) 'snapshot has Crate1 at [7, 2]'
Assert (@($room.entities | Where-Object { $_.script -eq 'res://sim/player.gd' }).Count -eq 0) 'players are not among the entities'
$dev = @($json.players | Where-Object { $_.player_id -eq 'dev-host' })
Assert ($json.players.Count -eq 1 -and $dev.Count -eq 1 -and $dev[0].tile[0] -eq 8 -and $dev[0].tile[1] -eq 2 -and $dev[0].zone -eq 'test_room') "snapshot holds the dev host's player record at [8, 2] in the test room"
Assert ($room.entities.Count -eq 10) "snapshot holds the 10 level entities (saw $($room.entities.Count))"

# 2. Restart: entities come from the snapshot, so Crate1 is still at (7, 2).
$second = Run-Host 'second' @('--test-exit-after=2')
Assert (@($second | Select-String '\[state\] loaded 10 entities and 1 player records').Count -eq 1) 'second run loads 10 entities and 1 player record from the snapshot'
Assert (@($second | Select-String '\[net\] Player \(dev-host\) joined as Player1 at \(8, 2\) \(back\)').Count -eq 1) 'the host comes back where it left off, as Player1'
Assert (@($second | Select-String 'tiles: .*Crate1=\(7, 2\)').Count -eq 1) 'second run has Crate1 where the first left it'
Assert (@($second | Select-String 'slots: Chest1=\[bandaging_kit\] Player1=\[\]$').Count -eq 1) 'the chest holds the bandaging kit, the host nothing'

# 2b. The host walks to the chest and drags the kit into their slots.
$take = Run-Host 'take' @('--test-chest=take', '--test-exit-after=5')
Assert (@($take | Select-String '\[test\] Player1 drags bandaging_kit from Chest1 0 to Player1 0').Count -eq 1) 'the host walks to the chest and drags the kit to their first slot'
Assert (@($take | Select-String 'slots: Player1 moved bandaging_kit from Chest1 0 to Player1 0').Count -eq 1) 'the server moves it'
Assert (@($take | Select-String 'slots: Chest1=\[\] Player1=\[bandaging_kit\]$').Count -eq 1) 'the chest is empty, the host holds the kit'
try { $json = Get-Content $state -Raw | ConvertFrom-Json } catch { $json = $null }
$chest = @($json.zones.test_room.entities | Where-Object { $_.name -eq 'Chest1' })
$dev = @($json.players | Where-Object { $_.player_id -eq 'dev-host' })
Assert ($chest.Count -eq 1 -and @($chest[0].slots | Where-Object { $_ -ne '' }).Count -eq 0 -and $dev.Count -eq 1 -and $dev[0].slots[0] -eq 'bandaging_kit') "the snapshot has the chest empty and the kit in the host's first slot"
$after = Run-Host 'after-take' @('--test-exit-after=2')
Assert (@($after | Select-String 'slots: Chest1=\[\] Player1=\[bandaging_kit\]$').Count -eq 1) 'after a restart the host still holds the kit and the chest is empty'

# 2c. And puts it back.
$put = Run-Host 'put' @('--test-chest=put', '--test-exit-after=4')
Assert (@($put | Select-String '\[test\] Player1 drags bandaging_kit from Player1 0 to Chest1 0').Count -eq 1) 'the host drags the kit back into the chest'
$after = Run-Host 'after-put' @('--test-exit-after=2')
Assert (@($after | Select-String 'slots: Chest1=\[bandaging_kit\] Player1=\[\]$').Count -eq 1) 'after a restart it is in the chest, the host holds nothing'

# 3. Corrupt file: start fresh, and overwrite it with a good one on exit.
Set-Content $state 'this is not json' -Encoding ascii
$third = Run-Host 'third' @('--test-exit-after=2')
Assert (@($third | Select-String 'does not parse.*starting fresh').Count -eq 1) 'a corrupt snapshot is logged and ignored'
Assert (@($third | Select-String 'tiles: .*Crate1=\(8, 2\)').Count -eq 1) 'and the room is generated fresh (Crate1 back at (8, 2))'
Assert (@($third | Select-String 'tiles: .*Player1=\(11, 2\)').Count -eq 1) 'with the host at a start tile'
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
