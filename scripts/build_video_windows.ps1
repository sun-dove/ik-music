param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [Parameter(Mandatory = $true)][string]$DependencyDirectory,
    [string]$InnoCompiler = 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$hostOutput = Join-Path $DependencyDirectory 'lx-host'
& (Join-Path $PSScriptRoot 'build_windows_lx_host.ps1') -OutputDirectory $hostOutput -DependencyDirectory $DependencyDirectory
$env:YUEYIN_SANDBOX_GATE = '1'
$env:YUEYIN_LX_HOST = Join-Path $hostOutput 'YueyinLxHost.exe'
$env:VIDEO_MUSIC_BUILD = '1'
Push-Location $projectRoot
try {
    $flutter = Join-Path $FlutterSdk 'bin/flutter.bat'
    & $flutter test --no-pub -j 1 test/video_windows_sandbox_test.dart test/windows_music_native_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Windows音源原生门未通过，停止打包。' }
    & $flutter build windows --release --no-pub --target lib/main_video.dart --build-name 0.5.1 --build-number 9
    if ($LASTEXITCODE -ne 0) { throw '乐音Windows主程序构建失败。' }
    $cmake = (Get-Command cmake -ErrorAction Stop).Source
    & $cmake --build (Join-Path $projectRoot 'build/windows/x64') --config Release --target yueyin_desktop_red_gate yueyin_desktop_gate
    if ($LASTEXITCODE -ne 0) { throw 'Windows窗口与字体原生门编译失败。' }
    # Windows PowerShell 5 将原生 stderr 包装为错误记录；红门预期失败，单独读取退出码。
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & (Join-Path $projectRoot 'build/windows/x64/desktop-gate/yueyin_desktop_red_gate.exe')
        $redExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    if ($redExitCode -ne 1) { throw '原生红门必须以断言失败退出，验收无效。' }
    Write-Output '原生红门已确认：停用新关闭处理器不能满足最小化交互。'
    & (Join-Path $projectRoot 'build/windows/x64/desktop-gate/yueyin_desktop_gate.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Windows窗口与字体原生门未通过，停止发行。' }
    $bundle = Join-Path $projectRoot 'build/windows/x64/runner/Release'
    foreach ($required in @('yueyin_music.exe', 'flutter_windows.dll', 'data/flutter_assets/AssetManifest.bin')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $required))) { throw "Windows产物缺少 $required" }
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'windows/runner/resources/yueyin_icon.ico') -Destination (Join-Path $bundle 'yueyin_icon.ico') -Force
    $hostDestination = Join-Path $bundle 'data/lx-host'
    New-Item -ItemType Directory -Path $hostDestination -Force | Out-Null
    Get-ChildItem -LiteralPath $hostOutput -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $hostDestination -Force }
    foreach ($license in @('LICENSE', 'NOTICE.md')) {
        if (Test-Path -LiteralPath (Join-Path $projectRoot $license)) { Copy-Item -LiteralPath (Join-Path $projectRoot $license) -Destination $bundle -Force }
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/交付文档/DJ Music 051 Windows 使用与构建.md') -Destination (Join-Path $bundle 'DJ Music 051 Windows 使用与构建.md') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'design/platform-icons-010/来源说明.md') -Destination (Join-Path $bundle '平台图标来源说明.md') -Force
    $release = Join-Path $projectRoot 'build/yueyin-release'
    New-Item -ItemType Directory -Path $release -Force | Out-Null
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath (Join-Path $release 'DJ-Music-0.5.1-windows-x64.zip') -Force
    if (Test-Path -LiteralPath $InnoCompiler) {
        & $InnoCompiler (Join-Path $projectRoot 'installer/yueyin.iss')
        if ($LASTEXITCODE -ne 0) { throw '乐音Windows安装器编译失败。' }
    } else { Write-Output '未找到Inno Setup，本次只生成完整便携ZIP。' }
    Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Extension -in @('.zip', '.exe') } | Get-FileHash -Algorithm SHA256 | Select-Object Hash,Path
} finally { Pop-Location }
