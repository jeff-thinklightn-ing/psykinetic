# Ships a change: tests, commit, push, CHANGELOG section, release, and the
# server deploy. One command for the whole chain, so a change never sits at
# "committed" or "released but not on the box".
#   tools\ship.ps1 -Message "what changed"                  tests, commit, push, deploy
#   tools\ship.ps1 -Message "what changed" -Release 0.1.14  ...with CHANGELOG + release before the deploy
#   tools\ship.ps1 -Release 0.1.14                          nothing to commit; release and deploy
#   -SkipTests                                              when they just ran
#   -NoDeploy                                               leave the server alone
# The box is $env:PSYKINETIC_BOX (user@host for ssh), default jequig@100.78.120.114.
#
# Order of work:
#   1. refuse if project.godot carries run args (the editor writes the join
#      token there); refuse a version that CHANGELOG.md or a tag already has
#   2. run tests\run.ps1, tests\net_test.ps1, tests\state_test.ps1
#   3. with -Release: add "## v<version>" to the top of CHANGELOG.md with the
#      message as its one bullet, unless that section already exists
#   4. commit everything with the message (if there is anything), push
#   5. with -Release: tools\release_client.ps1 -Version <version>
#   6. ssh to the box: ~/psykinetic/server/deploy.sh (pull, export, install,
#      restart), output streamed; then admin.sh players to show it is up
param(
	[string]$Message = '',
	[string]$Release = '',
	[switch]$SkipTests,
	[switch]$NoDeploy
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Fail($text) {
	Write-Error $text
	exit 1
}
function Run($label, $block) {
	Write-Output "--- $label"
	& $block
	if ($LASTEXITCODE -ne 0) { Fail "$label failed" }
}

# --- 1. checks ----------------------------------------------------------------
$projectDiff = git diff HEAD -- project.godot
if ($projectDiff -match 'main_run_args') { Fail 'project.godot has run args (a token?); revert that line first' }
if ($Release -ne '') {
	if ($Release -notmatch '^\d+\.\d+\.\d+$') { Fail "release must be x.y.z, got '$Release'" }
	if (git tag -l "v$Release") { Fail "tag v$Release already exists" }
}
$dirty = @(git status --porcelain)
if ($dirty.Count -gt 0 -and $Message -eq '') { Fail 'there are changes to commit; give a -Message' }
if ($dirty.Count -eq 0 -and $Release -eq '') { Write-Output 'nothing to commit and no release asked for'; exit 0 }

# --- 2. tests -------------------------------------------------------------------
if (-not $SkipTests) {
	Run 'sim tests' { & "$root\tests\run.ps1" | Select-String 'RESULT|FAIL|ERROR' | ForEach-Object { $_.Line } }
	Run 'network test' { & "$root\tests\net_test.ps1" | Select-String 'RESULT|FAIL' | ForEach-Object { $_.Line } }
	Run 'state test' { & "$root\tests\state_test.ps1" | Select-String 'RESULT|FAIL' | ForEach-Object { $_.Line } }
}

# --- 3. changelog ---------------------------------------------------------------
if ($Release -ne '') {
	$changelog = Get-Content "$root\CHANGELOG.md" -Raw
	if ($changelog -notmatch "(?m)^## v$([regex]::Escape($Release))\s*$") {
		if ($Message -eq '') { Fail "CHANGELOG.md has no '## v$Release' section and there is no -Message to write one from" }
		$section = "## v$Release`n`n- $Message`n`n"
		$changelog = ([regex]'(?m)^## v').Replace($changelog, "$section## v", 1)
		[IO.File]::WriteAllText("$root\CHANGELOG.md", $changelog)
		Write-Output "CHANGELOG.md: added ## v$Release"
	}
}

# --- 4. commit and push -----------------------------------------------------------
# git reports on stderr; under 'Stop' a successful push would count as an
# error. Exit codes are checked instead from here on.
$ErrorActionPreference = 'Continue'
$dirty = @(git status --porcelain)
if ($dirty.Count -gt 0) {
	git add -A
	git commit -q -m $Message
	if ($LASTEXITCODE -ne 0) { Fail 'commit failed' }
	Write-Output "committed: $(git log --oneline -1)"
}
git push -q origin main
if ($LASTEXITCODE -ne 0) { Fail 'push failed' }
Write-Output 'pushed main'

# --- 5. release -------------------------------------------------------------------
if ($Release -ne '') {
	& "$root\tools\release_client.ps1" -Version $Release
	if ($LASTEXITCODE -ne 0) { Fail 'release failed' }
}

# --- 6. deploy --------------------------------------------------------------------
if ($NoDeploy) {
	Write-Output 'deploy skipped (-NoDeploy)'
	exit 0
}
$box = if ($env:PSYKINETIC_BOX) { $env:PSYKINETIC_BOX } else { 'jequig@100.78.120.114' }
Write-Output "--- deploying on $box"
# BatchMode: never hang on a password prompt. stderr merged so git's and
# systemctl's progress reads in order; the exit code decides.
ssh -o BatchMode=yes -o ConnectTimeout=15 $box '~/psykinetic/server/deploy.sh' 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Fail "deploy on $box failed (ssh exit $LASTEXITCODE)" }
Write-Output '--- server console: players'
# The admin port opens a moment after the restart.
$players = $null
foreach ($attempt in 1..5) {
	$players = ssh -o BatchMode=yes -o ConnectTimeout=15 $box '~/psykinetic/server/admin.sh players' 2>&1 | ForEach-Object { "$_" }
	if ($LASTEXITCODE -eq 0) { break }
	Start-Sleep -Seconds 2
}
if ($LASTEXITCODE -ne 0) { Fail "admin.sh players on $box failed after the deploy: $players" }
$players | Write-Output
Write-Output "deployed on $box"
