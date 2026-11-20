param(
    [string]$FlutterSdk,
    [string]$AndroidSdk,
    [string]$Jdk = 'D:/Applications/Java/jdk-17',
    [string]$SigningProperties,
    [string]$ToolchainsRoot,
    [string]$BuildDirectory,
    [switch]$Compact,
    [switch]$EnableSpatialAudio,
    [string]$Python = 'python',
    [string]$SqliteBinaryDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'sync_ik_version.ps1') -Check
$version = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'ik-version.json') | ConvertFrom-Json
$taskRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
if (-not $ToolchainsRoot) { $ToolchainsRoot = Join-Path $taskRoot 'work/toolchains' }
if (-not $FlutterSdk) { $FlutterSdk = Join-Path $toolchainsRoot 'flutter' }
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $toolchainsRoot 'android-sdk' }
if (-not $SigningProperties) { $SigningProperties = Join-Path $taskRoot 'work/signing/video-music-signing.properties' }
if (-not (Test-Path -LiteralPath $SigningProperties)) { throw '缺少视频同款应用的稳定签名配置' }

$env:JAVA_HOME = $Jdk
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:ANDROID_USER_HOME = Join-Path $toolchainsRoot 'android-user'
$env:ANDROID_AVD_HOME = Join-Path $toolchainsRoot 'avd'
$env:GRADLE_USER_HOME = Join-Path $toolchainsRoot 'gradle-home'
$env:PUB_CACHE = Join-Path $toolchainsRoot 'pub-cache'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:FLUTTER_ROOT = $FlutterSdk
$env:VIDEO_MUSIC_BUILD = '1'
$env:VIDEO_MUSIC_SIGNING_PROPERTIES = $SigningProperties
$env:PATH = (Join-Path $Jdk 'bin') + ';' + (Join-Path $FlutterSdk 'bin') + ';' + $env:PATH
$gradleInitDirectory = Join-Path $env:GRADLE_USER_HOME 'init.d'
New-Item -ItemType Directory -Path $gradleInitDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'video-mirrors.gradle') -Destination (Join-Path $gradleInitDirectory 'video-mirrors.gradle') -Force
$gradlePropertiesPath = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$gradleProperties = if (Test-Path -LiteralPath $gradlePropertiesPath) { @(Get-Content -LiteralPath $gradlePropertiesPath) } else { @() }
if (-not ($gradleProperties -match '^org\.gradle\.jvmargs=')) {
    $gradleProperties += 'org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError'
    $gradleProperties += 'org.gradle.workers.max=2'
}
$distributionUri = [uri]'https://services.gradle.org'
$proxy = [Net.WebRequest]::DefaultWebProxy
if ($proxy -and -not $proxy.IsBypassed($distributionUri)) {
    $proxyUri = $proxy.GetProxy($distributionUri)
    if (-not $proxyUri.UserInfo) {
        foreach ($protocol in @('http', 'https')) {
            $hostKey = 'systemProp.' + $protocol + '.proxyHost='
            $portKey = 'systemProp.' + $protocol + '.proxyPort='
            if (-not ($gradleProperties -match ('^' + [regex]::Escape($hostKey)))) { $gradleProperties += $hostKey + $proxyUri.DnsSafeHost }
            if (-not ($gradleProperties -match ('^' + [regex]::Escape($portKey)))) { $gradleProperties += $portKey + $proxyUri.Port }
        }
    }
}
[IO.File]::WriteAllLines($gradlePropertiesPath, $gradleProperties, [Text.Encoding]::ASCII)

$buildRoot = $projectRoot
if ($Compact -or $EnableSpatialAudio) {
    $prepareArguments = @{ FlutterSdk=$FlutterSdk; Platform='android'; FullDependencies=(-not $Compact); EnableSpatialAudio=$EnableSpatialAudio; Python=$Python }
    if ($BuildDirectory) { $prepareArguments.OutputDirectory=$BuildDirectory }
    $buildRoot = & (Join-Path $PSScriptRoot 'prepare_ik_build.ps1') @prepareArguments
    if ($Compact) { & (Join-Path $PSScriptRoot 'verify_ik_build_profile.ps1') -BuildDirectory $buildRoot }
} elseif ($BuildDirectory) { throw '-BuildDirectory 仅用于 -Compact 或 -EnableSpatialAudio 隔离构建。' }
if ($SqliteBinaryDirectory) {
    if (-not ($Compact -or $EnableSpatialAudio)) { throw 'SQLite离线配置只能用于隔离构建副本。' }
    & (Join-Path $PSScriptRoot 'prepare_ik_sqlite_offline.ps1') -BuildDirectory $buildRoot -BinaryDirectory $SqliteBinaryDirectory
}
Push-Location $buildRoot
try {
    $dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
    $toolPackages = Join-Path $FlutterSdk 'packages/flutter_tools/.dart_tool/package_config.json'
    & $dart "--packages=$toolPackages" (Join-Path $PSScriptRoot 'generate_android_plugins.dart') $buildRoot
    if ($LASTEXITCODE -ne 0) { throw 'Android 插件注册器生成失败' }
    if ($Compact) {
        & (Join-Path $FlutterSdk 'bin/flutter.bat') test --no-pub -j 1 test/video_qq_qr_status_test.dart test/video_qq_qr_fetch_test.dart test/video_auth_state_test.dart test/kugou_login_page_test.dart test/platform_playlists_page_test.dart
        if ($LASTEXITCODE -ne 0) { throw '精简构建登录/二维码显示门失败。' }
    }
    & (Join-Path $FlutterSdk 'bin/flutter.bat') build apk --release --split-per-abi --no-pub --target lib/main_video.dart --build-name $version.version --build-number $version.build
    if ($LASTEXITCODE -ne 0) { throw "IK Music APK 构建失败，退出码 $LASTEXITCODE" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $release = Join-Path $projectRoot 'build/yueyin-release'
    New-Item -ItemType Directory -Path $release -Force | Out-Null
    foreach ($abi in @('arm64-v8a','armeabi-v7a','x86_64')) {
        $apk = Join-Path $buildRoot "build/app/outputs/flutter-apk/app-$abi-release.apk"
        if (-not (Test-Path -LiteralPath $apk)) { throw "缺少ABI分包：$abi" }
        $zip = [IO.Compression.ZipFile]::OpenRead($apk)
        try {
            if ($Compact -and @($zip.Entries | Where-Object { $_.FullName -match 'libbarhopper|barcode_ui|mobile_scanner' }).Count) { throw "精简APK仍含扫码原生依赖：$abi" }
        } finally { $zip.Dispose() }
        Copy-Item -LiteralPath $apk -Destination (Join-Path $release "ik-$($version.version)-$abi.apk") -Force
    }
    Get-ChildItem -LiteralPath $release -Filter "ik-$($version.version)-*.apk" -File | Get-FileHash -Algorithm SHA256 | Select-Object Hash,Path
} finally {
    Pop-Location
}
