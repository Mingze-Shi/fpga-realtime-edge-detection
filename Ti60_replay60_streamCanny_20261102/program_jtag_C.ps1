# Program ti60f225_oob.bit into FPGA SRAM via JTAG (volatile, lost on power-off).
# Uses the C-drive Efinity copy because the machine's application control policy
# blocks unsigned DLLs loading from D:.
# Usage: powershell -ExecutionPolicy Bypass -File .\program_jtag_C.ps1

param(
    [string]$EfinityHome = 'C:\Users\Admin\Efinity\2026.1',
    [string]$BitFile = 'D:\Desktop\sobel_filter114514(1)\sobel_filter114514\outflow_canny\ti60f225_oob.bit'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BitFile)) { throw "Bit file not found: $BitFile" }
if (-not (Test-Path "$EfinityHome\python311\bin\python.exe")) { throw "Efinity not found at $EfinityHome" }

$eh = $EfinityHome
$env:EFINITY_HOME   = ($eh -replace '\\','/')
$env:EFXPGM_HOME    = "$env:EFINITY_HOME/pgm"
$env:EFXDBG_HOME    = "$env:EFINITY_HOME/debugger"
$env:EFXSVF_HOME    = "$env:EFINITY_HOME/debugger/svf_player"
$env:EFXPT_HOME     = "$env:EFINITY_HOME/pt"
$env:EFXIPM_HOME    = "$env:EFINITY_HOME/ipm"
$env:EFXSERDESDBG_HOME = "$env:EFINITY_HOME/debugger/serdes_debug_tool"
$env:EFINITY_USER_DIR_INI = "$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:PYTHONHOME     = "$eh\python311"
$env:QT_PLUGIN_PATH = "$eh\python311"
$env:PYTHONPATH     = "$eh\pgm\bin;$eh\debugger\bin"
$env:PYTHONIOENCODING = 'utf-8'
$env:PATH = "$eh\python311\bin;$eh\bin;$eh\pgm\bin;$eh\debugger\bin;$eh\debugger\svf_player\bin;$eh\scripts;$env:PATH"

"Bit file : $BitFile"
"Size     : {0:N0} bytes" -f (Get-Item $BitFile).Length
""

# Optional: list what is on the JTAG chain first
& "$eh\python311\bin\python.exe" -m efx_pgm.ftdi_program --scan_usb

& "$eh\python311\bin\python.exe" -m efx_pgm.ftdi_program -m jtag $BitFile
$rc = $LASTEXITCODE

if ($rc -eq 0) {
    ""
    "PROGRAMMING DONE (SRAM). The design is running now; it is lost after power-off."
} else {
    ""
    "PROGRAMMING FAILED, exit code $rc"
}
exit $rc
