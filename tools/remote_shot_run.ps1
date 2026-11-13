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
#                 Every process it starts is in a job object Windows ends with this
#                 runner (kill on close): nothing a run starts outlives it, however
#                 it ends (828 amended (4)).
#                 -Joined: first the game headless as a server bound to 127.0.0.1 on a
#                 free loopback port, its user data in <Dir>\server_appdata, its args
#                 <Dir>\server_args.txt, its log <Dir>\out\server.log; once it says it
#                 listens, its sockets are read and any past loopback stops the run;
#                 then each pass's game as --client of 127.0.0.1:<port>. runner.log's
#                 "joined:" and "server at end:" lines name both and how the server ended.
param(
	[Parameter(Mandatory = $true)][ValidateSet("lock", "unlock", "import", "run", "judge")][string]$Mode,
	[string]$Dir = "",
	[string]$Root = "D:\psykinetic",
	[string]$Runs = "D:\psykinetic-runs",
	[int]$TimeoutMin = 10,
	[int]$StaleMin = 30,
	[int]$Repeat = 1,
	[string]$Godot = "",
	[switch]$Joined
)
$ErrorActionPreference = "Stop"
# A run whose runner fails says so (828 amended (4)): the error and its line in done.txt,
# which remote_shot.sh prints ("run: runner error at line N: ..."), not a silent wait out.
trap {
	if ($Mode -eq "run" -and $Dir -ne "") {
		try { Set-Content (Join-Path $Dir "done.txt") "runner error at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" } catch {}
	}
	break
}
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

## A joined run's sockets judged (828 amended (4), the coordinator's ruling 2026-11-12): each
## entry @{owner = "client"|"server"|"other"; proto = "udp"|"tcp"; address; port}. Loopback
## (127.0.0.1, ::1, ::ffff:127.0.0.1) is always fine. Off loopback, exactly one is allowed:
## UDP, the client's own, on the unspecified address (:: or 0.0.0.0), on an ephemeral port
## (at or above $low), while the client is joining 127.0.0.1: its ENet connection out
## (ENetMultiplayerPeer.create_client takes no bind address; every player's client opens it).
## Anything else off loopback, a second such socket, a TCP listener, or that socket owned by
## another process: refused. @{ok; line ("SOCKETS: ..."); why}.
function Judge-Sockets([object[]]$sockets, [int]$low, [bool]$joiningLocal) {
	$parts = @()
	$why = @()
	$allowed = 0
	foreach ($s in $sockets) {
		$at = "$($s.address):$($s.port)/$($s.proto)"
		if ($s.address -match '^(127\.0\.0\.1|::1|::ffff:127\.0\.0\.1)$') {
			$parts += "$($s.owner) $at"
			continue
		}
		$enet = $s.owner -eq "client" -and $s.proto -eq "udp" -and ($s.address -eq "::" -or $s.address -eq "0.0.0.0") -and [int]$s.port -ge $low
		if ($enet -and $joiningLocal -and $allowed -eq 0) {
			$allowed += 1
			$parts += "client ENet $at (outgoing, allowed)"
		} elseif ($enet -and $joiningLocal) {
			$why += "a second client socket off loopback: $at"
		} elseif ($enet) {
			$why += "the client's socket off loopback, but it is not joining 127.0.0.1: $at"
		} else {
			$why += "$($s.owner) socket off loopback: $at"
		}
	}
	$line = "SOCKETS: $(if ($parts) { ($parts | Select-Object -Unique) -join '; ' } else { 'none read' })"
	if ($why) { $line += "; REFUSED: $($why -join '; ')" }
	return @{ ok = ($why.Count -eq 0); line = $line; why = ($why -join '; ') }
}

## The sockets of a joined run's processes: the client, the server and anything either
## started since $since (a parent walk filtered by start time, so a reused PID is not
## followed). UDP endpoints and TCP listeners, each @{owner; proto; address; port}.
function Read-RunSockets([int]$clientPid, [int]$serverPid, [datetime]$since) {
	$owners = @{}
	if ($clientPid) { $owners[$clientPid] = "client" }
	if ($serverPid) { $owners[$serverPid] = "server" }
	$all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId, CreationDate)
	$grew = $true
	while ($grew) {
		$grew = $false
		foreach ($p in $all) {
			if (-not $owners.ContainsKey([int]$p.ProcessId) -and $owners.ContainsKey([int]$p.ParentProcessId) -and $p.CreationDate -ge $since) {
				$owners[[int]$p.ProcessId] = "other"
				$grew = $true
			}
		}
	}
	$pids = [uint32[]]@($owners.Keys)
	$found = @()
	$found += @(Get-NetUDPEndpoint -OwningProcess $pids -ErrorAction SilentlyContinue | ForEach-Object {
		@{ owner = $owners[[int]$_.OwningProcess]; proto = "udp"; address = "$($_.LocalAddress)"; port = [int]$_.LocalPort } })
	$found += @(Get-NetTCPConnection -OwningProcess $pids -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
		@{ owner = $owners[[int]$_.OwningProcess]; proto = "tcp"; address = "$($_.LocalAddress)"; port = [int]$_.LocalPort } })
	return ,$found
}

