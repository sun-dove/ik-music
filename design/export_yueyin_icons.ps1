param([switch]$VerifyOnly)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectDirectory = Split-Path -Parent $PSScriptRoot
$brandDirectory = Join-Path $projectDirectory 'assets/branding/yueyin'
$androidResources = Join-Path $projectDirectory 'android/app/src/yueyin/res'
$windowsIcon = Join-Path $projectDirectory 'windows/runner/resources/yueyin_icon.ico'
$densities = @{ mdpi = 1; hdpi = 1.5; xhdpi = 2; xxhdpi = 3; xxxhdpi = 4 }
$iconSizes = @(16, 24, 32, 48, 64, 128, 256)

function Get-ScaledIcon([System.Drawing.Image]$Image, [int]$Size, [double]$ArtworkScale = 1) {
    $result = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($result)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $dimension = [int][Math]::Round($Size * $ArtworkScale)
        $offset = [int][Math]::Round(($Size - $dimension) / 2)
        $graphics.DrawImage($Image, $offset, $offset, $dimension, $dimension)
    } finally { $graphics.Dispose() }
    return ,$result
}

if (-not $VerifyOnly) {
    $cream = [System.Drawing.Image]::FromFile((Join-Path $brandDirectory 'logo-cream.png'))
    $transparent = [System.Drawing.Image]::FromFile((Join-Path $brandDirectory 'logo-transparent.png'))
    try {
        foreach ($density in $densities.GetEnumerator()) {
            $launcherDirectory = Join-Path $androidResources ('mipmap-' + $density.Key)
            $foregroundDirectory = Join-Path $androidResources ('drawable-' + $density.Key)
            New-Item -ItemType Directory -Path $launcherDirectory,$foregroundDirectory -Force | Out-Null
            $launcher = Get-ScaledIcon $cream ([int](48 * $density.Value))
            $foreground = Get-ScaledIcon $transparent ([int](108 * $density.Value)) 0.55
            try {
                $launcher.Save((Join-Path $launcherDirectory 'ic_launcher.png'), [System.Drawing.Imaging.ImageFormat]::Png)
                $foreground.Save((Join-Path $foregroundDirectory 'ic_launcher_foreground.png'), [System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $launcher.Dispose(); $foreground.Dispose() }
        }
        $frames = foreach ($size in $iconSizes) {
            $bitmap = Get-ScaledIcon $transparent $size
            $stream = [IO.MemoryStream]::new()
            try { $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png); ,$stream.ToArray() }
            finally { $bitmap.Dispose(); $stream.Dispose() }
        }
        $iconStream = [IO.File]::Create($windowsIcon)
        $writer = [IO.BinaryWriter]::new($iconStream)
        try {
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$iconSizes.Count)
            $frameOffset = 6 + 16 * $iconSizes.Count
            for ($index = 0; $index -lt $iconSizes.Count; $index++) {
                $storedSize = if ($iconSizes[$index] -eq 256) { 0 } else { $iconSizes[$index] }
                $writer.Write([byte]$storedSize); $writer.Write([byte]$storedSize)
                $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
                $writer.Write([uint32]$frames[$index].Length); $writer.Write([uint32]$frameOffset)
                $frameOffset += $frames[$index].Length
            }
            foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
        } finally { $writer.Dispose(); $iconStream.Dispose() }
    } finally { $cream.Dispose(); $transparent.Dispose() }
}

foreach ($density in $densities.GetEnumerator()) {
    foreach ($kind in @('launcher','foreground')) {
        $relative = if ($kind -eq 'launcher') { 'mipmap-' + $density.Key + '/ic_launcher.png' } else { 'drawable-' + $density.Key + '/ic_launcher_foreground.png' }
        $expectedSize = [int]($(if ($kind -eq 'launcher') { 48 } else { 108 }) * $density.Value)
        $image = [System.Drawing.Bitmap]::new((Join-Path $androidResources $relative))
        try {
            if ($image.Width -ne $expectedSize -or $image.Height -ne $expectedSize) { throw "图标尺寸不符：$relative" }
            if ($kind -eq 'foreground') {
                # 图形须留在自适应图标中心安全圆内；忽略插值产生的极淡像素。
                for ($row = 0; $row -lt $image.Height; $row++) {
                    for ($column = 0; $column -lt $image.Width; $column++) {
                        $distance = [Math]::Sqrt([Math]::Pow($column + 0.5 - $image.Width / 2, 2) + [Math]::Pow($row + 0.5 - $image.Height / 2, 2))
                        if ($distance -gt $image.Width * 33 / 108 -and $image.GetPixel($column,$row).A -gt 32) { throw "图形越过自适应安全区：$relative" }
                    }
                }
            }
        } finally { $image.Dispose() }
    }
}
$iconBytes = [IO.File]::ReadAllBytes($windowsIcon)
if ([BitConverter]::ToUInt16($iconBytes, 4) -ne $iconSizes.Count) { throw 'Windows图标尺寸数量不符' }
for ($index = 0; $index -lt $iconSizes.Count; $index++) {
    $storedSize = $iconBytes[6 + 16 * $index]
    $actualSize = if ($storedSize -eq 0) { 256 } else { $storedSize }
    if ($actualSize -ne $iconSizes[$index]) { throw 'Windows图标尺寸顺序不符' }
}
Write-Output '图标资源门通过：Android五密度、安全圆与Windows七尺寸。'
