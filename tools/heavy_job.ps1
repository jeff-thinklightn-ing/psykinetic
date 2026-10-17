# tools/heavy_job.py from PowerShell (decision 394): the resource gate for
# heavy jobs, its commands as there.
#   tools/heavy_job.ps1 run <tree> <kind> -- <command...>
& python (Join-Path $PSScriptRoot "heavy_job.py") @args
exit $LASTEXITCODE
