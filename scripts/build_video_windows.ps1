param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [Parameter(Mandatory = $true)][string]$DependencyDirectory,
    [string]$InnoCompiler = 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe',
    [string]$BuildDirectory,
    [switch]$Compact,
    [string]$SqliteBinaryDirectory,
    [string]$SpatialAudioDll,
    [string]$SpatialAudioSha256,
    [string]$SpatialAudioLicenses,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'sync_ik_version.ps1') -Check
$version = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'ik-version.json') | ConvertFrom-Json
$hostOutput = Join-Path $DependencyDirectory 'lx-host'
& (Join-Path $PSScriptRoot 'build_windows_lx_host.ps1') -OutputDirectory $hostOutput -DependencyDirectory $DependencyDirectory
$env:YUEYIN_SANDBOX_GATE = '1'
$env:YUEYIN_LX_HOST = Join-Path $hostOutput 'YueyinLxHost.exe'
$env:VIDEO_MUSIC_BUILD = '1'
& (Join-Path $PSScriptRoot 'ik_install_migration_gate.ps1')
$buildRoot = $projectRoot
if ($Compact) {
    $prepareArguments = @{ FlutterSdk=$FlutterSdk; Platform='windows' }
    if ($BuildDirectory) { $prepareArguments.OutputDirectory=$BuildDirectory }
    $buildRoot = & (Join-Path $PSScriptRoot 'prepare_ik_build.ps1') @prepareArguments
    & (Join-Path $PSScriptRoot 'verify_ik_build_profile.ps1') -BuildDirectory $buildRoot
} elseif ($BuildDirectory) { throw '-BuildDirectory 仅用于 -Compact 隔离构建。' }
if ($SqliteBinaryDirectory) {
    if (-not $Compact) { throw 'SQLite离线配置只能用于 -Compact 隔离副本。' }
    & (Join-Path $PSScriptRoot 'prepare_ik_sqlite_offline.ps1') -BuildDirectory $buildRoot -BinaryDirectory $SqliteBinaryDirectory
}
Push-Location $buildRoot
try {
    $flutter = Join-Path $FlutterSdk 'bin/flutter.bat'
    & $flutter test --no-pub -j 1 test/video_windows_sandbox_test.dart test/windows_music_native_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Windows音源原生门未通过，停止打包。' }
    & $flutter build windows --release --no-pub --target lib/main_video.dart --build-name $version.version --build-number $version.build
    if ($LASTEXITCODE -ne 0) { throw 'IK Music Windows主程序构建失败。' }
    $cmake = (Get-Command cmake -ErrorAction Stop).Source
    & $cmake --build (Join-Path $buildRoot 'build/windows/x64') --config Release --target yueyin_desktop_red_gate yueyin_desktop_gate ik_desktop_red_gate ik_desktop_gate
    if ($LASTEXITCODE -ne 0) { throw 'Windows窗口与字体原生门编译失败。' }
    # Windows PowerShell 5 将原生 stderr 包装为错误记录；红门预期失败，单独读取退出码。
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & (Join-Path $buildRoot 'build/windows/x64/desktop-gate/yueyin_desktop_red_gate.exe')
        $redExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    if ($redExitCode -ne 1) { throw '原生红门必须以断言失败退出，验收无效。' }
    Write-Output '原生红门已确认：停用新关闭处理器不能满足最小化交互。'
    & (Join-Path $buildRoot 'build/windows/x64/desktop-gate/yueyin_desktop_gate.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Windows窗口与字体原生门未通过，停止发行。' }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & (Join-Path $buildRoot 'build/windows/x64/desktop-gate/ik_desktop_red_gate.exe')
        $redExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    if ($redExitCode -ne 1) { throw 'ik 桌面红门必须以断言失败退出。' }
    & (Join-Path $buildRoot 'build/windows/x64/desktop-gate/ik_desktop_gate.exe')
    if ($LASTEXITCODE -ne 0) { throw 'ik 托盘、窗口与媒体原生门未通过。' }
    $compiledBundle = Join-Path $buildRoot 'build/windows/x64/runner/Release'
    $bundle = Join-Path $buildRoot ('build/ik-bundles/' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $bundle -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $compiledBundle -File) {
        if ($file.Extension -eq '.dll' -or $file.Name -eq 'yueyin_music.exe') { Copy-Item -LiteralPath $file.FullName -Destination $bundle }
    }
    Copy-Item -LiteralPath (Join-Path $compiledBundle 'data') -Destination (Join-Path $bundle 'data') -Recurse
    if ($SpatialAudioDll) {
        . (Join-Path $PSScriptRoot 'ik_install_migration.ps1') -FunctionsOnly
        Assert-IkFileHash $SpatialAudioDll $SpatialAudioSha256
        & (Join-Path $PSScriptRoot 'copy_ik_audio_licenses.ps1') -LicenseDirectory $SpatialAudioLicenses -BundleDirectory $bundle -SpatialAudioSha256 $SpatialAudioSha256
        $spatialGate = Join-Path $projectRoot 'native/ik_spatial/verify_windows.ps1'
        if (-not (Test-Path -LiteralPath $spatialGate)) { throw '尚无正式Windows HRTF信号门，拒绝把未验DLL放入发行包。' }
        & $spatialGate -LibraryPath $SpatialAudioDll -Python $Python -OutputDirectory (Join-Path $DependencyDirectory ('spatial-gate/' + [Guid]::NewGuid().ToString('N')))
        if (-not $?) { throw 'Windows HRTF实际信号门未通过。' }
        Copy-Item -LiteralPath $SpatialAudioDll -Destination (Join-Path $bundle 'libmpv-2.dll') -Force
    } elseif ($SpatialAudioSha256 -or $SpatialAudioLicenses) { throw '指定SpatialAudioSha256或SpatialAudioLicenses时必须同时指定SpatialAudioDll。' }
    foreach ($required in @('yueyin_music.exe', 'flutter_windows.dll', 'data/flutter_assets/AssetManifest.bin')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $required))) { throw "Windows产物缺少 $required" }
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'windows/runner/resources/yueyin_icon.ico') -Destination (Join-Path $bundle 'ik.ico') -Force
    $hostDestination = Join-Path $bundle 'data/lx-host'
    New-Item -ItemType Directory -Path $hostDestination -Force | Out-Null
    Get-ChildItem -LiteralPath $hostOutput -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $hostDestination -Force }
    foreach ($license in @('LICENSE', 'NOTICE.md')) {
        if (Test-Path -LiteralPath (Join-Path $projectRoot $license)) { Copy-Item -LiteralPath (Join-Path $projectRoot $license) -Destination $bundle -Force }
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/交付文档/ik 061 使用与构建.md') -Destination (Join-Path $bundle 'ik 061 使用与构建.md') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'design/platform-icons-010/来源说明.md') -Destination (Join-Path $bundle '平台图标来源说明.md') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ik_install_migration.ps1') -Destination $bundle
    foreach ($dll in @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $hostDestination $dll)
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw "WebView2 SDK签名无效：$dll" }
    }
    $release = Join-Path $projectRoot 'build/yueyin-release'
    New-Item -ItemType Directory -Path $release -Force | Out-Null
    & (Join-Path $PSScriptRoot 'write_ik_bundle_manifest.ps1') -BundleDirectory $bundle -OutputPath (Join-Path $release "ik-$($version.version)-windows-manifest.json")
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath (Join-Path $release "ik-$($version.version)-windows-x64.zip") -Force
    if (Test-Path -LiteralPath $InnoCompiler) {
        $gateShell = (Get-Process -Id $PID).Path
        $previousErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $redOutput = @(& $gateShell -NoLogo -NoProfile -File (Join-Path $PSScriptRoot 'ik_installer_isolated_gate.ps1') -InnoCompiler $InnoCompiler -Baseline 2>&1)
            $redExitCode = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousErrorAction }
        $redOutput | Write-Output
        if ($redExitCode -ne 1 -or -not ($redOutput -match 'IK_INSTALLER_RED_CONFIRMED')) { throw '隔离Inno红门未按预期阻止先新装后卸旧。' }
        & (Join-Path $PSScriptRoot 'ik_installer_isolated_gate.ps1') -InnoCompiler $InnoCompiler
        & $InnoCompiler "/DMyAppSourceDir=$bundle" "/DMyOutputDir=$release" (Join-Path $projectRoot 'installer/yueyin.iss')
        if ($LASTEXITCODE -ne 0) { throw 'IK Music Windows安装器编译失败。' }
    } else { Write-Output '未找到Inno Setup，本次只生成完整便携ZIP。' }
    Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Extension -in @('.zip', '.exe') } | Get-FileHash -Algorithm SHA256 | Select-Object Hash,Path
} finally { Pop-Location }
