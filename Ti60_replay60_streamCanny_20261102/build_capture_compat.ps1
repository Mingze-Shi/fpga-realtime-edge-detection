param([string]$EfinityBin='D:\efinity-2026.1.132-windows-x64\2026.1\bin')
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$runner=Join-Path $EfinityBin 'efx_run.bat'
foreach($flow in @('map','interface','pnr')) {
    & $runner ti60f225_capture_compat.xml --flow $flow --output_dir outflow_capture_compat
    if($LASTEXITCODE -ne 0){throw "Capture compatibility $flow failed"}
}
# Review the generated timing report before running the pgm flow.
Write-Output 'Review outflow_capture_compat timing reports before generating programming files.'
