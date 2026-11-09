param(
    [string]$EfinityBin='D:\efinity\2026.1\bin',
    [string]$PythonExe='python'
)
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$runner=Join-Path $EfinityBin 'efx_run.bat'
if(-not(Test-Path -LiteralPath $runner)){throw "Efinity not found: $runner"}
& $PythonExe -X utf8 tests/run_all_tests.py
if($LASTEXITCODE -ne 0){throw 'Existing regression failed'}
& $PythonExe -X utf8 tests/run_cnn_tests.py
if($LASTEXITCODE -ne 0){throw 'CNN regression failed'}
& $PythonExe -X utf8 tests/run_expression_cnn_tests.py
if($LASTEXITCODE -ne 0){throw 'Expression CNN regression failed'}
& $PythonExe -X utf8 tests/run_replay6_tests.py --full
if($LASTEXITCODE -ne 0){throw 'Six-frame regression failed'}
& $PythonExe -X utf8 tests/check_cnn_build.py --snapshot
if($LASTEXITCODE -ne 0){throw 'Cannot snapshot build inputs'}
foreach($flow in @('map','interface','pnr')){
    & $runner ti60f225_oob.xml --flow $flow --output_dir outflow_cnn
    if($LASTEXITCODE -ne 0){throw "Efinity $flow failed"}
    if($flow -eq 'map'){
        & $PythonExe -X utf8 tests/check_replay6_netlist.py
        if($LASTEXITCODE -ne 0){throw 'Synthesized feedback check failed'}
    }
}
& $PythonExe -X utf8 tests/check_cnn_build.py --timing-only
if($LASTEXITCODE -ne 0){throw 'Timing or resource verification failed'}
& $runner ti60f225_oob.xml --flow pgm --output_dir outflow_cnn
if($LASTEXITCODE -ne 0){throw 'Programming artifact generation failed'}
& $PythonExe -X utf8 tests/check_cnn_build.py
if($LASTEXITCODE -ne 0){throw 'Final artifact verification failed'}
