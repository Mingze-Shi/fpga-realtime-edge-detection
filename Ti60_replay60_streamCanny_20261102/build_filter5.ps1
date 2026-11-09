param([string]$EfinityHome='D:\efinity-2026.1.132-windows-x64\2026.1')
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$runner=Join-Path $EfinityHome 'bin\efx_run.bat'
foreach($flow in @('map','interface','pnr')) {
    & $runner ti60f225_oob.xml --flow $flow --output_dir outflow_filter5
    if($LASTEXITCODE -ne 0){throw "5x5 $flow failed"}
}
$timing=Get-Content outflow_filter5/ti60f225_oob.timing.rpt -Raw
# A successful PNR can still randomly place essential ports when interface
# outputs are missing. Only the baseline's unused PLL reset may be unassigned.
$placement=Get-Content outflow_filter5/ti60f225_oob.place.rpt -Raw
$unassigned=[regex]::Match($placement,'(?s)Unassigned Core Pins(.*?)IO Placement Summary \(end\)')
if(-not $unassigned.Success){throw 'Cannot verify IO placement summary'}
foreach($line in ($unassigned.Groups[1].Value -split "`n")) {
    if($line -match '^\s*\|\s*(\S+)\s*\|\s*(Input|Output)\s*\|' -and $Matches[1] -ne 'pll_inst4_RSTN') {
        throw "Unassigned interface port: $($Matches[1]); refusing programming-file generation"
    }
}
if($timing -match 'Slack\s*:\s*-'){throw 'Negative timing slack; refusing programming-file generation'}
$generationStart=Get-Date
& $runner ti60f225_oob.xml --flow pgm --output_dir outflow_filter5
if($LASTEXITCODE -ne 0){throw '5x5 programming-file generation failed'}
$artifact=Get-Item outflow_filter5/ti60f225_oob.bit
if($artifact.Length -eq 0 -or $artifact.LastWriteTime -lt $generationStart){throw 'No fresh bitstream generated'}
Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256
