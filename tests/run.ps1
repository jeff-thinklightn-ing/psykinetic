# Runs the headless sim tests. Exit code 0 = all assertions passed, 1 = any failed.
# Godot is taken from $env:GODOT_PATH, or `godot` on PATH.
$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }

# The Windows GUI build detaches from the console (no output, no exit code);
# use the console build that ships next to it when there is one.
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
	& $godot --headless --path . --scene tests/push_test.tscn
	$code = $LASTEXITCODE
} finally {
	Pop-Location
}
exit $code
