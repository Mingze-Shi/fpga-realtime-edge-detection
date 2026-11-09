param([string]$EfinityHome='D:\efinity-2026.1.132-windows-x64\2026.1')
$ErrorActionPreference='Stop'
Set-Location -LiteralPath (Split-Path $PSScriptRoot -Parent)
$ivlRoot=Join-Path $PWD 'tools\iverilog-portable\Library'
$env:PATH="$ivlRoot\mingw-w64\bin;$EfinityHome\bin;$env:PATH"
foreach($bench in @('filters5x5_tb','canny_stream_tb','canny_cleanup_tb','canny_flat_video_tb')) {
    $sources=@('rtl/canny_window5x5.v','rtl/gaussian5x5.v')
    if($bench -eq 'filters5x5_tb'){$sources+='rtl/median5x5.v'}
    else{$sources+=@('rtl/canny_window3x3.v','rtl/canny_frontend.v','rtl/canny_stream.v')}
    if($bench -eq 'canny_flat_video_tb'){
        $sources+=@('rtl/median5x5.v','rtl/sobel_stream.v','rtl/threshold_keys.v',
            'rtl/mode_key.v','rtl/sc431_sobel_video.v')
    }
    $sources+="tests/$bench.v"
    $output="test_output/$bench.vvp"
    & "$ivlRoot\bin\iverilog.exe" -B "$ivlRoot\lib\ivl" -g2012 -s $bench -o $output @sources
    if($LASTEXITCODE -ne 0){throw "$bench compilation failed"}
    & "$ivlRoot\bin\vvp.exe" $output
    if($LASTEXITCODE -ne 0){throw "$bench simulation failed"}
}
