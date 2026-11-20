param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [Parameter(Mandatory = $true)][ValidateSet('android','windows')][string]$Platform,
    [string]$OutputDirectory,
    [switch]$FullDependencies,
    [switch]$EnableSpatialAudio,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $sourceRoot ('build/ik-isolated/' + $Platform + '-' + [Guid]::NewGuid().ToString('N')) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw '隔离构建目录必须尚不存在，避免混入前次产物。' }
$sourceLockHash = (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'pubspec.lock') -Algorithm SHA256).Hash
$sourceSpecHash = (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'pubspec.yaml') -Algorithm SHA256).Hash
if (-not $FullDependencies) {
    $references = Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'lib') -Filter '*.dart' -File -Recurse | Select-String -Pattern 'package:mobile_scanner/|MobileScanner|assets/branding/yueyin/note-ribbons\.png'
    if ($references) { throw '产品已出现待裁依赖/资源的引用，停止精简；请先复核功能或使用 -FullDependencies。' }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
foreach ($directory in @('lib','assets','test','integration_test','scripts','installer','native',$Platform)) {
    $source = Join-Path $sourceRoot $directory
    if (-not (Test-Path -LiteralPath $source)) { continue }
    & robocopy.exe $source (Join-Path $OutputDirectory $directory) /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NP /XJ /XD build .gradle .dart_tool ephemeral .plugin_symlinks /XF local.properties | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "隔离构建复制失败：$directory" }
}
foreach ($directory in @('docs/交付文档','design/platform-icons-010')) {
    $source = Join-Path $sourceRoot $directory
    if (-not (Test-Path -LiteralPath $source)) { continue }
    & robocopy.exe $source (Join-Path $OutputDirectory $directory) /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NP /XJ | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "隔离构建复制失败：$directory" }
}
foreach ($file in @('pubspec.yaml','pubspec.lock','analysis_options.yaml','l10n.yaml','ik-version.json','LICENSE','NOTICE.md','README.md')) {
    $source = Join-Path $sourceRoot $file
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $OutputDirectory $file) }
}
if ($EnableSpatialAudio -and $Platform -eq 'android') {
    $sourcePackages = Get-Content -LiteralPath (Join-Path $sourceRoot '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
    $audioPackage = $sourcePackages.packages | Where-Object { $_.name -eq 'just_audio' }
    if (-not $audioPackage -or -not ([uri]$audioPackage.rootUri).IsFile) { throw '请先解析完整项目依赖，以定位固定 just_audio 包。' }
    $audioSource = ([uri]$audioPackage.rootUri).LocalPath
    $audioCopy = Join-Path $OutputDirectory '.ik-packages/just_audio'
    & robocopy.exe $audioSource $audioCopy /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NP /XJ /XD build .gradle .dart_tool | Out-Null
    if ($LASTEXITCODE -ge 8) { throw 'just_audio 隔离副本复制失败。' }
    & $Python (Join-Path $sourceRoot 'native/ik_spatial/prepare_android.py') --package-dir $audioCopy | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Android HRTF PCM 适配失败。' }
    $audioLicense = Join-Path $audioCopy 'LICENSE'
    $licenseText = [IO.File]::ReadAllText($audioLicense)
    $hrtfLicense = [IO.File]::ReadAllText((Join-Path $sourceRoot 'native/ik_spatial/data/MIT-KEMAR-LICENSE'))
    $licenseText += "`n`nMIT KEMAR HRTF data — Bill Gardner / Keith Martin, MIT Media Lab, 1994`n`n" + $hrtfLicense
    [IO.File]::WriteAllText($audioLicense, $licenseText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'pubspec_overrides.yaml'), "dependency_overrides:`n  just_audio:`n    path: .ik-packages/just_audio`n", [Text.UTF8Encoding]::new($false))
}
$excluded = @()
if (-not $FullDependencies) {
    $specPath = Join-Path $OutputDirectory 'pubspec.yaml'
    $spec = [IO.File]::ReadAllText($specPath)
    if ($spec -notmatch '(?m)^  mobile_scanner:') { throw '预期依赖声明已变化，请先复核精简规则。' }
    $spec = [regex]::Replace($spec, '(?m)^  mobile_scanner:[^\r\n]*\r?\n', '')
    $spec = [regex]::Replace($spec, '(?m)^    - assets/branding/yueyin/note-ribbons\.png\r?\n', '')
    [IO.File]::WriteAllText($specPath, $spec, [Text.UTF8Encoding]::new($false))
    $excluded = @('mobile_scanner','assets/branding/yueyin/note-ribbons.png')
}
Push-Location $OutputDirectory
try {
    & (Join-Path $FlutterSdk 'bin/flutter.bat') pub get --offline | Out-Host
    if ($LASTEXITCODE -ne 0) { throw '隔离副本离线依赖解析失败；先在完整项目正常获取固定依赖。' }
    $packageConfig = Get-Content -LiteralPath '.dart_tool/package_config.json' -Raw | ConvertFrom-Json
    if (-not $FullDependencies -and 'mobile_scanner' -in $packageConfig.packages.name) { throw '未使用扫码依赖仍存在于隔离依赖图。' }
    if ('qr_flutter' -notin $packageConfig.packages.name) { throw '登录/分享用二维码显示依赖不能移除。' }
    $originalLock = [IO.File]::ReadAllText((Join-Path $sourceRoot 'pubspec.lock'))
    $isolatedLock = [IO.File]::ReadAllText((Join-Path $OutputDirectory 'pubspec.lock'))
    $versionPattern = '(?ms)^  ([a-zA-Z0-9_]+):\r?\n(?:(?!^  [a-zA-Z0-9_]+:).)*?^    version: "([^"]+)"'
    $originalVersions = @{}
    foreach ($entry in [regex]::Matches($originalLock, $versionPattern)) { $originalVersions[$entry.Groups[1].Value] = $entry.Groups[2].Value }
    foreach ($entry in [regex]::Matches($isolatedLock, $versionPattern)) {
        if ($originalVersions[$entry.Groups[1].Value] -ne $entry.Groups[2].Value) { throw "隔离依赖解析发生非预期版本变化：$($entry.Groups[1].Value)" }
    }
} finally { Pop-Location }
if ((Get-FileHash -LiteralPath (Join-Path $sourceRoot 'pubspec.lock') -Algorithm SHA256).Hash -ne $sourceLockHash -or (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'pubspec.yaml') -Algorithm SHA256).Hash -ne $sourceSpecHash) { throw '共享依赖文件在准备期间发生变化，请检查并重新准备。' }
$record = [ordered]@{ sourceRoot=$sourceRoot; buildRoot=$OutputDirectory; platform=$Platform; excluded=$excluded; spatialAudio=[bool]$EnableSpatialAudio; sharedLockSha256=$sourceLockHash; sharedSpecSha256=$sourceSpecHash; generatedAt=[DateTime]::UtcNow.ToString('o') }
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'ik-build-profile.json'), ($record | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Write-Output $OutputDirectory
