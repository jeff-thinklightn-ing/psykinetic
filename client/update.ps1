# Psykinetic client updater. Run by launch.bat, and by the game itself when
# a newer server turns it away as out of date (decision 241).
# Checks GitHub for a newer release, installs it over this folder (keeping
# settings.cfg), then starts the game. Anything that goes wrong is one line
# in update.log and the game starts anyway. Needs no admin rights: it only
# touches this folder and a temp file.
# With -Stage <folder> (decision 430) the game has already fetched the
# server's release and unpacked it there: this only waits for the game to
# quit (30 s at most), copies that folder over this one (keeping
# settings.cfg), removes it and starts the game. -NoStart leaves the game
# unstarted (tests/self_update_test's dry run).
param([string]$Stage = '', [switch]$NoStart)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$log = Join-Path $dir 'update.log'
$exe = Join-Path $dir 'psykinetic.exe'
$repo = 'jeff-thinklightn-ing/psykinetic'

function Log($message) {
	"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message" | Add-Content $log
}

# Everything in $from replaces ours, except the player's settings.
function Install($from) {
	Get-ChildItem $from -Recurse -File | ForEach-Object {
		$relative = $_.FullName.Substring($from.Length).TrimStart('\', '/')
		if ($relative -ieq 'settings.cfg') { return }
		$target = Join-Path $dir $relative
		New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
		Copy-Item $_.FullName $target -Force
	}
}

# True once the game is not running, waiting $seconds at most.
function WaitForGame($seconds) {
	$deadline = (Get-Date).AddSeconds($seconds)
	do {
		$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
		if ($running) { Start-Sleep -Milliseconds 250 }
	} while ($running -and (Get-Date) -lt $deadline)
	return -not $running
}

try {
	# Never replace files while the game has them open. A game that found
	# itself out of date started this and is quitting (decision 241): wait
	# for it.
	if ($Stage -ne '') {
		$Stage = (Resolve-Path $Stage).Path
		try {
			if (-not (WaitForGame 30)) {
				Log 'game still running after 30 s; not installing the staged update'
			} elseif (-not (Test-Path (Join-Path $Stage 'psykinetic.exe'))) {
				Log "staged update $Stage has no psykinetic.exe; not installing it"
			} else {
				Install $Stage
				Log "installed the staged update from $Stage"
			}
		} finally {
			Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
		}
	} elseif (-not (WaitForGame 15)) {
		Log 'game still running after 15 s; not updating'
	} else {
		$current = (Get-Content (Join-Path $dir 'version.txt') -Raw).Trim()
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" `
			-Headers @{ 'User-Agent' = 'psykinetic-updater' } -TimeoutSec 15
		$latest = ($release.tag_name -replace '^v', '')
		if ([version]$latest -le [version]$current) {
			Log "up to date (v$current)"
		} else {
			$asset = $release.assets | Where-Object { $_.name -like 'psykinetic-client-*.zip' } | Select-Object -First 1
			if (-not $asset) { throw "release v$latest has no client zip" }
			$zip = Join-Path ([IO.Path]::GetTempPath()) "psykinetic-update-$latest.zip"
			$stage = Join-Path ([IO.Path]::GetTempPath()) "psykinetic-update-$latest"
			try {
				Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -TimeoutSec 300 `
					-Headers @{ 'User-Agent' = 'psykinetic-updater' }
				if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
				Expand-Archive -Path $zip -DestinationPath $stage -Force
				if (-not (Test-Path (Join-Path $stage 'psykinetic.exe'))) { throw 'downloaded zip has no psykinetic.exe' }
				Install $stage
				Log "updated v$current -> v$latest"
			} finally {
				Remove-Item $zip -Force -ErrorAction SilentlyContinue
				Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
			}
		}
	}
} catch {
	Log "update failed: $($_.Exception.Message)"
}

if ($NoStart) {
	Log 'not starting the game (-NoStart)'
} elseif (Test-Path $exe) {
	Start-Process -FilePath $exe -WorkingDirectory $dir
} else {
	Log 'psykinetic.exe is missing; nothing to start'
}
