# Where a Godot the tooling runs writes its log (decision 664): this
# checkout's build/logs/<name>.log, never the shared user:// logs folder,
# whose few kept files are Jeff's client's (a test's godot.log rotated his
# draugr fight's out). Dot-sourced:
#   . (Join-Path $PSScriptRoot 'godot_log.ps1')          # from tests/
#   . (Join-Path $PSScriptRoot '..\tests\godot_log.ps1')  # from tools/
#   & $godot --log-file (Get-GodotLog 'import') --headless ...
# Each Godot running at the same time takes a name of its own.
function Get-GodotLog([string]$name) {
	$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\logs'
	New-Item -ItemType Directory -Force $dir | Out-Null
	Join-Path $dir "$name.log"
}
