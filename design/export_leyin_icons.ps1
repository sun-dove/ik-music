param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectDirectory = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectDirectory 'assets/branding/yueyin/note-ribbons.png'
$resources = Join-Path $projectDirectory 'android/app/src/yueyin/res'
$iconPath = Join-Path $projectDirectory 'windows/runner/resources/yueyin_icon.ico'
$sizes = @(16,24,32,48,64,128,256)

# 仅导出尺寸和文件格式，保留用户原图；生成服务失败，未伪称透明或简化版本。
function New-LeyinFrame([System.Drawing.Image]$Source, [int]$Size, [double]$Scale = 1) {
    $frame = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($frame)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $dimension = [int][Math]::Round($Size * $Scale)
        $offset = [int][Math]::Round(($Size - $dimension) / 2)
        $graphics.DrawImage($Source, $offset, $offset, $dimension, $dimension)
    } finally { $graphics.Dispose() }
    return ,$frame
}
if (-not $VerifyOnly) {
    $source = [System.Drawing.Image]::FromFile($sourcePath)
    try {
        foreach ($density in @{mdpi=1;hdpi=1.5;xhdpi=2;xxhdpi=3;xxxhdpi=4}.GetEnumerator()) {
            foreach ($kind in @('launcher','foreground')) {
                $relative = if ($kind -eq 'launcher') { 'mipmap-' + $density.Key + '/ic_launcher.png' } else { 'drawable-' + $density.Key + '/ic_launcher_foreground.png' }
                $size = [int]($(if ($kind -eq 'launcher') {48} else {108}) * $density.Value)
                $scale = if ($kind -eq 'launcher') {1} else {.42}
                $frame = New-LeyinFrame $source $size $scale
                try { $frame.Save((Join-Path $resources $relative), [System.Drawing.Imaging.ImageFormat]::Png) }
                finally { $frame.Dispose() }
            }
        }
        $frames = foreach ($size in $sizes) {
            $frame = New-LeyinFrame $source $size
            $stream = [IO.MemoryStream]::new()
            try { $frame.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png); ,$stream.ToArray() }
            finally { $frame.Dispose(); $stream.Dispose() }
        }
        $writer = [IO.BinaryWriter]::new([IO.File]::Create($iconPath))
        try {
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
            $offset = 6 + 16 * $sizes.Count
            for ($index=0; $index -lt $sizes.Count; $index++) {
                $size = if ($sizes[$index] -eq 256) {0} else {$sizes[$index]}
                $writer.Write([byte]$size); $writer.Write([byte]$size)
                $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
                $writer.Write([uint32]$frames[$index].Length); $writer.Write([uint32]$offset)
                $offset += $frames[$index].Length
            }
            foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
        } finally { $writer.Dispose() }
    } finally { $source.Dispose() }
}
& (Join-Path $PSScriptRoot 'export_yueyin_icons.ps1') -VerifyOnly
