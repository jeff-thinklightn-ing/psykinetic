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
$token = 'test-secret'
$state = Join-Path $logs 'world.json'
# Fixed identities for the players whose return we check.
$idC = 'c0ffee00-0000-4000-8000-00000000000c'
$idD = 'd0d0d0d0-0000-4000-8000-00000000000d'

# Servers read console commands from stdin; give them a closed one.
$noStdin = Join-Path $logs 'stdin.empty'
Set-Content $noStdin '' -NoNewline

function Start-Instance($name, $modeArgs) {
	$arguments = @('--headless', '--path', "`"$root`"") + $modeArgs + @("--port=$port")
	Start-Process -FilePath $godot -ArgumentList $arguments -NoNewWindow -PassThru `
		-RedirectStandardInput $noStdin `
		-RedirectStandardOutput (Join-Path $logs "$name.log") `
		-RedirectStandardError (Join-Path $logs "$name.err")
}

$server = Start-Instance 'server' @('--server', '--no-companions', "--token=$token", "--state=`"$state`"", '--test-exit-after=16')
Start-Sleep -Seconds 2
$client1 = Start-Instance 'client1' @('--client', '--address=127.0.0.1', "--token=$token", '--test-move=-3,0', '--test-contest=9,1,70', '--test-exit-after=9')
# Client 1 joins first so it is Player1 at (11, 2); three tiles west is Crate1,
# so its move ends by pushing the crate to (7, 2). Client 2 joins after that
# to the start tile client 1 left and walks to (9, 2). Both are then one step
# from (9, 1), and at server tick
# 70 both order a move into it. Each client predicts the step; the server lets
# only one of them have the tile.
Start-Sleep -Seconds 1
$client2 = Start-Instance 'client2' @('--client', '--address=127.0.0.1', "--token=$token", '--test-move=-2,0', '--test-contest=9,1,70', '--test-exit-after=9')
# A third client with the wrong token must be rejected and never get a player.
Start-Sleep -Seconds 1
$client3 = Start-Instance 'client3' @('--client', '--address=127.0.0.1', '--token=wrong-secret', '--test-move=0,1', '--test-exit-after=4')
# A fourth joins with no mode argument, from a settings file like an exported client.
$settings = Join-Path $logs 'settings.cfg'
Set-Content $settings "address=127.0.0.1`nport=$port`ntoken=$token`nplayer_id=$idC`nname=Casey`n" -Encoding ascii
Start-Sleep -Seconds 1
$client4 = Start-Instance 'client4' @("--settings=`"$settings`"", '--test-move=0,1', '--test-exit-after=4')
# A fifth has the right token but claims another version: turned away as out of date.
$client5 = Start-Instance 'client5' @('--client', '--address=127.0.0.1', "--token=$token", '--test-version=0.0.1', '--test-exit-after=4')

# A sixth has the right token and version number but is a different build.
$client6 = Start-Instance 'client6' @('--client', '--address=127.0.0.1', "--token=$token", '--test-protocol=stale-build', '--test-exit-after=4')

$all = @($server, $client1, $client2, $client3, $client4, $client5, $client6)
$all | Wait-Process -Timeout 40 -ErrorAction SilentlyContinue
$all | Where-Object { -not $_.HasExited } | Stop-Process -Force

# Phase 2: the server restarts from its snapshot. Casey (client 4's id) must
# come back where she left, Dana is new, and a second Casey is turned away.
$server2 = Start-Instance 'server2' @('--server', '--no-companions', "--token=$token", "--state=`"$state`"", '--test-exit-after=10')
Start-Sleep -Seconds 2
$clientC = Start-Instance 'clientC' @("--settings=`"$settings`"", '--test-exit-after=6')
Start-Sleep -Seconds 1
$clientD = Start-Instance 'clientD' @('--client', '--address=127.0.0.1', "--token=$token", "--player-id=$idD", '--name=Dana', '--test-exit-after=4')
$clientE = Start-Instance 'clientE' @('--client', '--address=127.0.0.1', "--token=$token", "--player-id=$idC", '--name=Impostor', '--test-exit-after=3')
$phase2 = @($server2, $clientC, $clientD, $clientE)
$phase2 | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
$phase2 | Where-Object { -not $_.HasExited } | Stop-Process -Force

# Phase 3: Fay and Gus walk to opposite ends of the two-wide passage along
# the bottom of the room, then at tick 70 cross it toward each other.
$server3 = Start-Instance 'server3' @('--server', '--no-companions', "--token=$token", '--test-exit-after=15')
Start-Sleep -Seconds 2
$clientF = Start-Instance 'clientF' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Fay', '--test-move=-6,9', '--test-contest=12,12,70', '--test-exit-after=12')
Start-Sleep -Seconds 1
$clientG = Start-Instance 'clientG' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Gus', '--test-move=1,9', '--test-contest=5,12,70', '--test-exit-after=11')
$phase3 = @($server3, $clientF, $clientG)
$phase3 | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
$phase3 | Where-Object { -not $_.HasExited } | Stop-Process -Force

# Phase 4: any player may reset the room. Hal pushes Crate1 west as client 1
# did; at tick 70 Ivy asks for a reset, as her R key would.
$server4 = Start-Instance 'server4' @('--server', '--no-companions', "--token=$token", '--test-exit-after=13')
Start-Sleep -Seconds 2
$clientH = Start-Instance 'clientH' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Hal', '--test-move=-3,0', '--test-exit-after=10')
Start-Sleep -Seconds 1
$clientI = Start-Instance 'clientI' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Ivy', '--test-reset=70', '--test-exit-after=8')
$phase4 = @($server4, $clientH, $clientI)
$phase4 | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
$phase4 | Where-Object { -not $_.HasExited } | Stop-Process -Force

# Phase 5: zones. Jo walks onto the test room's link at (1, 1) and goes to
# the sample with her companion; Kim stays. Each client must be sent only
# its own zone's entities.
$server5 = Start-Instance 'server5' @('--server', "--token=$token", '--test-exit-after=16')
Start-Sleep -Seconds 2
$clientJ = Start-Instance 'clientJ' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Jo', '--test-move=-10,-1', '--test-exit-after=12')
Start-Sleep -Seconds 1
$clientK = Start-Instance 'clientK' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Kim', '--test-exit-after=11')
$phase5 = @($server5, $clientJ, $clientK)
$phase5 | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
$phase5 | Where-Object { -not $_.HasExited } | Stop-Process -Force

# Phase 6: the chest. Max joins first and does nothing; Lee joins second,
# walks to the chest and drags the bandaging kit into their slots. Both
# clients must show the chest empty and Lee holding the kit (Max leaves
# first, so Lee's last view has only Lee in it).
$server6 = Start-Instance 'server6' @('--server', '--no-companions', "--token=$token", '--test-exit-after=15')
Start-Sleep -Seconds 2
$clientM = Start-Instance 'clientM' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Max', '--test-exit-after=8')
Start-Sleep -Seconds 1
$clientL = Start-Instance 'clientL' @('--client', '--address=127.0.0.1', "--token=$token", '--name=Lee', '--test-chest=take', '--test-exit-after=10')
$phase6 = @($server6, $clientM, $clientL)
$phase6 | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
$phase6 | Where-Object { -not $_.HasExited } | Stop-Process -Force

function Read-Log($name) {
	$path = Join-Path $logs "$name.log"
	if (Test-Path $path) { @(Get-Content $path) } else { @() }
}
$serverLog = Read-Log 'server'
$client1Log = Read-Log 'client1'
$client2Log = Read-Log 'client2'
$client3Log = Read-Log 'client3'
$client4Log = Read-Log 'client4'
$client5Log = Read-Log 'client5'
$client6Log = Read-Log 'client6'
$server2Log = Read-Log 'server2'
$clientCLog = Read-Log 'clientC'
$clientDLog = Read-Log 'clientD'
$clientELog = Read-Log 'clientE'
$server3Log = Read-Log 'server3'
$clientFLog = Read-Log 'clientF'
$clientGLog = Read-Log 'clientG'
$server4Log = Read-Log 'server4'
$clientHLog = Read-Log 'clientH'
$clientILog = Read-Log 'clientI'
$server5Log = Read-Log 'server5'
$clientJLog = Read-Log 'clientJ'
$clientKLog = Read-Log 'clientK'
$server6Log = Read-Log 'server6'
$clientMLog = Read-Log 'clientM'
$clientLLog = Read-Log 'clientL'

$script:failures = 0
function Assert($ok, $label) {
	if ($ok) { Write-Output "  PASS  $label" }
	else { Write-Output "  FAIL  $label"; $script:failures++ }
}

$joined = @($serverLog | Select-String '\[net\] .+ \(\w+\) joined as Player')
$movers = @($serverLog | Select-String '\[net\] (Player[12]) \(peer \d+\) moved' |
	ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
$inconsistent = @(($serverLog + $client1Log + $client2Log) | Select-String 'occupancy_consistent=false')

Assert ($joined.Count -eq 3) "server spawned a player for each client with the right token and version (saw $($joined.Count))"
Assert (@($serverLog | Select-String '\[net\] peer \d+ authenticated').Count -eq 3) 'server authenticated the three good clients'
Assert (@($client4Log | Select-String '\[net\] using .*settings\.cfg').Count -eq 1 -and @($client4Log | Select-String '\[test\] Player\d+ arrived').Count -eq 1) 'a client with no arguments joins from settings.cfg and plays'
Assert (@($serverLog | Select-String '\[net\] rejected peer \d+ from \S+ \(client 0\.0\.1, server ').Count -eq 1) 'server rejected the out-of-date client, naming both versions'
Assert (@($client5Log | Select-String '\[net\] client out of date').Count -eq 1) 'the out-of-date client was told so'
Assert (@($serverLog | Select-String '\[net\] rejected peer \d+ from \S+ \(client protocol stale-build, server [0-9a-f]+\)').Count -eq 1) 'server rejected the same-version, different-build client'
Assert (@($client6Log | Select-String '\[net\] build mismatch: this client and the server are different builds').Count -eq 1 -and @($client6Log | Select-String '\[test\] Player').Count -eq 0) 'that client was told it is a build mismatch and never got a player'
$rejected = @($serverLog | Select-String '\[net\] rejected peer \d+ from \S+ \(wrong token\)')
Assert ($rejected.Count -eq 1) "server rejected the wrong-token client with its address (saw $($rejected.Count))"
Assert (@($client3Log | Select-String 'authentication failed').Count -eq 1) 'the wrong-token client reports authentication failed'
Assert (@($client3Log | Select-String '\[test\] Player').Count -eq 0) 'and never got a player to order around' 
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
Assert (@($clientLogs | Select-String 'mispredict: Player\d+ step into \(9, 1\) refused').Count -eq 1) 'the loser was told its step into (9, 1) was refused and re-planned'
Assert (@($serverLog | Select-String '\[net\] Casey \(c0ffee00\) joined as Player3 at ').Count -eq 1) 'phase 1: Casey joined as Player3'
Assert (@($serverLog | Select-String '\[net\] Casey \(c0ffee00\) left').Count -eq 1) 'phase 1: her leaving was logged with her name and id'
Assert (@($server2Log | Select-String '\[state\] loaded 10 entities and 3 player records').Count -eq 1) 'phase 2: the restarted server loads three player records'
$colorBefore = @($client4Log | Select-String 'display: Player3 .*color=([0-9a-f]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
$colorAfter = @($clientCLog | Select-String 'display: Player3 server_tile=\(11, 3\).*color=([0-9a-f]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
Assert ($colorBefore.Count -eq 1 -and $colorAfter.Count -eq 1 -and $colorAfter[0] -eq $colorBefore[0]) "phase 2: Casey is back on (11, 3) as Player3 in her colour (before $colorBefore, after $colorAfter)"
Assert (@($server2Log | Select-String '\[net\] Casey \(c0ffee00\) joined as Player3 at \(11, 3\) \(back\)').Count -eq 1) 'phase 2: the server says she joined back'
Assert (@($server2Log | Select-String '\[net\] Dana \(d0d0d0d0\) joined as Player4 at \(\d+, \d+\)$').Count -eq 1) 'phase 2: a new id gets a fresh spawn as Player4'
Assert (@($server2Log | Select-String '\[net\] rejected peer \d+ from \S+ \(already connected as c0ffee00\)').Count -eq 1) 'phase 2: a second connection with an online id is rejected'
Assert (@($clientELog | Select-String '\[net\] already connected').Count -eq 1) 'phase 2: and told so'
Assert (@($clientFLog | Select-String '\[test\] Player\d+ arrived') | Measure-Object).Count -eq 1 -and (@($clientGLog | Select-String '\[test\] Player\d+ arrived') | Measure-Object).Count -eq 1 -and $true 'phase 3: both reached their ends of the passage'
$fay = @($clientFLog | Select-String '\[test\] display: .*server_tile=\((\d+), (\d+)\).*snaps=(\d+)')
$gus = @($clientGLog | Select-String '\[test\] display: .*server_tile=\((\d+), (\d+)\).*snaps=(\d+)')
Assert ($fay.Count -eq 1 -and $fay[0].Line -match 'server_tile=\(12, 12\)') "phase 3: Fay crossed to (12, 12) ($($fay | ForEach-Object { $_.Line }))"
Assert ($gus.Count -eq 1 -and $gus[0].Line -match 'server_tile=\(5, 12\)') "phase 3: Gus crossed to (5, 12) ($($gus | ForEach-Object { $_.Line }))"
Assert ($fay.Count -eq 1 -and $gus.Count -eq 1 -and $fay[0].Matches[0].Groups[3].Value -eq '0' -and $gus[0].Matches[0].Groups[3].Value -eq '0') 'phase 3: neither client snapped more than 2 tiles'
Assert (@($server4Log | Select-String 'push: Player1 -> Crate1').Count -eq 1 -and @($server4Log | Select-String '\[world\] Ivy reset the room').Count -eq 1) "phase 4: Hal pushed the crate, then Ivy's reset reached the server"
Assert (@($server4Log | Select-String '\[net\] (Hal|Ivy) \([a-z0-9-]+\) joined as Player').Count -eq 4) 'phase 4: both players were put back into the rebuilt room'
# Hal stood on the crate's spawn tile, so he is put on the nearest free one.
Assert (@($clientILog | Select-String '\[test\] tiles: .*Crate1=\(8, 2\).*Player1=\(9, 2\) Player2=').Count -eq 1) 'phase 4: Ivy sees Crate1 back at (8, 2), Hal beside it and herself'
Assert (@($clientHLog | Select-String '\[test\] tiles: .*Crate1=\(8, 2\).*Player1=\(9, 2\)').Count -eq 1) 'phase 4: Hal, who did not ask, sees the same room'
Assert (@($server5Log | Select-String '\[zone\] Jo went from test_room to sample').Count -eq 1) 'phase 5: Jo took the link to the sample; the server says so'
Assert (@($clientJLog | Select-String '\[zone\] now in sample').Count -eq 1) 'phase 5: her client switched to the sample'
$joTiles = @($clientJLog | Select-String '\[test\] tiles: ')
$kimTiles = @($clientKLog | Select-String '\[test\] tiles: ')
Assert ($joTiles.Count -eq 1 -and $joTiles[0].Line -match 'Sneak=' -and $joTiles[0].Line -match 'Player1=' -and $joTiles[0].Line -match 'Pip=' -and $joTiles[0].Line -notmatch 'CorridorImp|Player2=|Nix=') "phase 5: Jo sees the sample, herself and her companion Pip, nothing of the test room ($($joTiles | ForEach-Object { $_.Line }))"
Assert ($kimTiles.Count -eq 1 -and $kimTiles[0].Line -match 'CorridorImp1=' -and $kimTiles[0].Line -match 'Player2=' -and $kimTiles[0].Line -match 'Nix=' -and $kimTiles[0].Line -notmatch 'Sneak=|Player1=|Pip=') "phase 5: Kim, who stayed, sees the test room and not Jo or Pip ($($kimTiles | ForEach-Object { $_.Line }))"
Assert (@($clientKLog | Select-String '\[zone\] now in').Count -eq 0) 'phase 5: and Kim never left it'
Assert (@($clientLLog | Select-String '\[test\] Player2 drags bandaging_kit from Chest1 0 to Player2 0').Count -eq 1) 'phase 6: Lee walks to the chest and drags the kit to their slots'
Assert (@($server6Log | Select-String 'slots: Player2 moved bandaging_kit from Chest1 0 to Player2 0').Count -eq 1) 'phase 6: the server moves it'
Assert (@($clientLLog | Select-String '\[test\] slots: Chest1=\[\] Player2=\[bandaging_kit\]$').Count -eq 1) 'phase 6: Lee sees the chest empty and the kit in their slots (Max has gone by then)'
Assert (@($clientMLog | Select-String '\[test\] slots: Chest1=\[\] Player1=\[\] Player2=\[bandaging_kit\]$').Count -eq 1) 'phase 6: Max, who did nothing, sees the same'
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
