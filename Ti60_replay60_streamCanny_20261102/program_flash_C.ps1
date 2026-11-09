# Permanent programming: write the design into the on-board SPI Flash.
# Survives power-off. Board reboots into the new design on next power-up.
#
# Why three steps:
#   1. The on-board flash is NOT wired to the FTDI SPI channel on this board
#      (JEDEC read returns FF), so "SPI Active" mode cannot see the flash.
#   2. The only working path is the JTAG-to-SPI bridge: load Efinix's bridge
#      image (pgm/fli/titanium/u<IDCODE>.bit) into the FPGA first, then talk
#      to the flash through it.
#   3. After flashing, the FPGA is still running the bridge image, so we
#      re-download the user bitstream via JTAG to make it run immediately.
#
# Usage: powershell -ExecutionPolicy Bypass -File .\program_flash_C.ps1

param(
    [string]$EfinityHome = 'C:\Users\Admin\Efinity\2026.1',
    [string]$HexFile = 'D:\Desktop\sobel_filter114514(1)\sobel_filter114514\outflow_canny\ti60f225_oob.hex',
    [string]$BitFile = 'D:\Desktop\sobel_filter114514(1)\sobel_filter114514\outflow_canny\ti60f225_oob.bit',
    [string]$BridgeImage = '',   # auto: $EfinityHome\pgm\fli\titanium\u10660A79.bit
    [switch]$SkipFinalJtagLoad
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $HexFile)) { throw "HEX file not found: $HexFile" }
if (-not (Test-Path $BitFile)) { throw "BIT file not found: $BitFile" }
if ($BridgeImage -eq '') { $BridgeImage = Join-Path $EfinityHome 'pgm\fli\titanium\u10660A79.bit' }
if (-not (Test-Path $BridgeImage)) { throw "JTAG-SPI bridge image not found: $BridgeImage" }

$eh = $EfinityHome
$env:EFINITY_HOME   = ($eh -replace '\\','/')
$env:EFXPGM_HOME    = "$env:EFINITY_HOME/pgm"
$env:EFXDBG_HOME    = "$env:EFINITY_HOME/debugger"
$env:EFXSVF_HOME    = "$env:EFINITY_HOME/debugger/svf_player"
$env:EFXPT_HOME     = "$env:EFINITY_HOME/pt"
$env:EFXIPM_HOME    = "$env:EFINITY_HOME/ipm"
$env:EFXSERDESDBG_HOME = "$env:EFINITY_HOME/debugger/serdes_debug_tool"
$env:EFINITY_USER_DIR_INI = "$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:EFINITY_USER_DIR = "$env:LOCALAPPDATA\efinity"
$env:PYTHONHOME     = "$eh\python311"
$env:QT_PLUGIN_PATH = "$eh\python311"
$env:PYTHONPATH     = "$eh\pgm\bin;$eh\debugger\bin"
$env:PYTHONIOENCODING = 'utf-8'
$env:PATH = "$eh\python311\bin;$eh\bin;$eh\pgm\bin;$eh\debugger\bin;$eh\debugger\svf_player\bin;$eh\scripts;$env:PATH"

$py = "$eh\python311\bin\python.exe"

"=== Step 1/3: load JTAG-SPI bridge image into FPGA ==="
& $py -m efx_pgm.ftdi_program -m jtag $BridgeImage
if ($LASTEXITCODE -ne 0) { "FAILED at bridge image load"; exit 1 }

""
"=== Step 2/3: erase + write + verify SPI Flash ($HexFile) ==="
& $py -m efx_pgm.ftdi_program -m jtag_bridge $HexFile --jtag_bridge_mode all
if ($LASTEXITCODE -ne 0) { "FAILED at flash programming"; exit 1 }

if (-not $SkipFinalJtagLoad) {
    ""
    "=== Step 3/3: download user bitstream via JTAG so it runs right now ==="
    & $py -m efx_pgm.ftdi_program -m jtag $BitFile
    if ($LASTEXITCODE -ne 0) { "FAILED at final JTAG load"; exit 1 }
}

""
"FLASH PROGRAMMING DONE. The new design is now in SPI Flash (permanent) and also running in SRAM."
"Power-cycle the board to confirm it boots from flash on its own."
exit 0
