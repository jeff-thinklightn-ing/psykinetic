# Builds and publishes a Windows client release.
#   tools\release_client.ps1                 bumps the patch number in version.txt
#   tools\release_client.ps1 -Version 0.2.0  releases exactly that version
#
# Steps: write version.txt, commit it and tag v<version>; export the
# "Windows Client" preset to build\client\; add version.txt, launch.bat,
# update.ps1, settings.example.cfg and README.txt; zip it to
# build\psykinetic-client-v<version>.zip; then, if gh is installed, push the
# commit and tag and create the GitHub release with the top CHANGELOG.md
# section as notes. Nothing in the zip carries a token or address.
#
# Needs: a clean working tree, the Windows export templates installed for
# the Godot in $env:GODOT_PATH (or `godot` on PATH), and gh logged in to
# publish (without it the manual steps are printed).
param(
	[string]$Version = ''
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

if (git status --porcelain) {
	Write-Error 'the working tree is not clean; commit or stash first'
	exit 1
}

# --- version -----------------------------------------------------------------
$current = (Get-Content version.txt -Raw).Trim()
if ($Version -eq '') {
	$parts = $current.Split('.')
	if ($parts.Count -ne 3) { Write-Error "version.txt holds '$current', expected x.y.z"; exit 1 }
	$Version = '{0}.{1}.{2}' -f $parts[0], $parts[1], ([int]$parts[2] + 1)
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { Write-Error "version must be x.y.z, got '$Version'"; exit 1 }
$tag = "v$Version"
if (git tag -l $tag) { Write-Error "tag $tag already exists"; exit 1 }

Set-Content version.txt "$Version`n" -Encoding ascii -NoNewline
git add version.txt
git commit -q -m "Release $tag"
git tag $tag
Write-Output "version $current -> $Version, committed and tagged $tag"

# --- export ------------------------------------------------------------------
$out = Join-Path $root 'build\client'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null

& $godot --headless --path $root --export-release 'Windows Client' (Join-Path $out 'psykinetic.exe')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $out 'psykinetic.exe'))) {
	Write-Error 'export failed; are the Windows export templates installed?'
	exit 1
}
foreach ($name in 'launch.bat', 'update.ps1', 'settings.example.cfg', 'README.txt') {
	Copy-Item (Join-Path $root "client\$name") $out
}
Copy-Item (Join-Path $root 'version.txt') $out

# Nothing player-specific goes in the zip.
if (Test-Path (Join-Path $out 'settings.cfg')) { Remove-Item (Join-Path $out 'settings.cfg') }
$leak = Get-ChildItem $out -File -Include '*.bat', '*.ps1', '*.cfg', '*.txt' -Recurse |
	Select-String -Pattern '^token=(?!paste-the-token-here)' | Select-Object -First 1
if ($leak) { Write-Error "a token value is in $($leak.Filename); refusing to zip"; exit 1 }

$zip = Join-Path $root "build\psykinetic-client-$tag.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip
Write-Output "zipped $zip"

# --- release -----------------------------------------------------------------
# The top CHANGELOG.md section, without its heading.
$notes = New-TemporaryFile
$lines = Get-Content (Join-Path $root 'CHANGELOG.md')
$start = ($lines | Select-String -Pattern '^## ' | Select-Object -First 1).LineNumber
$end = ($lines | Select-String -Pattern '^## ' | Select-Object -Skip 1 -First 1).LineNumber
if (-not $start) { Set-Content $notes "Release $tag" }
elseif ($end) { $lines[$start..($end - 2)] | Set-Content $notes }
else { $lines[$start..($lines.Count - 1)] | Set-Content $notes }

if (Get-Command gh -ErrorAction SilentlyContinue) {
	git push
	git push origin $tag
	gh release create $tag $zip --title $tag --notes-file $notes
	Write-Output "released $tag"
} else {
	Write-Output ''
	Write-Output 'gh is not installed. To publish by hand:'
	Write-Output "  git push && git push origin $tag"
	Write-Output "  then on GitHub: Releases > Draft a new release > tag $tag, title $tag,"
	Write-Output "  attach $zip, and paste the notes from $notes"
}
Remove-Item $notes -ErrorAction SilentlyContinue
exit 0
