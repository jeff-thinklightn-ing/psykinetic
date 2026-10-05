# Network test: one headless --server and two headless --client instances on
# localhost. Each client orders its player to move; the server's log must show
# both players moving with a consistent occupancy map.
# Exit code 0 = all assertions passed, 1 = any failed.
# Godot is taken from $env:GODOT_PATH, or `godot` on PATH.
$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

$root = Split-Path $PSScriptRoot -Parent
$logs = Join-Path ([IO.Path]::GetTempPath()) 'psykinetic-net-test'
New-Item -ItemType Directory -Force $logs | Out-Null
Remove-Item (Join-Path $logs '*') -Force -ErrorAction SilentlyContinue
$port = 17777

function Start-Instance($name, $modeArgs) {
	$arguments = @('--headless', '--path', "`"$root`"") + $modeArgs + @("--port=$port")
	Start-Process -FilePath $godot -ArgumentList $arguments -NoNewWindow -PassThru `
		-RedirectStandardOutput (Join-Path $logs "$name.log") `
		-RedirectStandardError (Join-Path $logs "$name.err")
}

$server = Start-Instance 'server' @('--server', '--test-exit-after=12')
Start-Sleep -Seconds 2
$client1 = Start-Instance 'client1' @('--client', '--address=127.0.0.1', '--test-move=-2,0', '--test-exit-after=7')
$client2 = Start-Instance 'client2' @('--client', '--address=127.0.0.1', '--test-move=0,1', '--test-exit-after=8')

$all = @($server, $client1, $client2)
$all | Wait-Process -Timeout 40 -ErrorAction SilentlyContinue
$all | Where-Object { -not $_.HasExited } | Stop-Process -Force

function Read-Log($name) {
	$path = Join-Path $logs "$name.log"
	if (Test-Path $path) { @(Get-Content $path) } else { @() }
}
$serverLog = Read-Log 'server'
$client1Log = Read-Log 'client1'
$client2Log = Read-Log 'client2'

$script:failures = 0
function Assert($ok, $label) {
	if ($ok) { Write-Output "  PASS  $label" }
	else { Write-Output "  FAIL  $label"; $script:failures++ }
}

$joined = @($serverLog | Select-String '\[net\] peer \d+ joined as Player')
$movers = @($serverLog | Select-String '\[net\] (Player\d+) \(peer \d+\) moved' |
	ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
$inconsistent = @(($serverLog + $client1Log + $client2Log) | Select-String 'occupancy_consistent=false')

Assert ($joined.Count -eq 2) "server spawned a player for each client (saw $($joined.Count))"
Assert ($movers.Count -eq 2) "server log shows both players moved (saw: $($movers -join ', '))"
Assert (@($serverLog | Select-String 'rejected order').Count -eq 0) 'server rejected no orders'
Assert ($inconsistent.Count -eq 0) 'occupancy was consistent at every logged move, on server and clients'
Assert (@($serverLog | Select-String '\[test\] final .*occupancy_consistent=true').Count -eq 1) 'server occupancy consistent at exit'
Assert (@($client1Log | Select-String '\[test\] Player\d+ arrived').Count -eq 1) 'client 1 saw its own move replicated'
Assert (@($client2Log | Select-String '\[test\] Player\d+ arrived').Count -eq 1) 'client 2 saw its own move replicated'
$errors = @(Get-ChildItem $logs -Filter *.err | Where-Object { $_.Length -gt 0 } | ForEach-Object { $_.Name })
Assert ($errors.Count -eq 0) "no instance printed errors ($($errors -join ', '))"

Write-Output ''
if ($script:failures -gt 0) {
	Write-Output "--- server log ($logs) ---"
	$serverLog | Write-Output
	Write-Output "RESULT: FAIL ($($script:failures) failed)"
	exit 1
}
Write-Output "RESULT: PASS (logs in $logs)"
exit 0
