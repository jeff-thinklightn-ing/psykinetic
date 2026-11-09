# The laptop runner's side of tools/remote_shot.sh (the coordinator's design,
# 2026-11-08): copied to the laptop and run there, by ssh (lock, unlock,
# import) or as a one-shot task in the logged-on user's session (run: a
# window needs a desktop, which an ssh session has not).
#   -Mode lock    take D:\psykinetic-runs\lock (stale after -StaleMin), or fail
#   -Mode unlock  let it go
#   -Mode import  godot --headless --import in the clone, within -TimeoutMin
#   -Mode run     the game with the args in <Dir>\args.txt (one a line) at once,
#                 on the laptop's screen in front of its other windows without
#                 taking focus (Jeff, 2026-11-09: "i want the visuals to show up
#                 on screen when the screen is on so i can see what being done"),
#                 1600x900 or the screen's size, silent, its user data in
#                 <Dir>\appdata, the display kept on; a tray icon stops it;
#                 stopped by its PID past -TimeoutMin; writes <Dir>\done.txt:
#                 "exit <n>", "timeout" or "stopped by user", and to
#                 <Dir>\out\runner.log the laptop's idle seconds at start and end
#                 and whether it was used during the run (a bench's timing then
#                 isn't clean). -Repeat N: the game N times in a row with the same
#                 user data (a player's next session: its caches saved by the
#                 last); pass n's log <Dir>\out\godot-n.log, the first <Dir>\godot.log.
param(
	[Parameter(Mandatory = $true)][ValidateSet("lock", "unlock", "import", "run")][string]$Mode,
	[string]$Dir = "",
	[string]$Root = "D:\psykinetic",
	[string]$Runs = "D:\psykinetic-runs",
	[int]$TimeoutMin = 10,
	[int]$StaleMin = 30,
	[int]$Repeat = 1,
	[string]$Godot = ""
)
$ErrorActionPreference = "Stop"
if ($Godot -eq "") {
	$Godot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
}
$lock = Join-Path $Runs "lock"

## The caller reads $process.Handle as it starts it: without that, ExitCode
## comes back empty once the process has gone (a PowerShell quirk).
## The process and what it started (a bench's second pass), by its PID: taskkill /T.
function Stop-Tree([System.Diagnostics.Process]$process) {
	& taskkill.exe /T /F /PID $process.Id 2>&1 | Out-Null
}

## The laptop's power at a moment, for runner.log (a slow run's why: on battery,
## a power scheme, or the GPU held in a low state after being unplugged).
function Power-State {
	$battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | ForEach-Object { "battery status $($_.BatteryStatus) (2 = on mains), $($_.EstimatedChargeRemaining)%" })
	$scheme = (& powercfg.exe /getactivescheme 2>$null) -replace '^.*\(', '('
	$gpu = try { (& nvidia-smi.exe --query-gpu=pstate,clocks.gr,clocks.mem,temperature.gpu,power.draw --format=csv,noheader 2>$null) -join "; " } catch { "no nvidia-smi" }
	return "$(if ($battery) { $battery -join '; ' } else { 'no battery' }); scheme $scheme; GPU pstate, clock, mem clock, C, W: $gpu"
}

