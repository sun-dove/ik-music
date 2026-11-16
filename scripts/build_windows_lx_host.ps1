param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$DependencyDirectory
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$version = '1.0.2903.40'
$packageRoot = Join-Path $DependencyDirectory "webview2-$version"
$packageFile = Join-Path $DependencyDirectory "webview2-$version.zip"
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '需要.NET Framework 4.6.2或更高版本的编译器。' }
New-Item -ItemType Directory -Path $DependencyDirectory, $OutputDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $packageRoot)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$version/microsoft.web.webview2.$version.nupkg" -OutFile $packageFile
    Expand-Archive -LiteralPath $packageFile -DestinationPath $packageRoot
}
$core = Join-Path $packageRoot 'lib/net462/Microsoft.Web.WebView2.Core.dll'
$forms = Join-Path $packageRoot 'lib/net462/Microsoft.Web.WebView2.WinForms.dll'
$native = Join-Path $packageRoot 'runtimes/win-x64/native/WebView2Loader.dll'
foreach ($file in @($core, $forms, $native)) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'WebView2依赖的微软数字签名未通过。' }
    Copy-Item -LiteralPath $file -Destination $OutputDirectory -Force
}
Get-ChildItem -LiteralPath $packageRoot -File | Where-Object { $_.Name -match 'LICENSE|NOTICE' } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $OutputDirectory -Force
}
$source = Join-Path $projectRoot 'windows/lx_host/YueyinLxHost.cs'
$output = Join-Path $OutputDirectory 'YueyinLxHost.exe'
& $compiler /nologo /target:exe /platform:x64 /optimize+ /utf8output "/out:$output" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/reference:$core" "/reference:$forms" $source
if ($LASTEXITCODE -ne 0) { throw 'Windows音源宿主编译失败。' }
Write-Output 'Windows独立音源宿主已编译；仍需通过原生隔离门。'
