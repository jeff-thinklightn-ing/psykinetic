# The laptop runner's side of tools/remote_shot.sh (the coordinator's design,
# 2026-11-08): copied to the laptop and run there, by ssh (lock, unlock,
# import) or as a one-shot task in the logged-on user's session (run: a
# window needs a desktop, which an ssh session has not).
#   -Mode lock    take D:\psykinetic-runs\lock (stale after -StaleMin), or fail
#   -Mode unlock  let it go
#   -Mode import  godot --headless --import in the clone, within -TimeoutMin
#   -Mode run     wait for the laptop to be idle (no input for -IdleMin; never
#                 over its user), then the game with the args in <Dir>\args.txt
#                 (one a line), silent, at a fixed place and size, its user data
#                 in <Dir>\appdata, stopped by its PID past -TimeoutMin; writes
#                 <Dir>\done.txt: "exit <n>", "timeout" or "laptop in use".
param(
	[Parameter(Mandatory = $true)][ValidateSet("lock", "unlock", "import", "run")][string]$Mode,
	[string]$Dir = "",
	[string]$Root = "D:\psykinetic",
	[string]$Runs = "D:\psykinetic-runs",
	[int]$TimeoutMin = 10,
	[int]$StaleMin = 30,
	[int]$IdleMin = 5,
	[string]$Godot = ""
)
$ErrorActionPreference = "Stop"
if ($Godot -eq "") {
	$Godot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
}
$lock = Join-Path $Runs "lock"

## The caller reads $process.Handle as it starts it: without that, ExitCode
## comes back empty once the process has gone (a PowerShell quirk).
function Wait-Stop([System.Diagnostics.Process]$process, [int]$minutes) {
	if ($process.WaitForExit($minutes * 60 * 1000)) {
		return "exit $($process.ExitCode)"
	}
	Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
	return "timeout"
}

switch ($Mode) {
	"lock" {
		New-Item -ItemType Directory -Force $Runs | Out-Null
		if (Test-Path $lock) {
			$age = (Get-Date) - (Get-Item $lock).CreationTime
			if ($age.TotalMinutes -lt $StaleMin) {
				Write-Output "held: $(Get-Content (Join-Path $lock 'by.txt') -ErrorAction SilentlyContinue)"
				exit 3
			}
			Remove-Item -Recurse -Force $lock
		}
		New-Item -ItemType Directory $lock | Out-Null  # Fails if another took it first.
		Set-Content (Join-Path $lock "by.txt") "$Dir $(Get-Date -Format s)"
		exit 0
	}
	"unlock" {
		if (Test-Path $lock) { Remove-Item -Recurse -Force $lock }
		exit 0
	}
	"import" {
		$console = $Godot -replace '\.exe$', '_console.exe'
		$out = Join-Path $Runs "import.log"
		$process = Start-Process -FilePath $console -ArgumentList @("--headless", "--audio-driver", "Dummy", "--path", $Root, "--import") `
			-NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
		$null = $process.Handle
		$result = Wait-Stop $process $TimeoutMin
		Write-Output "import $result"
		if ($result -ne "exit 0") { exit 1 }
		exit 0
	}
	"run" {
		$done = Join-Path $Dir "done.txt"
		Remove-Item -Force $done -ErrorAction SilentlyContinue
		Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Idle {
	[StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
	[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
	public static double Seconds() {
		var info = new LASTINPUTINFO(); info.cbSize = (uint)Marshal.SizeOf(info);
		GetLastInputInfo(ref info);
		return ((uint)Environment.TickCount - info.dwTime) / 1000.0;
	}
}
'@
		# Never over its user: idle IdleMin minutes first, looked at every minute, up to the timeout.
		$deadline = (Get-Date).AddMinutes($TimeoutMin)
		while ([Idle]::Seconds() -lt $IdleMin * 60) {
			if ((Get-Date) -ge $deadline) {
				Set-Content $done "laptop in use"
				exit 0
			}
			Start-Sleep -Seconds 60
		}
		$appdata = Join-Path $Dir "appdata"
		New-Item -ItemType Directory -Force $appdata, (Join-Path $Dir "out") | Out-Null
		$env:APPDATA = $appdata  # Its own user:// (the laptop user's is never touched).
		$settings = Join-Path $appdata "settings.cfg"
		Set-Content -Encoding utf8 $settings "window_width=1600`nwindow_height=900`nwindow_mode=windowed`nhints=off"
		$given = @(Get-Content (Join-Path $Dir "args.txt") | Where-Object { $_ -ne "" })
		# Engine flags first; the game's after its "--" (remote_shot.sh puts --bind=127.0.0.1 there).
		$engine = @("--audio-driver", "Dummy", "--position", "0,0", "--resolution", "1600x900", "--path", $Root,
			"--log-file", (Join-Path $Dir "godot.log"))
		$quoted = ($engine + $given + @("--settings=$settings")) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
		$process = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru
		$null = $process.Handle
		$left = [Math]::Max(1, [int][Math]::Ceiling(($deadline - (Get-Date)).TotalMinutes))
		Set-Content $done (Wait-Stop $process $left)
		exit 0
	}
}
