param([string]$EfinityBin='D:\efinity\2026.1\bin')
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$runner=Join-Path $EfinityBin 'efx_run.bat'
if(-not(Test-Path -LiteralPath $runner)){throw "Efinity not found: $runner"}
New-Item -ItemType Directory -Force outflow_cnn | Out-Null
foreach($flow in @('map','interface','pnr','pgm')){
    Write-Output "=== $flow $(Get-Date -Format HH:mm:ss) ==="
    & $runner ti60f225_oob.xml --flow $flow --output_dir outflow_cnn
    if($LASTEXITCODE -ne 0){throw "Efinity $flow failed with $LASTEXITCODE"}
}
Write-Output "=== artifacts ==="
Get-ChildItem outflow_cnn\ti60f225_oob.bit,outflow_cnn\ti60f225_oob.hex -ErrorAction SilentlyContinue |
    Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String | Write-Output
