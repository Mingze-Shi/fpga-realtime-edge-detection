# Rebuild the Canny/photo-recognition bitstream with an Efinity installation that
# lives outside the folders blocked by this machine's application-control policy.
#
# The bundled Python of an Efinity install placed on D: cannot load its own DLLs
# here (Code Integrity event 3077, "did not meet the Enterprise signing level").
# Running the same software from the user profile on C: is allowed, so this
# script points every environment variable at that copy.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File build_canny_C.ps1
#   powershell -ExecutionPolicy Bypass -File build_canny_C.ps1 -EfinityHome 'C:\Users\Admin\Efinity\2026.1'

param(
    [string]$EfinityHome = 'C:\Users\Admin\Efinity\2026.1',
    [string]$SystemPython = 'C:\Program Files\Python313\python.exe'
)

$ErrorActionPreference = 'Stop'
$Project = $PSScriptRoot
Set-Location -LiteralPath $Project

$HomeUnix = $EfinityHome -replace '\\', '/'

$env:PYTHONPATH = $null
$env:PYTHONHOME = "$EfinityHome\python311"
$env:EFINITY_HOME = $HomeUnix
$env:EFXPT_HOME = "$HomeUnix/pt"
$env:EFXPGM_HOME = "$HomeUnix/pgm"
$env:EFXDBG_HOME = "$HomeUnix/debugger"
$env:EFXIPM_HOME = "$HomeUnix/ipm"
$env:EFXSVF_HOME = "$HomeUnix/debugger/svf_player"
$env:EFXSERDESDBG_HOME = "$HomeUnix/debugger/serdes_debug_tool"
$env:EFINITY_USER_DIR_INI = "$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:QT_PLUGIN_PATH = "$HomeUnix/bin"
$env:QT_QPA_PLATFORM_PLUGIN_PATH = "$HomeUnix/python311/platforms"
$env:PATH = "$EfinityHome\python311\bin;$EfinityHome\bin;$EfinityHome\pgm\bin;$EfinityHome\scripts;$env:PATH"

$EfinityPython = "$EfinityHome\python311\bin\python.exe"
if (-not (Test-Path -LiteralPath $EfinityPython)) { throw "Efinity Python not found: $EfinityPython" }

foreach ($flow in @('map', 'interface', 'pnr')) {
    Write-Output "### flow $flow $(Get-Date -Format T)"
    & $EfinityPython "$EfinityHome\scripts\efx_run.py" ti60f225_oob.xml --flow $flow --output_dir outflow_canny
    if ($LASTEXITCODE -ne 0) { throw "Canny $flow failed with exit code $LASTEXITCODE" }
}

# The verification script runs on the system Python, which must not inherit Efinity's PYTHONHOME.
$previousPythonHome = $env:PYTHONHOME
$env:PYTHONHOME = $null
Write-Output "### timing check $(Get-Date -Format T)"
& $SystemPython tests/check_canny_build.py --timing-only
if ($LASTEXITCODE -ne 0) { throw 'Canny timing/resource verification failed; bitstream not generated' }
$env:PYTHONHOME = $previousPythonHome

Write-Output "### programming files $(Get-Date -Format T)"
& $EfinityPython "$EfinityHome\scripts\efx_run.py" ti60f225_oob.xml --flow pgm --output_dir outflow_canny
if ($LASTEXITCODE -ne 0) { throw 'Canny bitstream generation failed' }

$env:PYTHONHOME = $null
Write-Output "### artifact verification $(Get-Date -Format T)"
& $SystemPython tests/check_canny_build.py
if ($LASTEXITCODE -ne 0) { throw 'Canny programming artifact verification failed' }

Write-Output "### done $(Get-Date -Format T)"
