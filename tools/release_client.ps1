# Builds and publishes a Windows client release.
#   tools\release_client.ps1                 bumps the patch number in version.txt
#   tools\release_client.ps1 -Version 0.2.0  releases exactly that version
#
# Order of work, so a missing tool never leaves a half-done release:
#   1. checks: Godot runs, the Windows export templates are installed, the
#      tree is clean, the tag is free            (nothing touched yet)
#   2. write version.txt, export the "Windows Client" preset to build\client\,
#      bundle launch.bat, update.ps1, settings.example.cfg, README.txt and
#      version.txt, zip to build\psykinetic-client-v<version>.zip
#      (a failure here puts version.txt back)
#   3. commit "Release v<version>" and tag it
#   4. with gh: push the commit and tag, create the GitHub release with the
#      top CHANGELOG.md section as notes; without gh: print the manual steps
# Nothing in the zip carries a token or address.
param(
	[string]$Version = ''
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Fail($message) {
	Write-Error $message
	exit 1
}

# --- 1. checks ----------------------------------------------------------------
$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}
if (-not (Get-Command $godot -ErrorAction SilentlyContinue)) {
	Fail "Godot not found at '$godot'. Set GODOT_PATH to the Godot 4.7.2 editor exe."
}
$godotVersion = (& $godot --version 2>$null | Select-Object -Last 1)
if (-not $godotVersion -or $godotVersion -notmatch '^(\d+\.\d+\.\d+\.[a-z0-9]+)') {
	Fail "could not read Godot's version from '$godot' (got '$godotVersion')"
}
$templateDir = Join-Path $env:APPDATA "Godot\export_templates\$($Matches[1])"
$template = Join-Path $templateDir 'windows_release_x86_64.exe'
if (-not (Test-Path $template)) {
	Fail "Windows export template missing: $template. In the editor: Editor > Manage Export Templates > Download."
}

if (git status --porcelain) {
	Fail 'the working tree is not clean; commit or stash first'
}
$current = (Get-Content version.txt -Raw).Trim()
if ($Version -eq '') {
	$parts = $current.Split('.')
	if ($parts.Count -ne 3) { Fail "version.txt holds '$current', expected x.y.z" }
	$Version = '{0}.{1}.{2}' -f $parts[0], $parts[1], ([int]$parts[2] + 1)
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { Fail "version must be x.y.z, got '$Version'" }
$tag = "v$Version"
if (git tag -l $tag) { Fail "tag $tag already exists" }
if (-not (Select-String -Path CHANGELOG.md -Pattern "^## $tag\b" -Quiet)) {
	Write-Warning "CHANGELOG.md has no '## $tag' section; the release notes will be the top section as it is"
}
Write-Output "Godot $godotVersion, templates in $templateDir, releasing $current -> $Version"

# --- 2. build -----------------------------------------------------------------
$out = Join-Path $root 'build\client'
$zip = Join-Path $root "build\psykinetic-client-$tag.zip"
Set-Content version.txt "$Version`n" -Encoding ascii -NoNewline
try {
	if (Test-Path $out) { Remove-Item $out -Recurse -Force }
	New-Item -ItemType Directory -Force $out | Out-Null

	# Godot reports warnings (a file's metadata, say) on stderr; under 'Stop'
	# the first one would end the release. The exit code and the exe decide.
	$ErrorActionPreference = 'Continue'
	& $godot --headless --path $root --export-release 'Windows Client' (Join-Path $out 'psykinetic.exe') 2>&1 |
		ForEach-Object { "$_" } | Where-Object { $_ -match 'ERROR|WARNING' } | Write-Output
	$exported = $LASTEXITCODE
	$ErrorActionPreference = 'Stop'
	if ($exported -ne 0 -or -not (Test-Path (Join-Path $out 'psykinetic.exe'))) {
		throw 'export failed'
	}
	foreach ($name in 'launch.bat', 'update.ps1', 'settings.example.cfg', 'README.txt') {
		Copy-Item (Join-Path $root "client\$name") $out
	}
	Copy-Item (Join-Path $root 'version.txt') $out

	# Nothing player-specific goes in the zip.
	if (Test-Path (Join-Path $out 'settings.cfg')) { Remove-Item (Join-Path $out 'settings.cfg') }
	$leak = Get-ChildItem $out -File -Include '*.bat', '*.ps1', '*.cfg', '*.txt' -Recurse |
		Select-String -Pattern '^token=(?!paste-the-token-here)' | Select-Object -First 1
	if ($leak) { throw "a token value is in $($leak.Filename); refusing to zip" }

	if (Test-Path $zip) { Remove-Item $zip }
	Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip
} catch {
	git checkout -- version.txt
	Fail "$($_.Exception.Message); version.txt restored, nothing committed"
}
Write-Output "zipped $zip"

# --- 3. commit and tag --------------------------------------------------------
git add version.txt
git commit -q -m "Release $tag"
git tag $tag
Write-Output "committed and tagged $tag"

# --- 4. release ---------------------------------------------------------------
# The top CHANGELOG.md section, without its heading.
$notes = New-TemporaryFile
$lines = Get-Content (Join-Path $root 'CHANGELOG.md')
$start = ($lines | Select-String -Pattern '^## ' | Select-Object -First 1).LineNumber
$end = ($lines | Select-String -Pattern '^## ' | Select-Object -Skip 1 -First 1).LineNumber
if (-not $start) { Set-Content $notes "Release $tag" }
elseif ($end) { $lines[$start..($end - 2)] | Set-Content $notes }
else { $lines[$start..($lines.Count - 1)] | Set-Content $notes }

if (Get-Command gh -ErrorAction SilentlyContinue) {
	# git and gh report progress on stderr; under 'Stop' that would abort a
	# push that succeeded. Only the exit codes matter here.
	$ErrorActionPreference = 'Continue'
	git push
	if ($LASTEXITCODE -ne 0) { Fail 'git push failed' }
	git push origin $tag
	if ($LASTEXITCODE -ne 0) { Fail "git push origin $tag failed" }
	gh release create $tag $zip --title $tag --notes-file $notes
	if ($LASTEXITCODE -ne 0) { Fail 'gh release create failed' }
	$ErrorActionPreference = 'Stop'
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
