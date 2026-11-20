param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ik_install_migration.ps1') -FunctionsOnly
$bundleRoot = [IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\', '/')
if ([IO.Path]::GetFullPath($OutputPath).StartsWith($bundleRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '发行清单放在包目录外，避免清单自引用。' }
Assert-IkProductIdentity $bundleRoot
$files = @(Get-IkTreeManifest $bundleRoot)
foreach ($required in @('yueyin_music.exe','ik.ico','flutter_windows.dll','libmpv-2.dll','data\app.so','data\icudtl.dat','data\flutter_assets\AssetManifest.bin','LICENSE','NOTICE.md')) {
    if ($required -notin $files.path) { throw "发行目录缺少必要运行时或许可：$required" }
}
if (@($files | Where-Object { $_.path -match '(^|[\\/])(unins\d+\.(exe|dat)|\.git|\.dart_tool|node_modules)([\\/]|$)|\.(pdb|ilk|exp|lib)$' }).Count) { throw '发行目录包含卸载遗留或开发产物。' }
$version = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'ik-version.json') -Raw | ConvertFrom-Json
$exeVersion = (Get-Item -LiteralPath (Join-Path $bundleRoot 'yueyin_music.exe')).VersionInfo
$fixedVersion = "$($exeVersion.FileMajorPart).$($exeVersion.FileMinorPart).$($exeVersion.FileBuildPart).$($exeVersion.FilePrivatePart)"
if ($exeVersion.FileDescription -ne $version.name -or $fixedVersion -ne "$($version.version).$($version.build)") { throw '发行EXE的显示名称或固定版本与当前独立版本清单不一致，拒绝把旧包标成新版本。' }
$manifest = [ordered]@{ appId='{54A778C9-2261-4E1F-BA89-EE68844DA7AA}'; productName='YueyinMusic'; displayName=$version.name; version=$version.version; build=$version.build; files=$files }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Write-Output "发行清单：$($files.Count) 文件，$(([long]($files | Measure-Object length -Sum).Sum)) 字节。"
