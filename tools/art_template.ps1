# Makes a slot's Blender template to model over: art/kit/<category>/<slot>/<slot>.blend.
#   tools\art_template.ps1 door.single           (refuses if the .blend is there already)
#   tools\art_template.ps1 door.single -Force    (makes it again over the old one)
# It holds the slot's grey box as the game makes it: its size and origin, its moving parts as
# objects with their origins at the pivots (a door's "leaf"), its sockets, all in the shared
# "palette" material, flat-shaded, plus a wireframe "guide" collection with the slot's outline
# that exporting leaves out. Model over the boxes (or replace them), keeping the parts' names
# and origins; then tools\art_drop.ps1 <the .blend> exports and checks it. Blender is
# $env:BLENDER_PATH, else Steam's.
param(
	[Parameter(Mandatory = $true)][string]$Slot,
	[switch]$Force
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}
$blender = if ($env:BLENDER_PATH) { $env:BLENDER_PATH } else { 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' }
if (-not (Test-Path $blender)) { Write-Output "art_template: no Blender at $blender; set BLENDER_PATH"; exit 1 }

$manifest = Get-Content (Join-Path $root 'art\kit\slots.json') -Raw | ConvertFrom-Json
$entry = $manifest.slots.$Slot
if ($null -eq $entry) {
	foreach ($more in Get-ChildItem (Join-Path $root 'art\kit') -Filter 'slots_*.json') {
		$entry = (Get-Content $more.FullName -Raw | ConvertFrom-Json).slots.$Slot
		if ($null -ne $entry) { break }
	}
}
if ($null -eq $entry) { Write-Output "art_template: no slot '$Slot' in art/kit/slots.json"; exit 1 }
if ($entry.type -ne 'mesh') { Write-Output "art_template: $Slot is a $($entry.type) slot, not a model"; exit 1 }

$folder = Join-Path $root "art\kit\$($entry.category)\$Slot"
$blend = Join-Path $folder "$Slot.blend"
if ((Test-Path $blend) -and -not $Force) {
	Write-Output "art_template: $blend is there already; open it, or pass -Force to make the template again over it"
	exit 1
}
New-Item -ItemType Directory -Force $folder | Out-Null
$grey = Join-Path ([System.IO.Path]::GetTempPath()) "psykinetic-template-$Slot.glb"

# Godot and Blender write progress to stderr, which must not stop the script.
$ErrorActionPreference = 'Continue'
Push-Location $root
try {
	& $godot --headless --path . --script tools/art_template.gd -- $Slot $grey 2>&1 | ForEach-Object { "$_" } |
		Where-Object { "$_" -match '^art_template|SCRIPT ERROR|^ERROR' } | ForEach-Object { Write-Output "$_" }
} finally {
	Pop-Location
}
if (-not (Test-Path $grey)) { Write-Output "art_template: Godot did not write $grey"; exit 1 }

# The palette's grey stone swatch (row 1, column 3 of 8: #8f8f8a).
$size = @($entry.size | ForEach-Object { "$_" })
& $blender -b --python (Join-Path $PSScriptRoot 'blender\template_slot.py') -- $grey $blend (Join-Path $root 'art\kit\palette.png') `
	$Slot $size[0] $size[1] $size[2] $entry.kind 3 1 8 2>&1 | ForEach-Object { "$_" } |
	Where-Object { "$_" -match 'template|Error|error' } | ForEach-Object { Write-Output "blender: $_" }
Remove-Item $grey -ErrorAction SilentlyContinue
if (-not (Test-Path $blend)) { Write-Output "art_template: Blender did not write $blend"; exit 1 }
Write-Output "template: $blend"
Write-Output "  open it in Blender, model over the grey boxes (keep the parts' names and origins), save,"
Write-Output "  then: tools\art_drop.ps1 $blend"
Write-Output "  to watch it as the game will while you work: godot --path . tools/art_preview.tscn -- --slot=$Slot"
