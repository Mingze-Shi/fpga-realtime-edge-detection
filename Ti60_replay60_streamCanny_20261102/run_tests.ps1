param([string]$SimulatorBin = '')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not $SimulatorBin) {
    if ($env:IVERILOG_BIN) { $SimulatorBin = $env:IVERILOG_BIN }
    elseif (Test-Path -LiteralPath 'tools\iverilog-portable\Library\bin\iverilog.exe') {
        $SimulatorBin = Join-Path $PSScriptRoot 'tools\iverilog-portable\Library\bin'
    } elseif (Get-Command iverilog.exe -ErrorAction SilentlyContinue) {
        $SimulatorBin = Split-Path (Get-Command iverilog.exe).Source
    } else { throw 'Set IVERILOG_BIN or pass -SimulatorBin with the Icarus bin directory' }
}
$simulatorBin = $SimulatorBin
$runtimeBin = Join-Path (Split-Path $simulatorBin) 'mingw-w64\bin'
$env:PATH = $runtimeBin + ';' + $env:PATH
$env:PATH = $simulatorBin + ';' + $env:PATH
if (-not (Test-Path -LiteralPath 'test_output')) { New-Item -ItemType Directory -Path 'test_output' | Out-Null }
if (-not (Test-Path -LiteralPath 'test_output\tmp')) { New-Item -ItemType Directory -Path 'test_output\tmp' | Out-Null }
$env:TMPDIR = Join-Path $PSScriptRoot 'test_output\tmp'
$env:TMP = $env:TMPDIR
$env:TEMP = $env:TMPDIR
& (Join-Path $simulatorBin 'iverilog.exe') -g2012 -s threshold_keys_tb -o 'test_output/threshold_keys.vvp' 'rtl/threshold_keys.v' 'tests/threshold_keys_tb.v'
if ($LASTEXITCODE -ne 0) { throw 'Button test compile failed' }
& (Join-Path $simulatorBin 'vvp.exe') 'test_output/threshold_keys.vvp' 2>&1 | Tee-Object -FilePath 'test_output/keys_simulation.log'
if ($LASTEXITCODE -ne 0) { throw 'Button test failed' }
& (Join-Path $simulatorBin 'iverilog.exe') -g2012 -s median3x3_tb -o 'test_output/median3x3.vvp' 'rtl/median3x3.v' 'tests/median3x3_tb.v'
if ($LASTEXITCODE -ne 0) { throw 'Median filter test compile failed' }
& (Join-Path $simulatorBin 'vvp.exe') 'test_output/median3x3.vvp' 2>&1 | Tee-Object -FilePath 'test_output/median3x3_simulation.log'
if ($LASTEXITCODE -ne 0) { throw 'Median filter test failed' }
& (Join-Path $simulatorBin 'iverilog.exe') -g2012 -s threshold_video_tb -o 'test_output/threshold_video.vvp' 'rtl/threshold_keys.v' 'rtl/mode_key.v' 'rtl/median3x3.v' 'rtl/sobel_stream.v' 'rtl/sc431_sobel_video.v' 'tests/threshold_video_tb.v'
if ($LASTEXITCODE -ne 0) { throw 'Video test compile failed' }
& (Join-Path $simulatorBin 'vvp.exe') 'test_output/threshold_video.vvp' 2>&1 | Tee-Object -FilePath 'test_output/video_simulation.log'
if ($LASTEXITCODE -ne 0) { throw 'Video test failed' }
& (Join-Path $simulatorBin 'iverilog.exe') -g2012 -s color_mode_tb -o 'test_output/color_mode.vvp' 'rtl/threshold_keys.v' 'rtl/mode_key.v' 'rtl/median3x3.v' 'rtl/sobel_stream.v' 'rtl/sc431_sobel_video.v' 'tests/color_mode_tb.v'
if ($LASTEXITCODE -ne 0) { throw 'Color mode test compile failed' }
& (Join-Path $simulatorBin 'vvp.exe') 'test_output/color_mode.vvp' 2>&1 | Tee-Object -FilePath 'test_output/color_mode_simulation.log'
if ($LASTEXITCODE -ne 0) { throw 'Color mode test failed' }
& (Join-Path $simulatorBin 'iverilog.exe') -g2012 -s mode_key_tb -o 'test_output/mode_key.vvp' 'rtl/mode_key.v' 'tests/mode_key_tb.v'
if ($LASTEXITCODE -ne 0) { throw 'Long press test compile failed' }
& (Join-Path $simulatorBin 'vvp.exe') 'test_output/mode_key.vvp' 2>&1 | Tee-Object -FilePath 'test_output/mode_key_simulation.log'
if ($LASTEXITCODE -ne 0) { throw 'Long press test failed' }
& (Join-Path $simulatorBin 'iverilog.exe') -g2012 -s frame_freeze_tb -o 'test_output/frame_freeze.vvp' 'rtl/frame_buffer_V4/bank_switch.v' 'tests/frame_freeze_tb.v'
if ($LASTEXITCODE -ne 0) { throw 'DDR freeze test compile failed' }
& (Join-Path $simulatorBin 'vvp.exe') 'test_output/frame_freeze.vvp' 2>&1 | Tee-Object -FilePath 'test_output/frame_freeze_simulation.log'
if ($LASTEXITCODE -ne 0) { throw 'DDR freeze test failed' }
& (Join-Path $simulatorBin 'iverilog.exe') -g2012 -s freeze_video_tb -o 'test_output/freeze_video.vvp' 'rtl/mode_key.v' 'rtl/threshold_keys.v' 'rtl/median3x3.v' 'rtl/sobel_stream.v' 'rtl/sc431_sobel_video.v' 'rtl/frame_buffer_V4/bank_switch.v' 'tests/freeze_video_tb.v'
if ($LASTEXITCODE -ne 0) { throw 'Freeze video integration test compile failed' }
& (Join-Path $simulatorBin 'vvp.exe') 'test_output/freeze_video.vvp' 2>&1 | Tee-Object -FilePath 'test_output/freeze_video_simulation.log'
if ($LASTEXITCODE -ne 0) { throw 'Freeze video integration test failed' }
$env:IVERILOG_BIN = $simulatorBin
python tests/run_canny_tests.py
if ($LASTEXITCODE -ne 0) { throw 'Canny tests failed' }
python tests/run_photo_tests.py
if ($LASTEXITCODE -ne 0) { throw 'Fixed-photo tests failed' }
