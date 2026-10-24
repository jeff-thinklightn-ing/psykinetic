# Puts a model or texture into its art slot and checks it.
#   tools\art_drop.ps1 C:\art\door.single.blend                the slot is the file's name
#   tools\art_drop.ps1 C:\art\my_door.glb -Slot door.single     or given
#   tools\art_drop.ps1 art\kit\doors\door.single\door.single.blend   already in place: export again and check
# A .blend is copied in and exported to <slot>.glb through Blender ($env:BLENDER_PATH, else
# Steam's Blender); a .glb or .png is copied in. Then Godot imports it and tools/art_check.gd
# checks it against the slot (art/kit/slots.json), naming anything to change, and
# tools/art_status.gd writes docs/art_status.md and THIRD_PARTY.md again. The game draws it
# from then on: it replaces the slot's fill or grey box.
param(
	[Parameter(Mandatory = $true)][string]$File,
	[string]$Slot = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot '..\tests\godot_log.ps1')  # Its logs in build/logs (decision 664).

$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}
$blender = if ($env:BLENDER_PATH) { $env:BLENDER_PATH } else { 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' }

$source = (Resolve-Path $File).Path
$extension = [System.IO.Path]::GetExtension($source).ToLower()
if ($extension -notin @('.blend', '.glb', '.png')) { throw "art_drop: $File is not a .blend, .glb or .png" }
if ($Slot -eq '') {
	# door.single.blend, or a variant door.single.2.glb
	$Slot = [System.IO.Path]::GetFileNameWithoutExtension($source) -replace '\.\d+$', ''
}
$variant = ''
if ([System.IO.Path]::GetFileNameWithoutExtension($source) -match '\.(\d+)$') { $variant = ".$($Matches[1])" }

$manifest = Get-Content (Join-Path $root 'art\kit\slots.json') -Raw | ConvertFrom-Json
$entry = $manifest.slots.$Slot
if ($null -eq $entry) {
	foreach ($more in Get-ChildItem (Join-Path $root 'art\kit') -Filter 'slots_*.json') {
		$entry = (Get-Content $more.FullName -Raw | ConvertFrom-Json).slots.$Slot
		if ($null -ne $entry) { break }
	}
}
if ($null -eq $entry) { throw "art_drop: no slot '$Slot' in art/kit/slots.json; name the file for its slot (door.single.blend) or pass -Slot" }

$folder = Join-Path $root "art\kit\$($entry.category)\$Slot"
New-Item -ItemType Directory -Force $folder | Out-Null
$target = Join-Path $folder "$Slot$variant$extension"
if ((Resolve-Path $source).Path -ne [System.IO.Path]::GetFullPath($target)) {
	Copy-Item $source $target -Force
	Write-Output "copied to $target"
}

# Blender and Godot write progress to stderr, which must not stop the script.
$ErrorActionPreference = 'Continue'
if ($extension -eq '.blend') {
	if (-not (Test-Path $blender)) { Write-Output "art_drop: no Blender at $blender; set BLENDER_PATH"; exit 1 }
	$glb = Join-Path $folder "$Slot$variant.glb"
	& $blender -b $target --python (Join-Path $PSScriptRoot 'blender\export_slot.py') -- $glb 2>&1 | ForEach-Object { "$_" } |
		Where-Object { "$_" -match 'exported|Error|error' } | ForEach-Object { Write-Output "blender: $_" }
	if (-not (Test-Path $glb)) { Write-Output "art_drop: Blender did not write $glb"; exit 1 }
	(Get-Item $glb).LastWriteTime = Get-Date
}

Push-Location $root
try {
	& $godot --log-file (Get-GodotLog 'art_drop_import') --headless --path . --import 2>&1 | Out-Null
	& $godot --log-file (Get-GodotLog 'art_check') --headless --path . --script tools/art_check.gd -- $Slot 2>&1 | ForEach-Object { "$_" } |
		Where-Object { "$_" -match '^(ok|error|warning|\d+ error)|: (error|warning):|SCRIPT ERROR|^ERROR' } | ForEach-Object { Write-Output "$_" }
	$checked = $LASTEXITCODE
	# What each slot is drawn from now: docs/art_status.md and THIRD_PARTY.md.
	& $godot --log-file (Get-GodotLog 'art_status') --headless --path . --script tools/art_status.gd 2>&1 | ForEach-Object { "$_" } |
		Where-Object { "$_" -match '^wrote|SCRIPT ERROR|^ERROR' } | ForEach-Object { Write-Output "$_" }
	exit $checked
} finally {
	Pop-Location
}
