# This script is delivered for explicit later use. Building does not run it.
param([ValidateSet('Jtag','Flash')][string]$Mode='Jtag',[string]$EfinityHome='D:\efinity\2026.1')
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$reportPath=Join-Path $projectRoot 'outflow_cnn\cnn_verification.json'
$report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if($report.device -ne 'Ti60F225' -or $report.timing_model -ne 'I3'){throw 'Unexpected device'}
foreach($ext in @('bit','hex')){
    $artifact=$report.artifacts.$ext
    $artifactPath=Join-Path $projectRoot $artifact.path
    if((Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLower() -ne $artifact.sha256){throw "Artifact hash mismatch: $ext"}
}
$bitPath=Join-Path $projectRoot $report.artifacts.bit.path
$hexPath=Join-Path $projectRoot $report.artifacts.hex.path
$py=Join-Path $EfinityHome 'python311\bin\python.exe'
if(-not(Test-Path -LiteralPath $py)){throw 'Efinity Python not found'}
$env:EFINITY_HOME=$EfinityHome.Replace('\','/')
$env:EFXPGM_HOME="$env:EFINITY_HOME/pgm"
$env:EFXDBG_HOME="$env:EFINITY_HOME/debugger"
$env:EFXSVF_HOME="$env:EFINITY_HOME/debugger/svf_player"
$env:EFXPT_HOME="$env:EFINITY_HOME/pt"
$env:EFXIPM_HOME="$env:EFINITY_HOME/ipm"
$env:EFXSERDESDBG_HOME="$env:EFINITY_HOME/debugger/serdes_debug_tool"
$env:EFINITY_USER_DIR_INI="$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:EFINITY_USER_DIR="$env:LOCALAPPDATA\efinity"
$env:PYTHONHOME=Join-Path $EfinityHome 'python311'
$env:QT_PLUGIN_PATH=$env:PYTHONHOME
$env:PYTHONPATH="$EfinityHome\pgm\bin;$EfinityHome\debugger\bin"
$env:PATH="$EfinityHome\python311\bin;$EfinityHome\bin;$EfinityHome\pgm\bin;$EfinityHome\debugger\bin;$env:PATH"
if($Mode -eq 'Flash'){
    $bridge=Join-Path $EfinityHome 'pgm\fli\titanium\u10660A79.bit'
    if(-not(Test-Path -LiteralPath $bridge)){throw 'Ti60 JTAG-SPI bridge image missing'}
    & $py -m efx_pgm.ftdi_program -m jtag $bridge
    if($LASTEXITCODE -ne 0){throw 'Bridge loading failed'}
    & $py -m efx_pgm.ftdi_program -m jtag_bridge $hexPath --jtag_bridge_mode all
    if($LASTEXITCODE -ne 0){throw 'Flash write/verify failed'}
}
& $py -m efx_pgm.ftdi_program -m jtag $bitPath
if($LASTEXITCODE -ne 0){throw 'JTAG download failed'}
Write-Output "Completed $Mode programming. Flash power-cycle verification is a separate board test."
