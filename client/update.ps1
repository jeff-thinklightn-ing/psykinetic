# Psykinetic client updater. Run by launch.bat.
# Checks GitHub for a newer release, installs it over this folder (keeping
# settings.cfg), then starts the game. Anything that goes wrong is one line
# in update.log and the game starts anyway. Needs no admin rights: it only
# touches this folder and a temp file.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$log = Join-Path $dir 'update.log'
$exe = Join-Path $dir 'psykinetic.exe'
$repo = 'jeff-thinklightn-ing/psykinetic'

function Log($message) {
	"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message" | Add-Content $log
}

try {
	# Never replace files while the game has them open.
	$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
	if ($running) {
		Log 'game already running; not updating'
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
				# Everything in the zip replaces ours, except the player's settings.
				Get-ChildItem $stage -Recurse -File | ForEach-Object {
					$relative = $_.FullName.Substring($stage.Length).TrimStart('\', '/')
					if ($relative -ieq 'settings.cfg') { return }
					$target = Join-Path $dir $relative
					New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
					Copy-Item $_.FullName $target -Force
				}
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

if (Test-Path $exe) {
	Start-Process -FilePath $exe -WorkingDirectory $dir
} else {
	Log 'psykinetic.exe is missing; nothing to start'
}
