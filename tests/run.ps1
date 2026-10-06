# Runs the headless sim tests, one scene after another.
# Exit code 0 = every assertion in every scene passed, 1 = any failed.
# Godot is taken from $env:GODOT_PATH, or `godot` on PATH.
$godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }

# The Windows GUI build detaches from the console (no output, no exit code);
# use the console build that ships next to it when there is one.
if ($godot -match '\.exe$' -and $godot -notmatch '_console\.exe$') {
	$console = $godot -replace '\.exe$', '_console.exe'
	if (Test-Path $console) { $godot = $console }
}

$scenes = @('tests/push_test.tscn', 'tests/respawn_test.tscn', 'tests/companion_test.tscn', 'tests/spawn_test.tscn', 'tests/mirror_test.tscn')
$code = 0
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
	foreach ($scene in $scenes) {
		Write-Output "### $scene"
		# A script error aborts a test function without failing an assertion,
		# so treat any engine error as a failure too.
		$output = & $godot --headless --path . --scene $scene 2>&1 | ForEach-Object { "$_" }
		$output | Write-Output
		if ($LASTEXITCODE -ne 0) { $code = 1 }
		if ($output | Select-String 'SCRIPT ERROR|^ERROR:') { $code = 1 }
	}
} finally {
	Pop-Location
}
exit $code
