# Exports the Windows client to build\client\ and bundles a launch.bat with
# the server address and join token filled in. build\ is gitignored, so the
# token never enters the repo.
#   tests\export_client.ps1 -Address 100.64.0.5 -Token <the token>
# Needs the Windows export templates installed for the Godot in
# $env:GODOT_PATH (or `godot` on PATH).
param(
	[Parameter(Mandatory = $true)][string]$Address,
	[Parameter(Mandatory = $true)][string]$Token
)

$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root 'build\client'
New-Item -ItemType Directory -Force $out | Out-Null

& $godot --headless --path $root --export-release 'Windows Client' (Join-Path $out 'psykinetic.exe')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $out 'psykinetic.exe'))) {
	Write-Error 'export failed; are the Windows export templates installed?'
	exit 1
}

$launch = Get-Content (Join-Path $root 'client\launch.bat') -Raw
$launch = $launch.Replace('SERVER_ADDRESS', $Address).Replace('CHANGE_ME', $Token)
Set-Content (Join-Path $out 'launch.bat') $launch -Encoding ascii -NoNewline

Write-Output "client exported to $out"
Write-Output "launch.bat points at $Address; copy the folder to a player's machine and run it"
exit 0
