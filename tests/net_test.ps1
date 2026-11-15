# tests/net_test.sh from PowerShell (the coordinator, 11-14: one network test,
# not two copies drifting; land.ps1 and tools/ship.ps1 keep calling this). Runs
# the sh through Git's bash, as tests/server_boot_test.ps1 does: its output and
# its exit code (0 = all checks passed, 1 = any failed). The sh reads
# GODOT_PATH, NET_TEST_SERIAL, NET_TEST_WAIT and NET_TEST_GROUPS as before.
#   tests\net_test.ps1
& bash (Join-Path $PSScriptRoot 'net_test.sh')
exit $LASTEXITCODE
