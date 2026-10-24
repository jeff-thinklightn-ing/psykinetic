# Screenshots of the 3D view for the terrain pass: a host on each map, the
# normal camera at a fixed yaw, a PNG each in -Out. Runs with APPDATA set to a
# temp folder of this checkout's own, so it reads the levels as committed and
# never writes the shared user:// folder; its own port (test offset) and
# settings file.
#   tools/terrain_shots.ps1 -Out <dir> [-Tag before] [-Maps castle,wilds,sample] [-Seconds 8] [-Yaw 0]
#     [-Extra "--test-move=4,5"]   more arguments for the game (e.g. walk somewhere first)
param(
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Tag = "shot",
	[string[]]$Maps = @("castle", "wilds", "sample"),
	[int]$Seconds = 8,
	[int]$Yaw = 0,
	[string[]]$Extra = @()
)
$ErrorActionPreference = "Stop"
if (-not $env:GODOT_PATH) { throw "GODOT_PATH is not set" }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot '..\tests\godot_log.ps1')  # Its logs in build/logs (decision 664).
. (Join-Path $root "tests/test_ports.ps1")
$offset = $portOffset
$checkout = Split-Path -Leaf $root
$appdata = Join-Path ([IO.Path]::GetTempPath()) "psykinetic-shots-$checkout"
New-Item -ItemType Directory -Force $appdata | Out-Null
New-Item -ItemType Directory -Force $Out | Out-Null
$settings = Join-Path $appdata "settings.cfg"
Set-Content -Encoding utf8 $settings "window_width=1600`nwindow_height=900`nwindow_mode=windowed`nhints=off"
$port = 7700 + $offset
foreach ($map in $Maps) {
	$png = Join-Path (Resolve-Path $Out) "$map-$Tag.png"
	$env:APPDATA = $appdata
	& $env:GODOT_PATH --log-file (Get-GodotLog "terrain_shots_$map") --path $root --host --map=$map --port=$port --no-companions `
		--settings=$settings --test-yaw=$Yaw --test-exit-after=$Seconds --screenshot=$png @Extra | Out-Null
	Write-Output $png
}
