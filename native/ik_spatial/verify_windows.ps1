param(
    [Parameter(Mandatory=$true)][string]$LibraryPath,
    [string]$Python = 'python',
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PSScriptRoot ('gate-output/' + [Guid]::NewGuid().ToString('N'))
}
$LibraryPath = (Resolve-Path -LiteralPath $LibraryPath).Path
& $Python (Join-Path $PSScriptRoot 'verify_mpv.py') --dll $LibraryPath --output-dir $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'U07 发行 DLL 真实 PCM 门失败，禁止打包。' }
