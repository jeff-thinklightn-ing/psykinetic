# Deploys the dedicated server on the box, staged (decision 242), and asks
# nothing: for the coordinator after a release.
#   tools\deploy_box.ps1        compare protocols, then on the box: pull, export,
#                               stage the new build, and if it passes, the
#                               graceful restart (a 60 s countdown for players)
#   tools\deploy_box.ps1 -Now   the same without the countdown
# The box is $env:PSYKINETIC_BOX (user@host for ssh), default jequig@100.78.120.114.
#
# 1. Prints the box's running build and protocol beside origin/main's (what
#    the box will build), and whether the clients must update: another
#    protocol needs the client release published first, or the clients find
#    nothing newer to update to (decision 241). Then:
# 2. ssh: ~/psykinetic/server/deploy.sh --staged (server/stage.sh tries the
#    build on UDP 7787 before the live server is touched), output streamed
# 3. admin.sh version: what runs now
# Exits non-zero if staging or the deploy fails; the running server is then
# untouched (a failed stage) or restarted as it was.
param([switch]$Now)
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$box = if ($env:PSYKINETIC_BOX) { $env:PSYKINETIC_BOX } else { 'jequig@100.78.120.114' }
$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}
function Fail($text) {
	Write-Output "deploy_box: FAILED: $text"
	exit 1
}
$ssh = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', $box)

# --- 1. protocols -------------------------------------------------------------------
git -C $root fetch -q origin
$head = (git -C $root rev-parse HEAD).Trim()
$main = (git -C $root rev-parse origin/main).Trim()
$ours = & $godot --headless --path $root -- --print-protocol 2>$null | Select-String '^PROTOCOL' | Select-Object -First 1
$running = (ssh @ssh '~/psykinetic/server/admin.sh version' 2>&1 | ForEach-Object { "$_" }) -join ' '
Write-Output "box runs:     $running"
Write-Output "origin/main:  $(if ($ours) { $ours.Line -replace '^PROTOCOL ', '' } else { 'unknown (no --print-protocol)' })$(if ($head -ne $main) { ' (this checkout is not at origin/main; the box builds origin/main)' })"
if ($ours -and $running -match 'protocol ([0-9a-f]+)') {
	$theirs = $Matches[1]
	$new = ($ours.Line -split ' ')[-1]
	if ($theirs -eq $new) {
		Write-Output 'protocol: the same; players keep their build'
	} else {
		$version = (Get-Content (Join-Path $root 'version.txt') -Raw).Trim()
		$released = $false
		if (Get-Command gh -ErrorAction SilentlyContinue) {
			gh release view "v$version" -R jeff-thinklightn-ing/psykinetic *> $null
			$released = $LASTEXITCODE -eq 0
		}
		Write-Output "protocol: CHANGED; clients must update$(if ($released) { " (v$version is released: they will)" } else { " (v$version is not released yet: they will find nothing to update to)" })"
	}
} else {
	Write-Output 'protocol: cannot compare (the box is down or too old to say)'
}

# --- 2. deploy, staged ---------------------------------------------------------------
$flags = '--staged' + $(if ($Now) { ' --now' } else { '' })
Write-Output "--- deploying on $box ($flags)"
ssh @ssh "cd ~/psykinetic && git clean -f -- '*.uid' '*.import' && git pull --ff-only && ~/psykinetic/server/deploy.sh $flags" 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Fail "deploy.sh $flags on $box exited $LASTEXITCODE" }

# --- 3. what runs now ----------------------------------------------------------------
$after = $null
foreach ($attempt in 1..10) {
	$after = (ssh @ssh '~/psykinetic/server/admin.sh version' 2>&1 | ForEach-Object { "$_" }) -join ' '
	if ($LASTEXITCODE -eq 0 -and $after -match 'protocol') { break }
	Start-Sleep -Seconds 3
}
if ($after -notmatch 'protocol') { Fail "the server does not answer on its console after the deploy: $after" }
Write-Output "box runs now: $after"