function Wait-Stop([System.Diagnostics.Process]$process, [int]$minutes) {
	if ($process.WaitForExit($minutes * 60 * 1000)) {
		return "exit $($process.ExitCode)"
	}
	Stop-Tree $process
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
		Add-Type -AssemblyName System.Windows.Forms, System.Drawing
		Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Idle {
	[StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
	[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
	public static uint LastTick() {
		var info = new LASTINPUTINFO(); info.cbSize = (uint)Marshal.SizeOf(info);
		GetLastInputInfo(ref info);
		return info.dwTime;
	}
	public static double Seconds() { return ((uint)Environment.TickCount - LastTick()) / 1000.0; }
	[DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
	[DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
	// The display on (SC_MONITORPOWER, on: no input faked, so the idle seconds still say
	// only what Jeff did) and kept on while this thread asks (ES_CONTINUOUS |
	// ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED); Release() hands it back. No setting changed.
	public static void Hold() {
		SetThreadExecutionState(0x80000003u);
		PostMessage(new IntPtr(0xFFFF), 0x0112u, new IntPtr(0xF170), new IntPtr(-1));
	}
	public static void Release() { SetThreadExecutionState(0x80000000u); }
	[DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int cx, int cy, uint flags);
	// In front of every other window (HWND_TOPMOST), not moved, not sized, never activated:
	// no focus taken, so his keys never drive the game.
	public static bool Topmost(IntPtr window) { return SetWindowPos(window, new IntPtr(-1), 0, 0, 0, 0, 0x0001u | 0x0002u | 0x0010u); }
	[StructLayout(LayoutKind.Sequential)] struct THROTTLING { public uint Version; public uint ControlMask; public uint StateMask; }
	[DllImport("kernel32.dll")] static extern bool SetProcessInformation(IntPtr process, int infoClass, ref THROTTLING info, uint size);
	// A window without focus is a background process to Windows 11, run at its efficiency
	// speed (EcoQoS) with its timer requests ignored: this process opts out (ProcessPowerThrottling,
	// EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION, state off). For this process alone; no setting changed.
	public static bool FullSpeed(IntPtr process) {
		var info = new THROTTLING { Version = 1, ControlMask = 0x1u | 0x4u, StateMask = 0 };
		return SetProcessInformation(process, 4, ref info, (uint)Marshal.SizeOf(info));
	}
}
'@
		$deadline = (Get-Date).AddMinutes($TimeoutMin)
		$name = Split-Path -Leaf $Dir
		$log = Join-Path $Dir "out\runner.log"
		$appdata = Join-Path $Dir "appdata"
		New-Item -ItemType Directory -Force $appdata, (Join-Path $Dir "out") | Out-Null
		$env:APPDATA = $appdata  # Its own user:// (the laptop user's is never touched).
		# 1600x900, or the screen's size where it is smaller (atlas's may be).
		$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
		$width = [Math]::Min(1600, $screen.Width)
		$height = [Math]::Min(900, $screen.Height)
		$settings = Join-Path $appdata "settings.cfg"
		Set-Content -Encoding utf8 $settings "window_width=$width`nwindow_height=$height`nwindow_mode=windowed`nhints=off"
		$given = @(Get-Content (Join-Path $Dir "args.txt") | Where-Object { $_ -ne "" })
		# Engine flags first; the game's after its "--" (remote_shot.sh puts --bind=127.0.0.1 there).
		# A way for Jeff to stop it: the tray icon, clicked (left or right).
		$asked = @{ stop = $false }
		$icon = New-Object System.Windows.Forms.NotifyIcon
		$icon.Icon = [System.Drawing.SystemIcons]::Application
		$icon.Text = ("Psykinetic run " + $name + ": click to stop").Substring(0, [Math]::Min(63, ("Psykinetic run " + $name + ": click to stop").Length))
		$icon.add_MouseClick({ $asked.stop = $true })
		$icon.Visible = $true
		$icon.ShowBalloonTip(6000, "Psykinetic: a run on screen", "$name, a Claude session's run. Click the tray icon to stop it.", [System.Windows.Forms.ToolTipIcon]::Info)
		$powerBefore = Power-State
		$idleBefore = [Idle]::Seconds()
		$since = [Idle]::LastTick()
		[Idle]::Hold()
		$passes = @()
		$topped = $false
		$full = $false
		$result = ""
		for ($pass = 1; $pass -le $Repeat; $pass++) {
			$logFile = if ($pass -eq 1) { Join-Path $Dir "godot.log" } else { Join-Path $Dir "out\godot-$pass.log" }
			$engine = @("--audio-driver", "Dummy", "--position", "0,0", "--resolution", "${width}x${height}", "--path", $Root)
			$quoted = ($engine + @("--log-file", $logFile) + $given + @("--settings=$settings")) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
			$process = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru
			$null = $process.Handle
			$full = [Idle]::FullSpeed($process.Handle)
			$shown = $false
			$result = ""
			while (-not $process.HasExited) {
				[System.Windows.Forms.Application]::DoEvents()
				if (-not $shown) {
					$process.Refresh()
					if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
						$shown = [Idle]::Topmost($process.MainWindowHandle)
						$topped = $topped -or $shown
						# The window up and in front: a caller watching for it (to say it is on screen) sees this.
						if ($shown -and $pass -eq 1) { Set-Content (Join-Path $Dir "shown.txt") (Get-Date -Format "HH:mm:ss") }
					}
				}
				if ($asked.stop) {
					Stop-Tree $process
					$result = "stopped by user"
					break
				}
				if ((Get-Date) -ge $deadline) {
					Stop-Tree $process
					$result = "timeout"
					break
				}
				Start-Sleep -Milliseconds 200
			}
			if ($result -eq "") {
				$process.WaitForExit()
				$result = "exit $($process.ExitCode)"
			}
			$passes += "pass ${pass}: $result"
			if ($result -ne "exit 0") { break }
		}
		$used = [Idle]::LastTick() -ne $since
		$icon.Visible = $false
		$icon.Dispose()
		[Idle]::Release()
		Add-Content -Encoding utf8 $log @(
			"full speed: $full",
			"window: ${width}x${height}, in front: $topped",
			"idle at start: $([int]$idleBefore) s; at end: $([int][Idle]::Seconds()) s",
			"laptop used during the run: $(if ($used) { 'yes' } else { 'no' })",
			"passes: $($passes -join '; ')",
			"power at start: $powerBefore",
			"power at end: $(Power-State)",
			"result: $result")
		Set-Content $done $result
		exit 0
	}
}
