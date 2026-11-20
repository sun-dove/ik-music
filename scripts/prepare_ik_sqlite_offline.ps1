param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [string]$BinaryDirectory
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $BuildDirectory 'ik-build-profile.json'))) { throw '离线SQLite配置仅允许已准备的隔离构建副本。' }
$packages = Get-Content -LiteralPath (Join-Path $BuildDirectory '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
$sqlite = $packages.packages | Where-Object { $_.name -eq 'sqlite3' }
if (-not $sqlite -or -not ([uri]$sqlite.rootUri).IsFile) { throw '未找到SQLite固定依赖。' }
$packageRoot = ([uri]$sqlite.rootUri).LocalPath
$hashFile = Get-Content -LiteralPath (Join-Path $packageRoot 'lib/src/hook/asset_hashes.dart') -Raw
$releaseMatch = [regex]::Match($hashFile, "releaseTag\s*=\s*'([^']+)'")
if (-not $releaseMatch.Success) { throw 'SQLite发行标签格式变化。' }
if (-not $BinaryDirectory) { $BinaryDirectory = Join-Path $BuildDirectory '.ik-native/sqlite3' }
$BinaryDirectory = [IO.Path]::GetFullPath($BinaryDirectory)
New-Item -ItemType Directory -Path $BinaryDirectory -Force | Out-Null
$binaries = @('sqlite3.x64.windows.dll','libsqlite3.arm.android.so','libsqlite3.arm64.android.so','libsqlite3.x64.android.so')
foreach ($name in $binaries) {
    $match = [regex]::Match($hashFile, "'" + [regex]::Escape($name) + "':\s*'([0-9a-f]{64})'")
    if (-not $match.Success) { throw "固定包未提供二进制SHA-256：$name" }
    $file = Join-Path $BinaryDirectory $name
    if (-not (Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $match.Groups[1].Value) {
        $uri = 'https://github.com/simolus3/sqlite3.dart/releases/download/' + $releaseMatch.Groups[1].Value + '/' + $name
        Invoke-WebRequest -Uri $uri -OutFile $file -UseBasicParsing -TimeoutSec 60
    }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $match.Groups[1].Value) { throw "SQLite官方文件校验失败：$name" }
}
$specPath = Join-Path $BuildDirectory 'pubspec.yaml'
$spec = [IO.File]::ReadAllText($specPath)
if ($spec -match '(?m)^hooks:') { throw '隔离副本已有hooks配置，拒绝覆盖。' }
$directoryYaml = ([uri]($BinaryDirectory.TrimEnd('\','/') + '\')).AbsoluteUri.Replace("'", "''")
$spec += "`nhooks:`n  user_defines:`n    sqlite3:`n      source: test-sqlite3`n      directory: '$directoryYaml'`n"
[IO.File]::WriteAllText($specPath, $spec, [Text.UTF8Encoding]::new($false))
Write-Output '隔离SQLite离线输入已配置：官方同版本二进制、固定SHA-256双重校验，未修改全局缓存。'
