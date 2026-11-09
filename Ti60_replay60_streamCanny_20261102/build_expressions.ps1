param([string]$EfinityBin='D:\efinity\2026.1\bin',[string]$PythonExe='')
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not $PythonExe) {
    if (Get-Command python -ErrorAction SilentlyContinue) { $PythonExe=(Get-Command python).Source }
    elseif (Test-Path -LiteralPath "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe") {
        $PythonExe="$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
    } else { throw 'Python 3 with Pillow is required; pass -PythonExe.' }
}
& $PythonExe -X utf8 tests/run_all_tests.py
if ($LASTEXITCODE -ne 0) { throw 'Regression/expression tests failed.' }
$taskRunner=Join-Path $EfinityBin 'efx_run.bat'
if (-not (Test-Path -LiteralPath $taskRunner)) { throw 'Pass the installed Efinity bin directory.' }
foreach ($taskFlow in @('map','interface','pnr')) {
    & $taskRunner ti60f225_oob.xml --flow $taskFlow --output_dir outflow_expression
    if ($LASTEXITCODE -ne 0) { throw "Expression $taskFlow failed." }
}
& $PythonExe -X utf8 tests/check_expression_build.py --timing-only
if ($LASTEXITCODE -ne 0) { throw 'Resource/timing/freshness checks failed; no new programming file generated.' }
& $taskRunner ti60f225_oob.xml --flow pgm --output_dir outflow_expression
if ($LASTEXITCODE -ne 0) { throw 'Programming file generation failed.' }
& $PythonExe -X utf8 tests/check_expression_build.py
if ($LASTEXITCODE -ne 0) { throw 'Programming artifact verification failed.' }
