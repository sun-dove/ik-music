param(
    [Parameter(Mandatory = $true)][string]$LicenseDirectory,
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$SpatialAudioSha256
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ik_install_migration.ps1') -FunctionsOnly
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $LicenseDirectory -PathType Container)) { throw 'HRTF DLL必须附完整的同次构建许可目录。' }
if ($SpatialAudioSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw '源码声明缺少DLL的固定SHA-256。' }
$licenses = @(Get-IkTreeManifest $LicenseDirectory)
$required = @(
    'ffmpeg-6.0-LICENSE.md','ffmpeg-6.0-COPYING.LGPLv2.1','ffmpeg-6.0-COPYING.LGPLv3',
    'ffmpeg-6.0-COPYING.GPLv2','ffmpeg-6.0-COPYING.GPLv3','freetype-VER-2-13-2-FTL.TXT',
    'fribidi-1.0.13-COPYING','harfbuzz-8.3.0-COPYING','libass-0.17.1-COPYING',
    'mpv-652a1dd907-Copyright','mpv-652a1dd907-LICENSE.GPL','mpv-652a1dd907-LICENSE.LGPL',
    'MIT-KEMAR-LICENSE','gcc-mingw-w64-x86-64-posix-copyright','mingw-w64-common-copyright','源码与构建说明.md'
)
foreach ($name in $required) {
    $entry = @($licenses | Where-Object { $_.path -ceq $name })
    if ($entry.Count -ne 1 -or $entry[0].length -le 0) { throw "音频运行时许可缺失或为空：$name" }
}
Assert-IkFileHash (Join-Path $LicenseDirectory 'MIT-KEMAR-LICENSE') (Get-FileHash -LiteralPath (Join-Path $root 'native/ik_spatial/data/MIT-KEMAR-LICENSE') -Algorithm SHA256).Hash
$destination = Join-Path $BundleDirectory 'third-party-audio-licenses'
if (Test-Path -LiteralPath $destination) { throw '音频许可目标已存在，拒绝混入旧版本许可。' }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($entry in $licenses) {
    $target = Get-IkManifestPath $destination $entry.path
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    Copy-Item -LiteralPath (Get-IkManifestPath $LicenseDirectory $entry.path) -Destination $target
}
if (-not (Test-IkManifestEqual $licenses @(Get-IkTreeManifest $destination))) { throw '音频许可复制后校验不一致。' }
$version = Get-Content -LiteralPath (Join-Path $root 'ik-version.json') -Raw | ConvertFrom-Json
$notice = @"
# IK Music 音频运行时对应源码

此包的 libmpv-2.dll SHA-256：$SpatialAudioSha256。

此文件夹保留 mpv、FFmpeg、FreeType、FriBidi、HarfBuzz、libass、GCC/MinGW 与 MIT KEMAR 数据许可。构建版本为 $($version.version) / $($version.build)。

对应源代码与构建修改以同次发行附件 ik-audio-sources.tar.gz 提供，包含固定上游源归档、HRTF 原始数据、修改源码与可重建脚本。请在与本安装包相同版本的发行页面下载：
https://github.com/sun-dove/yueyin-music/releases

具体固定提交、上游 URL、校验哈希、构建参数与重新链接说明见同目录“源码与构建说明.md”及源归档中的 native/ik_spatial/download_sources.py、build_windows.sh。发行者必须同时提供对应源码附件，CI 临时 artifact 不替代正式源码下载。
"@
[IO.File]::WriteAllText((Join-Path $destination '对应源码下载说明.md'), $notice, [Text.UTF8Encoding]::new($false))
Write-Output "音频许可已完整校验并复制：$($licenses.Count) 个源文件与对应源码下载声明。"
