# Copies the sound takes that live outside the repo into the game (decision 268).
#   tools\sound_sync.ps1             copy what art/audio/takes.json lists, then reimport
#   tools\sound_sync.ps1 -Check      only say what is missing or changed; copy nothing
#   tools\sound_sync.ps1 -NoImport   copy, but leave Godot's import to the caller
#
# Takes of a source stored "external" in art/audio/slots.json (the Sonniss bundles, whose
# licence forbids sharing the files, so they can't be in this public repo) are kept in the
# sound library: <library>\takes\<slot>\<file>. The library is $env:PSYK_SOUND_DIR, else
# N:\assets\sound (the NAS). Each is copied to art\audio\external\<slot>\<file> (git ignores
# that folder) and checked against the sha256 takes.json gives it; a file there that
# takes.json no longer lists is removed. tools\release_client.ps1 runs this before it
# exports, so a release has every listed take or stops.
#
# Exit 0 when every listed take is in place (or none is listed: the library isn't needed
# then, and isn't looked for), 1 when the library can't be reached or a take is missing or
# differs (each named).
param(
	[switch]$Check,
	[switch]$NoImport,
	[string]$Library = $(if ($env:PSYK_SOUND_DIR) { $env:PSYK_SOUND_DIR } else { 'N:\assets\sound' }),
	# A network share that's down can keep Test-Path waiting for a minute or more.
	[int]$TimeoutSeconds = 10
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$external = Join-Path $root 'art\audio\external'

function Fail($message) {
	[Console]::Error.WriteLine("sound_sync: $message")
	exit 1
}

$manifest = Get-Content (Join-Path $root 'art\audio\slots.json') -Raw | ConvertFrom-Json
$list = Get-Content (Join-Path $root 'art\audio\takes.json') -Raw | ConvertFrom-Json

# The takes to copy: those whose source is stored external.
$wanted = @()
foreach ($slot in $list.takes.PSObject.Properties) {
	foreach ($take in $slot.Value) {
		$source = $manifest.sources.PSObject.Properties[[string]$take.from]
		if ($null -eq $source) { Fail "$($slot.Name): take $($take.file) is from '$($take.from)', which slots.json has no source for" }
		if ($source.Value.store -ne 'external') { continue }
		$wanted += [pscustomobject]@{ Slot = $slot.Name; File = [string]$take.file; Sha256 = ([string]$take.sha256).ToUpper() }
	}
}

$changed = $false
# A file in art\audio\external that no take names (with its .import) goes.
if (Test-Path $external) {
	$keep = @{}
	foreach ($take in $wanted) { $keep[(Join-Path (Join-Path $external $take.Slot) $take.File).ToLower()] = $true }
	foreach ($file in Get-ChildItem $external -Recurse -File) {
		$path = $file.FullName.ToLower()
		if ($path.EndsWith('.import')) { $path = $path.Substring(0, $path.Length - 7) }
		if (-not $keep.ContainsKey($path)) {
			if ($Check) { Write-Output "stale: $($file.FullName)" } else { Remove-Item $file.FullName; $changed = $true }
		}
	}
}

if ($wanted.Count -eq 0) {
	Write-Output 'sound_sync: no external takes listed; nothing to copy'
	exit 0
}

# Is the library there? Asked so that a share that's down can't hang this.
. (Join-Path $PSScriptRoot 'sound_library.ps1')
$reachable = Test-SoundLibrary (Join-Path $Library 'takes') $TimeoutSeconds
if ($reachable -eq 'timeout') {
	Fail "the sound library $Library did not answer within $TimeoutSeconds s. Is the NAS up and N: mapped? (PSYK_SOUND_DIR points at another copy.) $($wanted.Count) takes need it."
}
if ($reachable -ne 'yes') {
	Fail "no takes folder in the sound library $Library (PSYK_SOUND_DIR points at another copy). $($wanted.Count) takes need it."
}

$problems = @()
$copied = 0
foreach ($take in $wanted) {
	$from = Join-Path (Join-Path (Join-Path $Library 'takes') $take.Slot) $take.File
	$to = Join-Path (Join-Path $external $take.Slot) $take.File
	if (-not (Test-Path -LiteralPath $from)) {
		$problems += "missing: $from ($($take.Slot))"
		continue
	}
	$hash = (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash
	if ($hash -ne $take.Sha256) {
		$problems += "differs: $from has sha256 $hash, takes.json says $($take.Sha256)"
		continue
	}
	if ((Test-Path -LiteralPath $to) -and (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash -eq $hash) {
		continue
	}
	if ($Check) {
		Write-Output "to copy: $($take.Slot)/$($take.File)"
		continue
	}
	New-Item -ItemType Directory -Force (Split-Path $to -Parent) | Out-Null
	Copy-Item -LiteralPath $from -Destination $to -Force
	$copied += 1
	$changed = $true
}

if ($problems.Count -gt 0) {
	$problems | ForEach-Object { [Console]::Error.WriteLine("sound_sync: $_") }
	Fail "$($problems.Count) of $($wanted.Count) external takes are missing or differ"
}
Write-Output "sound_sync: $($wanted.Count) external takes in place ($copied copied) from $Library"

if ($changed -and -not $Check -and -not $NoImport) {
	$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
	if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
		$console = $godot -replace '\.exe$', '_console.exe'
		if (Test-Path $console) { $godot = $console }
	}
	$ErrorActionPreference = 'Continue'
	& $godot --headless --path $root --import 2>&1 | Out-Null
	$ErrorActionPreference = 'Stop'
	if ($LASTEXITCODE -ne 0) { Fail "Godot's import failed after copying (exit $LASTEXITCODE)" }
	Write-Output 'sound_sync: imported'
}
exit 0
