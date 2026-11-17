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
		# Not listed: 5600 + 200 * (the md5 of the name, lower-cased, mod 100), as test_ports.gd's
		# hashed() (278 amended (11)).
		$md5 = [Security.Cryptography.MD5]::Create()
		$digest = -join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($folder.ToLowerInvariant()))[0..3] | ForEach-Object { $_.ToString('x2') })
		$portOffset = 5600 + 200 * [int]([Convert]::ToUInt64($digest, 16) % 100)
	}
}
