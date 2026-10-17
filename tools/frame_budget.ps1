# The client's frame budget on this machine, in one line to paste: a host in
# the wilds town (its residents, herds of animals), several players, a storm
# at night, the big minimap open, at the zoom Jeff plays (camera_zoom 1.1),
# for -Seconds; then the frame time's median, 99th percentile and worst, the
# renderer's share, and the machine. Every piece can be left out to see what
# it costs: -Off shadows,border,glimpse,minimap and -NoFade, -Clear (a clear
# day, no storm). -AA off|fxaa|smaa|msaa4 picks the anti-aliasing (the
# game's antialias=, decision 385; smaa as the game's default). Runs with APPDATA set to a temp folder of its own (the
# town is made there by tools/town_state), so it reads the levels as
# committed and writes nothing to the game's own user data.
#   tools/frame_budget.ps1 [-Godot <exe>] [-Players 9] [-Herds 4] [-Seconds 20]
#     [-Width 1920] [-Height 1080] [-Zoom 1.1] [-AA smaa] [-Off shadows,border,glimpse,minimap] [-NoFade] [-Clear]
# The window is the game's: leave it in front and the machine otherwise idle.
param(
	[string]$Godot = $env:GODOT_PATH,
	[int]$Players = 9,
	[int]$Herds = 4,
	[int]$Seconds = 20,
	[int]$Width = 1920,
	[int]$Height = 1080,
	[double]$Zoom = 1.1,
	[ValidateSet("off", "fxaa", "smaa", "msaa4")][string]$AA = "smaa",
	[string[]]$Off = @(),
	[switch]$NoFade,
	[switch]$Clear
)
$ErrorActionPreference = "Stop"
# -Off a,b comes as one string through powershell -File: one name each.
$Off = @(($Off -join ',') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
if (-not $Godot) { throw "No Godot: pass -Godot <path to the Godot exe> or set GODOT_PATH" }
$console = $Godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $Godot = $console }
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) "psykinetic-frame-budget"
$appdata = Join-Path $work "appdata"
New-Item -ItemType Directory -Force $appdata | Out-Null
$settings = Join-Path $work "settings.cfg"
$culture = [Globalization.CultureInfo]::InvariantCulture
Set-Content -Encoding utf8 $settings ("window_width={0}`nwindow_height={1}`nwindow_mode=windowed`nhints=off`ncamera_zoom={2}`nantialias={3}" -f $Width, $Height, $Zoom.ToString($culture), $AA)
$env:APPDATA = $appdata
$town = Join-Path $work "town.json"
& $Godot --headless --path $root res://tools/town_state.tscn -- "--out=$town" | Out-Null
if (-not (Test-Path $town)) { throw "tools/town_state made no town ($town)" }
$state = Join-Path $work "world.json"
Copy-Item -Force $town $state
$bench = @("--path", $root, "--scene", "res://tools/map_bench.tscn", "--",
	"--map=wilds", "--bench-state=$state", "--test-herds=$Herds", "--players=$Players",
	"--ticks=60", "--settle=0", "--seconds=$Seconds", "--host", "--settings=$settings")
if ($Clear) { $bench += @("--weather=clear", "--hour=12") } else { $bench += @("--weather=storm", "--hour=23", "--test-minimap") }
if ($Off.Count -gt 0) { $bench += "--off=$($Off -join ',')" }
if ($NoFade) { $bench += "--fade=0" }
# A heavy job (decision 394): through the gate as <checkout> bench.
$gate = Join-Path $PSScriptRoot "heavy_job.py"
$log = & python $gate run (Split-Path $root -Leaf) bench -- $Godot @bench 2>&1 | ForEach-Object { "$_" }
$time = $log | Where-Object { $_ -like "BENCH frame time:*" } | Select-Object -First 1
$frames = $log | Where-Object { $_ -like "BENCH frames:*" } | Select-Object -First 1
$render = $log | Where-Object { $_ -like "BENCH a frame:*" } | Select-Object -First 1
$device = $log | Where-Object { $_ -match "Using Device" } | Select-Object -First 1
if (-not $time) {
	$log | Select-Object -Last 20 | ForEach-Object { Write-Output $_ }
	throw "map_bench gave no frame times (its last lines are above)"
}
$median = [regex]::Match($time, "median ([0-9.]+) ms").Groups[1].Value
$p99 = [regex]::Match($time, "99th ([0-9.]+) ms").Groups[1].Value
$worst = [regex]::Match($frames, "worst frame ([0-9.]+) ms").Groups[1].Value
$fps = [regex]::Match($frames, "([0-9.]+) fps").Groups[1].Value
$cpu = [regex]::Match($render, "([0-9.]+) ms on the CPU").Groups[1].Value
$gpu = [regex]::Match($render, "([0-9.]+) ms on the GPU").Groups[1].Value
$gpuName = if ($device) { ($device -replace '.*Using Device #\d+: ', '').Trim() } else { "unknown GPU" }
$cpuName = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$scene = if ($Clear) { "clear day" } else { "storm at night, minimap open" }
$left = @()
if ($Off.Count -gt 0) { $left += $Off }
if ($NoFade) { $left += "fade" }
$without = if ($left.Count -gt 0) { "; without $($left -join ', ')" } else { "" }
Write-Output ("frame_budget: median {0} ms, 99th {1} ms, worst {2} ms ({3} fps; rendering {4} ms CPU, {5} ms GPU) | wilds town, {6} players, {7} herds, {8}, {9}x{10} zoom {11}, AA {15}{12} | {13}; {14}" -f `
	$median, $p99, $worst, $fps, $cpu, $gpu, $Players, $Herds, $scene, $Width, $Height, $Zoom.ToString($culture), $without, $cpuName, $gpuName, $AA)
