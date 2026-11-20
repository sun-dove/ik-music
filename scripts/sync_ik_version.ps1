param([switch]$Check)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = Get-Content -Raw -LiteralPath (Join-Path $root 'ik-version.json') | ConvertFrom-Json
if ($version.version -notmatch '^\d+\.\d+\.\d+$' -or $version.build -lt 1) { throw '独立版本清单无效' }
$number = $version.version.Replace('.', ',') + ',' + $version.build
$files = @{
    'lib/video_app/ik/ik_version.dart' = "// 由 scripts/sync_ik_version.ps1 生成，版本源为 ik-version.json。`nabstract final class IkVersion {`n  static const name = '$($version.name)';`n  static const version = '$($version.version)';`n  static const build = $($version.build);`n  static const label = '$($version.name) · $($version.version)';`n}`n"
    'windows/runner/ik_version.h' = "// 由独立版本清单生成。`n#define IK_VERSION_NUMBER $number`n#define IK_VERSION_STRING `"$($version.version)`"`n#define IK_APP_NAME `"$($version.name)`"`n"
    'installer/ik_version.iss' = "; 由独立版本清单生成。`n#define MyAppName `"$($version.name)`"`n#define MyAppVersion `"$($version.version)`"`n"
}
foreach ($entry in $files.GetEnumerator()) {
    $path = Join-Path $root $entry.Key
    if ($Check) {
        if (-not (Test-Path -LiteralPath $path) -or [IO.File]::ReadAllText($path).Replace("`r`n", "`n") -ne $entry.Value) { throw "独立版本未同步：$($entry.Key)" }
    } else { [IO.File]::WriteAllText($path, $entry.Value, [Text.UTF8Encoding]::new($false)) }
}
Write-Output "独立版本：$($version.name) $($version.version) / $($version.build)"
