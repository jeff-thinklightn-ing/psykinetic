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

$server = Start-Instance 'server' @('--server', '--test-exit-after=16')
Start-Sleep -Seconds 2
$client1 = Start-Instance 'client1' @('--client', '--address=127.0.0.1', '--test-move=-3,0', '--test-contest=9,1,70', '--test-exit-after=9')
# Client 1 joins first so it is Player1 at (11, 2); three tiles west is Crate1,
# so its move ends by pushing the crate to (7, 2). Client 2 joins after that
# to the start tile client 1 left and walks to (9, 2). Both are then one step
# from (9, 1), and at server tick
# 70 both order a move into it. Each client predicts the step; the server lets
# only one of them have the tile.
Start-Sleep -Seconds 1
$client2 = Start-Instance 'client2' @('--client', '--address=127.0.0.1', '--test-move=-2,0', '--test-contest=9,1,70', '--test-exit-after=9')

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
$pushed = @($serverLog | Select-String 'push: Player1 -> Crate1').Count
Assert ($pushed -eq 1) 'server log shows Player1 pushing Crate1'
foreach ($entry in @(@('server', $serverLog), @('client 1', $client1Log), @('client 2 (joined after the push)', $client2Log))) {
	Assert (@($entry[1] | Select-String '\[test\] tiles: .*Crate1=\(7, 2\)').Count -eq 1) "$($entry[0]) has the pushed crate at (7, 2)"
}
$clientLogs = @($client1Log) + @($client2Log)
$contestMoves = @($serverLog | Select-String 'moved .* -> \(9, 1\)')
Assert ($contestMoves.Count -eq 1) "exactly one player took the contested tile (9, 1) on the server (saw $($contestMoves.Count))"
$display = @($clientLogs | Select-String '\[test\] display: ' | ForEach-Object { $_.Line })
$onServerTile = @($display | Where-Object { $_ -match 'server_tile=(\([^)]*\)) shown_tile=\1 ' })
Assert ($display.Count -eq 2 -and $onServerTile.Count -eq 2) "both clients end up showing their player on the server's tile"
$winner = @($display | Where-Object { $_ -match 'server_tile=\(9, 1\) .*mispredicts=0' })
$loser = @($display | Where-Object { $_ -notmatch 'server_tile=\(9, 1\)' -and $_ -match 'mispredicts=1' })
Assert ($winner.Count -eq 1) 'the winner is on (9, 1) with no mispredictions'
Assert ($loser.Count -eq 1) 'the loser is not on (9, 1) and counted exactly one misprediction'
Assert (@($clientLogs | Select-String 'mispredict: Player\d+ predicted \(9, 1\)').Count -eq 1) 'the loser had predicted (9, 1) before snapping back'
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
