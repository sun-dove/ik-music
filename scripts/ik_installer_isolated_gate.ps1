param(
    [string]$InnoCompiler = 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe',
    [string]$GateDirectory,
    [switch]$Baseline
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) { throw '需要 Inno Setup 编译器；未执行任何安装/卸载。' }
if (-not $GateDirectory) { $GateDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ik-installer-gate-' + [Guid]::NewGuid().ToString('N')) }
$GateDirectory = [IO.Path]::GetFullPath($GateDirectory).TrimEnd('\', '/')
if (Test-Path -LiteralPath $GateDirectory) { throw '隔离安装门目录必须尚不存在。' }
. (Join-Path $PSScriptRoot 'ik_install_migration.ps1') -FunctionsOnly
Assert-IkNoReparsePoint $GateDirectory
$gateId = [Guid]::NewGuid().ToString().ToUpperInvariant()
$gateName = 'IK Music 安装门 ' + $gateId.Substring(0,8)
$registrationKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{$gateId}_is1"
$fixture = Join-Path $GateDirectory 'fixture'
$buildOutput = Join-Path $GateDirectory 'compiled'
$oldDirectory = Join-Path $GateDirectory 'YueyinMusic'
$newDirectory = Join-Path $GateDirectory 'ik-music'
New-Item -ItemType Directory -Path $fixture, $buildOutput -Force | Out-Null
$fixtureSource = Join-Path $GateDirectory 'Fixture.cs'
$fixtureCode = @'
using System.Reflection;
[assembly: AssemblyCompany("sun-dove")]
[assembly: AssemblyProduct("YueyinMusic")]
[assembly: AssemblyTitle("IK Music isolated installer gate")]
public static class Fixture { public static void Main() {} }
'@
[IO.File]::WriteAllText($fixtureSource, $fixtureCode, [Text.UTF8Encoding]::new($true))
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:winexe "/out:$(Join-Path $fixture 'yueyin_music.exe')" $fixtureSource
if ($LASTEXITCODE -ne 0) { throw '隔离样例编译失败。' }
Copy-Item -LiteralPath (Join-Path $root 'windows/runner/resources/yueyin_icon.ico') -Destination (Join-Path $fixture 'ik.ico')
& $InnoCompiler "/DMyAppSourceDir=$fixture" "/DMyOutputDir=$buildOutput" "/DMyAppId=$gateId" "/DGateAppName=$gateName" (Join-Path $root 'installer/yueyin.iss') | Out-Host
if ($LASTEXITCODE -ne 0) { throw '隔离安装器编译失败。' }
$installer = @(Get-ChildItem -LiteralPath $buildOutput -Filter '*.exe' -File)
if ($installer.Count -ne 1) { throw '隔离安装器产物数不为1。' }
$installerPath = $installer[0].FullName
function Read-GateDirectory {
    if (-not (Test-Path -LiteralPath $registrationKey)) { return $null }
    return [IO.Path]::GetFullPath((Get-ItemProperty -LiteralPath $registrationKey).InstallLocation).TrimEnd('\', '/')
}
function Assert-GateInstalled([string]$Expected) {
    if ((Read-GateDirectory) -ne $Expected -or -not (Test-Path -LiteralPath (Join-Path $Expected 'yueyin_music.exe'))) { throw '隔离安装落点或登记不一致。' }
    $linkPath = Join-Path ([Environment]::GetFolderPath('Programs')) ($gateName + '/' + $gateName + '.lnk')
    if (-not (Test-Path -LiteralPath $linkPath)) { throw '隔离开始菜单入口缺失。' }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($linkPath)
    # ShellLink会展开TargetPath中的8.3短目录；CI的TEMP本身可能仍是RUNNER~1。
    $iconParts = [regex]::Match($shortcut.IconLocation, '^(.*),\s*0$')
    if (-not $iconParts.Success -or
        (Get-Item -LiteralPath $shortcut.TargetPath).FullName -ne (Get-Item -LiteralPath (Join-Path $Expected 'yueyin_music.exe')).FullName -or
        (Get-Item -LiteralPath $shortcut.WorkingDirectory).FullName -ne (Get-Item -LiteralPath $Expected).FullName -or
        (Get-Item -LiteralPath $iconParts.Groups[1].Value).FullName -ne (Get-Item -LiteralPath (Join-Path $Expected 'ik.ico')).FullName) {
        throw "快捷方式目标、图标或工作目录错误：预期=$Expected；目标=$($shortcut.TargetPath)；工作目录=$($shortcut.WorkingDirectory)；图标=$($shortcut.IconLocation)"
    }
}
function Invoke-GateUninstall {
    $installedDirectory = Read-GateDirectory
    if (-not $installedDirectory) { return }
    if ($installedDirectory -notin @($oldDirectory, $newDirectory)) { throw '隔离门注册位置越界，拒绝卸载。' }
    Assert-IkDirectoryPair $oldDirectory $newDirectory
    $exe = Join-Path $installedDirectory 'unins000.exe'
    Assert-IkNoReparsePoint $exe
    Invoke-IkInstallerProcess $exe @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + (Join-Path $GateDirectory 'uninstall.log') + '"'))
    if (Read-GateDirectory) { throw '隔离卸载登记未解除。' }
}
try {
    Invoke-IkInstallerProcess $installerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=',('/DIR="' + $oldDirectory + '"'))
    Assert-GateInstalled $oldDirectory
    # 普通升级保留旧自定义目录，单EXE可直接使用。
    Invoke-IkInstallerProcess $installerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=')
    Assert-GateInstalled $oldDirectory
    if ($Baseline) {
        # 错误顺序：旧登记仍在时先向新目录安装，必须返回失败。
        $blocked = $false
        try { Invoke-IkInstallerProcess $installerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=',('/DIR="' + $newDirectory + '"')) } catch { $blocked = $true }
        if ($blocked -and (Read-GateDirectory) -eq $oldDirectory -and -not (Test-Path -LiteralPath (Join-Path $newDirectory 'yueyin_music.exe'))) {
            Write-Output 'IK_INSTALLER_RED_CONFIRMED：旧登记仍在时跨目录安装被拒绝，旧安装保持。'
            exit 1
        }
        Write-Output '红门无效：错误的跨目录安装竟然通过。'
        return
    }
    $rejected = $false
    try { Invoke-IkInstallerProcess $installerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=',('/DIR="' + $newDirectory + '"')) } catch { $rejected = $true }
    if (-not $rejected -or (Read-GateDirectory) -ne $oldDirectory -or (Test-Path -LiteralPath (Join-Path $newDirectory 'yueyin_music.exe'))) { throw '未经迁移流程的跨目录覆盖未被阻止。' }
    $protectedFile = Join-Path $oldDirectory '用户保留音乐.mp3'
    [IO.File]::WriteAllBytes($protectedFile, [byte[]](1,2,3,4,5))
    $protectedHash = (Get-FileHash -LiteralPath $protectedFile -Algorithm SHA256).Hash
    Invoke-GateUninstall
    if ((Get-FileHash -LiteralPath $protectedFile -Algorithm SHA256).Hash -ne $protectedHash) { throw '旧卸载损坏未登记内容。' }
    Invoke-IkInstallerProcess $installerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=',('/DIR="' + $newDirectory + '"'))
    Assert-GateInstalled $newDirectory
    Invoke-IkInstallerProcess $installerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=')
    Assert-GateInstalled $newDirectory
    Invoke-GateUninstall
    if ((Get-FileHash -LiteralPath $protectedFile -Algorithm SHA256).Hash -ne $protectedHash) { throw '新卸载影响旧目录用户内容。' }
    Write-Output "真实 Inno 隔离门通过：同独立AppId先卸旧后装新、旧/新普通升级、快捷方式与未登记内容保留。材料目录：$GateDirectory"
} finally {
    Invoke-GateUninstall
}
