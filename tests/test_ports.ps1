# Dot-sourced by the PowerShell tests: $portOffset for this checkout, from
# tests/port_offsets.txt (see there), so worktrees can run their tests at the same time.
$portOffset = $null
if ($env:PSYKINETIC_TEST_PORT_OFFSET -match '^-?\d+$') {
	$portOffset = [int]$env:PSYKINETIC_TEST_PORT_OFFSET
} else {
	$folder = Split-Path (Split-Path $PSScriptRoot -Parent) -Leaf
	foreach ($line in Get-Content (Join-Path $PSScriptRoot 'port_offsets.txt')) {
		$fields = -split $line
		if ($fields.Count -eq 2 -and $fields[0] -eq $folder -and $fields[1] -match '^-?\d+$') {
			$portOffset = [int]$fields[1]
			break
		}
	}
	if ($null -eq $portOffset) {
		$total = 0
		foreach ($byte in [Text.Encoding]::UTF8.GetBytes($folder)) { $total += $byte }
		$portOffset = 1000 + 200 * ($total % 20)
	}
}