switch ($Mode) {
	# The judgement alone, for tests/remote_shot_sockets_test.sh: -Dir names a JSON file
	# {"low": n, "joining_local": bool, "sockets": [{owner, proto, address, port}]}.
	"judge" {
		$case = Get-Content -Raw $Dir | ConvertFrom-Json
		$verdict = Judge-Sockets @($case.sockets) ([int]$case.low) ([bool]$case.joining_local)
		Write-Output "$(if ($verdict.ok) { 'OK' } else { 'STOP' }) $($verdict.line)"
		exit 0
	}
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
// 828 amended (4): the run's processes in one job object, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE.
// Its handle is held by this runner alone and never closed by it: Windows closes it when
// the runner ends, however it ends, and ends every process still in the job then. A
// process a job member starts is in the job too (the server a scene might start).
public static class Job {
	[StructLayout(LayoutKind.Sequential)] struct BASIC {
		public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
		public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
		public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass; }
	[StructLayout(LayoutKind.Sequential)] struct IO {
		public ulong ReadOperationCount; public ulong WriteOperationCount; public ulong OtherOperationCount;
		public ulong ReadTransferCount; public ulong WriteTransferCount; public ulong OtherTransferCount; }
	[StructLayout(LayoutKind.Sequential)] struct EXTENDED {
		public BASIC Basic; public IO Io; public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit;
		public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed; }
	[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
	[DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref EXTENDED info, uint size);
	[DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
	static IntPtr handle = IntPtr.Zero;
	// 0 made, else the Windows error.
	public static int Make() {
		handle = CreateJobObject(IntPtr.Zero, null);
		if (handle == IntPtr.Zero) return Marshal.GetLastWin32Error();
		var info = new EXTENDED();
		info.Basic.LimitFlags = 0x2000u;  // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
		if (!SetInformationJobObject(handle, 9, ref info, (uint)Marshal.SizeOf(info))) return Marshal.GetLastWin32Error();
		return 0;
	}
	// 0 in the job, else the Windows error (-1: no job made).
	public static int Add(IntPtr process) {
		if (handle == IntPtr.Zero) return -1;
		return AssignProcessToJobObject(handle, process) ? 0 : Marshal.GetLastWin32Error();
	}
}
// 828 amended (4): a firewall prompt on the laptop's screen, found by its title among the
// visible top-level windows of this session. Read only: nothing is clicked or closed.
public static class Dialogs {
	delegate bool EnumProc(IntPtr window, IntPtr data);
	[DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr data);
	[DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int most);
	// How many visible windows bear the title, or -1 when the windows could not be listed.
	public static int Count(string title) {
		int count = 0;
		bool listed = EnumWindows((window, data) => {
			if (!IsWindowVisible(window)) return true;
			var text = new System.Text.StringBuilder(256);
			GetWindowText(window, text, 256);
			if (text.ToString() == title) count++;
			return true;
		}, IntPtr.Zero);
		return listed ? count : -1;
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
		# Or <Dir>\stop.txt, made by the caller over ssh: the same stop as the click (a proof of
		# the tray's path without moving the laptop's mouse; 828 amended (4)).
		$stopFile = Join-Path $Dir "stop.txt"
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
		# 828 amended (4): every process of the run in a job that ends with this runner.
		$jobMade = [Job]::Make()
		$jobbed = @()
		$joinedLines = @()
		$server = $null
		$port = 0
		$clientArgs = @()
		# A Windows firewall prompt ("Windows Security Alert"; an English Windows' title) on the
		# screen: never clicked, it is Jeff's. Said at the start of every run; a joined run
		# with one showing runs nothing, and one appearing during it stops it.
		$firewallTitle = "Windows Security Alert"
		$firewallAtStart = try { [Dialogs]::Count($firewallTitle) } catch { -1 }
		$firewallLine = "firewall dialog at start: $(switch ($firewallAtStart) { -1 { 'not checked (the windows could not be listed)' } 0 { 'none showing' } default { "SHOWING ($firewallAtStart)" } })"
		if ($Joined -and $firewallAtStart -gt 0) { $result = "a firewall dialog is showing: not started (it is Jeff's, not clicked)" }
		if ($Joined -and $result -eq "") {
			# A free loopback UDP port (ENet's), asked of Windows; the server binds it at once.
			$probe = New-Object System.Net.Sockets.UdpClient (New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Loopback, 0))
			$port = $probe.Client.LocalEndPoint.Port
			$probe.Close()
			$serverData = Join-Path $Dir "server_appdata"
			New-Item -ItemType Directory -Force $serverData | Out-Null
			$serverLog = Join-Path $Dir "out\server.log"
			$serverGiven = @(Get-Content (Join-Path $Dir "server_args.txt") -ErrorAction SilentlyContinue | Where-Object { $_ -ne "" })
			# A --server refuses to run open; this run's own token, made here and thrown away with
			# the run: in this runner's environment, which the server and each client inherit, never
			# on argv (decision 690: any local process reads a command line), in a file or a log.
			$env:PSYKINETIC_TOKEN = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
			# Its own user data, a fresh world: no state file, nothing of the box's, no player's id.
			# (The args just above the launch: tools/godot_log_check.py reads 3 lines around it.)
			$serverArgs = @("--headless", "--audio-driver", "Dummy", "--path", $Root, "--log-file", $serverLog, "--",
				"--server", "--bind=127.0.0.1", "--port=$port") + $serverGiven
			$env:APPDATA = $serverData
			$server = Start-Process -FilePath $Godot -ArgumentList $serverArgs -PassThru -WindowStyle Hidden
			$env:APPDATA = $appdata
			$null = $server.Handle
			$jobbed += "server pid $($server.Id): $(if (($code = [Job]::Add($server.Handle)) -eq 0) { 'in' } else { "not in (error $code)" })"
			$serverStart = Get-Date
			$listening = $false
			while (-not $listening) {
				[System.Windows.Forms.Application]::DoEvents(); if (Test-Path $stopFile) { $asked.stop = $true }
				if ($asked.stop) { $result = "stopped by user"; break }
				if ($server.HasExited) { $result = "server exited $($server.ExitCode) before it listened"; break }
				if (((Get-Date) - $serverStart).TotalSeconds -gt 90) { $result = "server never listened (90 s)"; break }
				# (The log is open in Godot as it writes: a read it refuses is tried again.)
				$listening = try { (Test-Path $serverLog) -and [bool](Select-String -Path $serverLog -SimpleMatch "[net] server listening on port $port" -Quiet) } catch { $false }
				if (-not $listening) { Start-Sleep -Milliseconds 250 }
			}
			$after = [int]((Get-Date) - $serverStart).TotalSeconds
			$joinedLines += "joined: server pid $($server.Id) on 127.0.0.1:$port, args: $($serverGiven -join ' '), $(if ($listening) { "listening after $after s" } else { "not listening after $after s" })"
			if ($listening) {
				# The coordinator's rule checked, not trusted: every socket the server holds is on loopback.
				try {
					$ends = @(Get-NetUDPEndpoint -OwningProcess $server.Id -ErrorAction Stop | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)/udp" })
					$ends += @(try { Get-NetTCPConnection -OwningProcess $server.Id -State Listen -ErrorAction Stop | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)/tcp" } } catch { @() })
					# Loopback: 127.0.0.1, ::1, or 127.0.0.1 mapped into a dual-stack socket (::ffff:127.0.0.1).
					$wide = @($ends | Where-Object { $_ -notmatch '^(127\.0\.0\.1|::1|::ffff:127\.0\.0\.1):' })
					$joinedLines += "joined: server sockets: $(if ($ends) { $ends -join ', ' } else { 'none read' })"
					if ($wide) { $result = "server listened beyond loopback: stopped ($($wide -join ', '))" }
					elseif (-not $ends) { $result = "server sockets not found: stopped" }
				} catch {
					$joinedLines += "joined: server sockets could not be read: $($_.Exception.Message)"
					$result = "server sockets could not be read: stopped"
				}
			}
			$clientArgs = @("--client", "--address=127.0.0.1", "--port=$port")
		}
		# A joined run whose server didn't come up (or was stopped) runs no game.
		$blocked = $result -ne ""
		# The joined socket check's state: the first ephemeral port (Windows' own range), the
		# run's start (for the process walk), the fullest line seen, how many looks.
		$runStart = (Get-Date).AddMinutes(-$TimeoutMin - 5)
		if ($server -ne $null) { $runStart = $server.StartTime.AddSeconds(-1) }
		$low = try { [int](Get-NetUDPSetting -ErrorAction Stop).DynamicPortRangeStartPort } catch { 49152 }
		$socketLine = ""
		$socketLooks = 0
		$firewallUnread = $false
		for ($pass = 1; $pass -le $Repeat -and -not $blocked; $pass++) {
			$logFile = if ($pass -eq 1) { Join-Path $Dir "godot.log" } else { Join-Path $Dir "out\godot-$pass.log" }
			$engine = @("--audio-driver", "Dummy", "--position", "0,0", "--resolution", "${width}x${height}", "--path", $Root)
			$quoted = ($engine + @("--log-file", $logFile) + $given + $clientArgs + @("--settings=$settings")) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
			$process = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru
			$null = $process.Handle
			$jobbed += "pass $pass's game pid $($process.Id): $(if (($code = [Job]::Add($process.Handle)) -eq 0) { 'in' } else { "not in (error $code)" })"
			$full = [Idle]::FullSpeed($process.Handle)
			$shown = $false
			$result = ""
			$clientStart = Get-Date
			$nextLook = $clientStart
			while (-not $process.HasExited) {
				[System.Windows.Forms.Application]::DoEvents(); if (Test-Path $stopFile) { $asked.stop = $true }
				# Joined: the run's sockets judged every 2 s for the first 30 s, then every 10 s,
				# and the screen looked at for a firewall prompt each time; either stops the run.
				if ($Joined -and (Get-Date) -ge $nextLook) {
					$age = ((Get-Date) - $clientStart).TotalSeconds
					$nextLook = (Get-Date).AddSeconds($(if ($age -lt 30) { 2 } else { 10 }))
					$joiningLocal = try { (Test-Path $logFile) -and [bool](Select-String -Path $logFile -SimpleMatch "[net] client connecting to 127.0.0.1:$port" -Quiet) } catch { $false }
					try {
						$verdict = Judge-Sockets (Read-RunSockets $process.Id $server.Id $runStart) $low $joiningLocal
						$socketLooks += 1
						if ($verdict.line.Length -ge $socketLine.Length) { $socketLine = $verdict.line }
						if (-not $verdict.ok) {
							$socketLine = $verdict.line
							Stop-Tree $process
							$result = "a socket off loopback refused: stopped ($($verdict.why))"
							break
						}
					} catch {
						$socketLine = "SOCKETS: could not be read ($($_.Exception.Message))"
						Stop-Tree $process
						$result = "sockets could not be read: stopped"
						break
					}
					$dialogs = try { [Dialogs]::Count($firewallTitle) } catch { -1 }
					if ($dialogs -gt 0) {
						Stop-Tree $process
						$firewallLine += "; one APPEARED at $([int]$age) s"
						$result = "a firewall dialog appeared: stopped (it is Jeff's, not clicked)"
						break
					}
					if ($dialogs -lt 0) { $firewallUnread = $true }
				}
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
		# The server goes with the game (a tray stop, a timeout, the game's exit or crash):
		# by its PID here, and by the job should this runner itself end first.
		if ($server -ne $null) {
			if ($server.HasExited) {
				$serverEnd = "it had exited by itself ($($server.ExitCode))"
			} else {
				Stop-Tree $server
				$gone = $server.WaitForExit(10000)
				$serverEnd = "stopped by the runner after the game ($(if ($gone) { 'gone' } else { 'STILL RUNNING' }))"
			}
			$joinedLines += "server at end: $serverEnd"
			Remove-Item Env:PSYKINETIC_TOKEN -ErrorAction SilentlyContinue
		}
		$used = [Idle]::LastTick() -ne $since
		$icon.Visible = $false
		$icon.Dispose()
		[Idle]::Release()
		if ($Joined) {
			$joinedLines += $(if ($socketLooks -gt 0 -or $socketLine -ne "") { "$socketLine ($socketLooks looks, ephemeral from $low)" } else { "SOCKETS: not looked at (no client ran)" })
			if ($firewallUnread) { $firewallLine += "; during the run: not checked (the windows could not be listed)" }
		}
		# The runner that ran, by its own file's hash (828 amended (4)): remote_shot.sh prints the
		# hash of the copy it sent, and says so when they differ.
		$runnerSha = try { (Get-FileHash -Algorithm SHA256 $PSCommandPath).Hash.ToLower().Substring(0, 16) } catch { "unread" }
		Add-Content -Encoding utf8 $log ($joinedLines + @($firewallLine) + @(
			"runner: $(Split-Path -Leaf $PSCommandPath), sha256 $runnerSha",
			"job: $(if ($jobMade -eq 0) { 'kill on close' } else { "not made (error $jobMade): processes stopped by PID only" }); $($jobbed -join '; ')",
			"full speed: $full",
			"window: ${width}x${height}, in front: $topped",
			"idle at start: $([int]$idleBefore) s; at end: $([int][Idle]::Seconds()) s",
			"laptop used during the run: $(if ($used) { 'yes' } else { 'no' })",
			"passes: $($passes -join '; ')",
			"power at start: $powerBefore",
			"power at end: $(Power-State)",
			"result: $result"))
		Set-Content $done $result
		exit 0
	}
}
