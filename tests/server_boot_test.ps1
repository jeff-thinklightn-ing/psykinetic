# tests/server_boot_test.sh from PowerShell (decision 450): the "Linux
# Server" pack exported and booted by the Windows release template, a client
# joining, failing on any error line. Runs the sh through Git's bash, as
# tools/heavy_job.sh's callers do; its exit code.
#   tests\server_boot_test.ps1
& bash (Join-Path $PSScriptRoot 'server_boot_test.sh')
exit $LASTEXITCODE
