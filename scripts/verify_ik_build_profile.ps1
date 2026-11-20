param([Parameter(Mandatory = $true)][string]$BuildDirectory)
$ErrorActionPreference = 'Stop'
$spec = Get-Content -LiteralPath (Join-Path $BuildDirectory 'pubspec.yaml') -Raw
$packages = Get-Content -LiteralPath (Join-Path $BuildDirectory '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
if ($spec -match '(?m)^  mobile_scanner:' -or 'mobile_scanner' -in $packages.packages.name) { throw '精简门：未使用的扫码插件仍在依赖图中。' }
if ($spec -match '(?m)^    - assets/branding/yueyin/note-ribbons\.png') { throw '精简门：未使用的旧品牌图片仍在资源清单中。' }
foreach ($required in @('qr_flutter','media_kit','just_audio','audio_service','flutter_secure_storage','path_provider')) {
    if ($required -notin $packages.packages.name) { throw "精简门：必要依赖丢失：$required" }
}
$pluginsPath = Join-Path $BuildDirectory '.flutter-plugins-dependencies'
if (Test-Path -LiteralPath $pluginsPath) {
    $plugins = Get-Content -LiteralPath $pluginsPath -Raw | ConvertFrom-Json
    if ('mobile_scanner' -in $plugins.plugins.android.name) { throw '精简门：Android插件注册图仍含mobile_scanner。' }
}
Write-Output '精简构建门通过：扫码插件与未用旧图片已从正规清单移除，二维码显示/播放器/凭据/路径依赖保留。'
