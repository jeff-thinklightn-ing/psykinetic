# Runs the perception A/B eval (tests/perception_eval.gd) on this machine
# against the box's model: opens an ssh tunnel to the box's Ollama, runs
# the eval headless through it, closes the tunnel. Deploys nothing.
#
#   tools\perception_eval.ps1                      # 3 runs, every mode and scene
#   tools\perception_eval.ps1 -Runs 1 -Modes grid  # a quick look
#   tools\perception_eval.ps1 -Preview             # the scenes and their truth; no model
#
# The report goes to build\perception_eval.md, every answer to
# build\perception_eval.jsonl. The live server shares the box's Ollama, so
# latency is only clean while nobody is playing.
param(
	[int]$Runs = 3,
	[string]$Modes = 'list,grid,both',
	[string]$Scenes = '',
	[string]$Model = 'qwen3:14b',
	[string]$Box = $(if ($env:PSYKINETIC_BOX) { $env:PSYKINETIC_BOX } else { 'jequig@100.78.120.114' }),
	[int]$LocalPort = 21434,
	[string]$Out = 'build/perception_eval',
	[switch]$Preview
)

$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

$evalArgs = @("--eval-runs=$Runs", "--eval-modes=$Modes", "--eval-out=$Out")
if ($Scenes) { $evalArgs += "--eval-scenes=$Scenes" }
$tunnel = $null
if ($Preview) {
	$evalArgs += '--eval-preview'
} else {
	$tunnel = Start-Process ssh -ArgumentList @('-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-N',
		'-L', "${LocalPort}:127.0.0.1:11434", $Box) -PassThru -NoNewWindow
	Start-Sleep -Seconds 3
	if ($tunnel.HasExited) { Write-Error "the ssh tunnel to $Box did not open"; exit 1 }
	$evalArgs += @("--llm-url=http://127.0.0.1:$LocalPort/api/chat", "--llm-model=$Model")
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
	& $godot --headless --path . --scene tests/perception_eval.tscn -- @evalArgs
	$code = $LASTEXITCODE
} finally {
	Pop-Location
	if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id }
}
exit $code
