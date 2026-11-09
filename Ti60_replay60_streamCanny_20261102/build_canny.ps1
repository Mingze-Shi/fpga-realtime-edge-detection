param([string]$EfinityBin = 'D:\efinity\2026.1\bin')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if ((Get-Content -LiteralPath 'rtl/ti60f225_oob_top.v' -Raw).Contains('.EXPRESSION_ENABLE(1)')) {
    & "$PSScriptRoot/build_expressions.ps1" -EfinityBin $EfinityBin
    exit $LASTEXITCODE
}
$runner = Join-Path $EfinityBin 'efx_run.bat'
if (-not (Test-Path -LiteralPath $runner)) { throw 'Pass -EfinityBin with your Efinity bin directory' }
# Keep previous outflow/ programming files intact. Do not program the board here.
foreach ($flow in @('map', 'interface', 'pnr')) {
    & $runner 'ti60f225_oob.xml' --flow $flow --output_dir outflow_canny
    if ($LASTEXITCODE -ne 0) { throw "Canny $flow failed" }
}
# PNR exit success alone does not establish timing closure.
python tests/check_canny_build.py --timing-only
if ($LASTEXITCODE -ne 0) { throw 'Canny timing/resource verification failed; bitstream not generated' }
& $runner 'ti60f225_oob.xml' --flow pgm --output_dir outflow_canny
if ($LASTEXITCODE -ne 0) { throw 'Canny bitstream generation failed' }
python tests/check_canny_build.py
if ($LASTEXITCODE -ne 0) { throw 'Canny programming artifact verification failed' }
