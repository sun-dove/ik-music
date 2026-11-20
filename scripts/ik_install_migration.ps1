param(
    [string]$InstallerPath,
    [string]$InstallerSha256,
    [string]$RollbackInstallerPath,
    [string]$RollbackInstallerSha256,
    [string]$BundleManifestPath,
    [string]$BundleManifestSha256,
    [string]$TargetDirectory,
    [switch]$Execute,
    [switch]$FunctionsOnly
)
$ErrorActionPreference = 'Stop'

function Get-IkInstallTarget {
    param([string]$PreviousDirectory, [string]$ProgramsDirectory)
    if (-not $PreviousDirectory) { return Join-Path $ProgramsDirectory 'ik-music' }
    $previous = [IO.Path]::GetFullPath($PreviousDirectory).TrimEnd('\', '/')
    if ([IO.Path]::GetFileName($previous) -eq 'YueyinMusic') {
        return Join-Path ([IO.Path]::GetDirectoryName($previous)) 'ik-music'
    }
    return $previous
}

function Assert-IkNoReparsePoint {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "拒绝重解析点路径：$current" }
        }
        $current = [IO.Path]::GetDirectoryName($current.TrimEnd('\', '/'))
    }
}

function Assert-IkDirectoryPair {
    param([string]$SourceDirectory, [string]$TargetDirectory)
    foreach ($path in @($SourceDirectory, $TargetDirectory)) {
        if (-not [IO.Path]::IsPathRooted($path)) { throw '安装路径必须为绝对路径。' }
        $full = [IO.Path]::GetFullPath($path).TrimEnd('\', '/')
        if ($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\', '/')) { throw '不能使用盘符根作为安装目录。' }
        foreach ($protected in @($env:WINDIR, $env:USERPROFILE, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:APPDATA, $env:LOCALAPPDATA)) {
            if ($protected -and $full.Equals($protected.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw "拒绝系统或用户根目录：$full" }
        }
        if ($env:WINDIR -and $full.StartsWith($env:WINDIR.TrimEnd('\','/') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '安装迁移不得使用Windows系统目录。' }
        if ($env:APPDATA) {
            $dataRoot = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'sun-dove/YueyinMusic')).TrimEnd('\','/')
            if ($full.Equals($dataRoot, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($dataRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $dataRoot.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '安装目录不能包含或进入稳定用户数据目录。' }
        }
        Assert-IkNoReparsePoint $full
    }
    $source = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath($TargetDirectory).TrimEnd('\', '/')
    if ($source.Equals($target, [StringComparison]::OrdinalIgnoreCase) -or
        $source.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $target.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '旧、新目录不能相同或互相包含。原地更新请直接运行安装器。' }
}

function Get-IkManifestPath {
    param([string]$RootDirectory, [string]$RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':') -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw '文件清单含越界路径。' }
    $root = [IO.Path]::GetFullPath($RootDirectory).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '文件清单未指向根目录内文件。' }
    Assert-IkNoReparsePoint $path
    return $path
}

function Get-IkTreeManifest {
    param([string]$RootDirectory)
    if (-not (Test-Path -LiteralPath $RootDirectory)) { return @() }
    Assert-IkNoReparsePoint $RootDirectory
    $root = [IO.Path]::GetFullPath($RootDirectory).TrimEnd('\', '/')
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($root)
    $entries = [Collections.Generic.List[object]]::new()
    while ($pending.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Dequeue() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "目录内存在重解析点，未读取或删除：$($item.FullName)" }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName); continue }
            $entries.Add([pscustomobject]@{ path=$item.FullName.Substring($root.Length + 1); length=$item.Length; sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash })
        }
    }
    return @($entries | Sort-Object path)
}

function Test-IkManifestEqual {
    param([object[]]$Before, [object[]]$After)
    $first = @($Before | Sort-Object path)
    $second = @($After | Sort-Object path)
    if ($first.Count -ne $second.Count) { return $false }
    for ($index = 0; $index -lt $first.Count; $index++) {
        if ($first[$index].path -cne $second[$index].path -or $first[$index].length -ne $second[$index].length -or $first[$index].sha256 -ne $second[$index].sha256) { return $false }
    }
    return $true
}

function Invoke-IkMigrationTransaction {
    param([hashtable]$Actions, [switch]$Baseline, [scriptblock]$OldInstallationRemoved)
    & $Actions.Snapshot
    if ($Baseline) {
        & $Actions.InstallNew
        & $Actions.UninstallOld
        & $Actions.Verify
        return
    }
    $oldRemoved = $false
    try {
        & $Actions.UninstallOld
        $oldRemoved = $true
        & $Actions.InstallNew
        & $Actions.Verify
    } catch {
        $failure = $_
        if (-not $oldRemoved -and $OldInstallationRemoved) { $oldRemoved = [bool](& $OldInstallationRemoved) }
        if (-not $oldRemoved) { throw $failure }
        try {
            & $Actions.UninstallFailedNew
            & $Actions.RestoreOld
        } catch { throw "新安装失败，回滚也未完成。保留快照与两份安装器。原错误：$failure；回滚错误：$_" }
        throw "新安装未通过，已恢复旧程序。用户数据保持原位。原因：$failure"
    }
}

function Assert-IkFileHash {
    param([string]$Path, [string]$Sha256)
    if (-not $Path -or $Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw '必须提供文件路径和预先核验的完整 SHA-256。' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "文件不存在：$Path" }
    Assert-IkNoReparsePoint $Path
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Sha256) { throw "文件校验失败：$Path" }
}

function Get-IkInstalledRegistration {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{54A778C9-2261-4E1F-BA89-EE68844DA7AA}_is1'
    if (-not (Test-Path -LiteralPath $key)) { return $null }
    return Get-ItemProperty -LiteralPath $key
}

function Assert-IkProductIdentity {
    param([string]$Directory)
    $exe = Join-Path $Directory 'yueyin_music.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "缺少已知产品入口：$exe" }
    $versionInfo = (Get-Item -LiteralPath $exe).VersionInfo
    if ($versionInfo.CompanyName -ne 'sun-dove' -or $versionInfo.ProductName -ne 'YueyinMusic' -or $versionInfo.OriginalFilename -ne 'yueyin_music.exe') { throw '现装内部身份无法核实，未执行卸载。' }
}

function Assert-IkStopped {
    param([string[]]$Directories)
    foreach ($process in Get-CimInstance Win32_Process -Filter "Name='yueyin_music.exe' OR Name='YueyinLxHost.exe'") {
        if (-not $process.ExecutablePath) { throw '存在无法核对路径的音乐进程，请先正常退出应用再迁移。' }
        foreach ($directory in $Directories) {
            if ($process.ExecutablePath.StartsWith($directory.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '请从托盘菜单正常退出 IK Music，等待播放记忆和音源宿主收尾后重试。当前未停止或强杀进程。' }
        }
    }
}

function Invoke-IkInstallerProcess {
    param([string]$Executable, [string[]]$Arguments)
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "安装/卸载进程返回 $($process.ExitCode)：$Executable" }
}

function Write-IkMigrationRecord {
    $migration.record.updatedAt = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $migration.root 'migration.json'), ($migration.record | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}

if ($FunctionsOnly) { return }
if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') { throw '此迁移脚本仅支持 Windows。' }
Assert-IkFileHash $InstallerPath $InstallerSha256
Assert-IkFileHash $RollbackInstallerPath $RollbackInstallerSha256
Assert-IkFileHash $BundleManifestPath $BundleManifestSha256
$registration = Get-IkInstalledRegistration
if (-not $registration) { throw '未发现同 AppId 的当前用户安装。首次安装请直接运行安装器。' }
$sourceDirectory = [IO.Path]::GetFullPath($registration.InstallLocation).TrimEnd('\', '/')
if (-not $TargetDirectory) { $TargetDirectory = Get-IkInstallTarget $sourceDirectory (Join-Path $env:LOCALAPPDATA 'Programs') }
$TargetDirectory = [IO.Path]::GetFullPath($TargetDirectory).TrimEnd('\', '/')
Assert-IkDirectoryPair $sourceDirectory $TargetDirectory
Assert-IkProductIdentity $sourceDirectory
if (Test-Path -LiteralPath $TargetDirectory) {
    if (@(Get-ChildItem -LiteralPath $TargetDirectory -Force).Count) { throw '目标目录已有内容，请使用空目录；本脚本不会覆盖未知文件。' }
}
$uninstaller = Join-Path $sourceDirectory 'unins000.exe'
$uninstallLog = Join-Path $sourceDirectory 'unins000.dat'
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf) -or -not (Test-Path -LiteralPath $uninstallLog -PathType Leaf)) { throw '旧安装缺少正式卸载器或卸载日志。' }
$registeredCommand = [string]$registration.UninstallString
if ($registeredCommand -notmatch ('^"?' + [regex]::Escape($uninstaller) + '"?(?:\s|$)')) { throw '卸载登记与已核验的产品目录不一致。' }
foreach ($packagePath in @($InstallerPath, $RollbackInstallerPath, $BundleManifestPath)) {
    $fullPackagePath = [IO.Path]::GetFullPath($packagePath)
    foreach ($directory in @($sourceDirectory, $TargetDirectory)) {
        if ($fullPackagePath.StartsWith($directory + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '安装器与回滚材料必须放在新、旧程序目录之外。' }
    }
}
$bundleManifest = Get-Content -LiteralPath $BundleManifestPath -Raw | ConvertFrom-Json
if ($bundleManifest.appId -ne '{54A778C9-2261-4E1F-BA89-EE68844DA7AA}' -or $bundleManifest.productName -ne 'YueyinMusic' -or -not $bundleManifest.files) { throw '发行清单产品身份无效。' }
foreach ($entry in $bundleManifest.files) { Get-IkManifestPath $TargetDirectory $entry.path | Out-Null }
foreach ($required in @('yueyin_music.exe','ik.ico','flutter_windows.dll','data\app.so')) {
    if ($required -notin @($bundleManifest.files.path | ForEach-Object { $_.Replace('/', '\') })) { throw "发行清单缺少：$required" }
}
Assert-IkStopped @($sourceDirectory, $TargetDirectory)
$dataDirectory = Join-Path $env:APPDATA 'sun-dove/YueyinMusic'
$dataManifest = @(Get-IkTreeManifest $dataDirectory)
$ownedFiles = @(Get-IkTreeManifest $sourceDirectory)
$bytesNeeded = [long](($bundleManifest.files | Measure-Object length -Sum).Sum) + 16777216
$drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($TargetDirectory))
if (-not $drive.IsReady -or $drive.AvailableFreeSpace -lt $bytesNeeded) { throw '目标磁盘未就绪或可用空间不足。' }
$backupBytes = [long](($dataManifest | Measure-Object length -Sum).Sum) + 16777216
$backupDrive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($env:LOCALAPPDATA))
if (-not $backupDrive.IsReady -or $backupDrive.AvailableFreeSpace -lt ($backupBytes + $(if ($backupDrive.Name -eq $drive.Name) { $bytesNeeded } else { 0 }))) { throw '用户数据保护性快照空间不足。' }
$plan = [ordered]@{
    appId='{54A778C9-2261-4E1F-BA89-EE68844DA7AA}'; sourceDirectory=$sourceDirectory; targetDirectory=$TargetDirectory
    dataDirectory=$dataDirectory; dataFiles=$dataManifest.Count; sourceFiles=$ownedFiles.Count
    order=@('正常退出','受保护快照','旧卸载','新安装','启动前核验'); cleanup='旧目录未登记内容全部保留，稍后精确清理'
}
if (-not $Execute) { [pscustomobject]$plan | ConvertTo-Json -Depth 4; return }

$migrationRoot = Join-Path $env:LOCALAPPDATA ('IKMusic/Migrations/' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
Assert-IkNoReparsePoint $migrationRoot
New-Item -ItemType Directory -Path $migrationRoot -Force | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($identity)
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @($identity, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
Set-Acl -LiteralPath $migrationRoot -AclObject $acl
$migration = @{
    root=$migrationRoot; dataBefore=$dataManifest; sourceBefore=$ownedFiles; oldRemoved=$false
    record=[ordered]@{ plan=$plan; phase='inspected'; updatedAt=''; installerSha256=$InstallerSha256; rollbackSha256=$RollbackInstallerSha256; sourceUninstallerSha256=(Get-FileHash -LiteralPath $uninstaller -Algorithm SHA256).Hash; sourceUninstallLogSha256=(Get-FileHash -LiteralPath $uninstallLog -Algorithm SHA256).Hash; dataBefore=$dataManifest; sourceBefore=$ownedFiles; remainingFiles=@() }
}
Write-IkMigrationRecord
$actions = @{
    Snapshot = {
        Assert-IkStopped @($sourceDirectory, $TargetDirectory)
        $backupRoot = Join-Path $migration.root 'user-data'
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        foreach ($entry in $migration.dataBefore) {
            $backupFile = Get-IkManifestPath $backupRoot $entry.path
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($backupFile)) -Force | Out-Null
            Copy-Item -LiteralPath (Get-IkManifestPath $dataDirectory $entry.path) -Destination $backupFile
        }
        if (-not (Test-IkManifestEqual $migration.dataBefore @(Get-IkTreeManifest $backupRoot))) { throw '数据快照校验失败。' }
        if (-not (Test-IkManifestEqual $migration.dataBefore @(Get-IkTreeManifest $dataDirectory))) { throw '快照期间数据发生变化，请正常退出程序后重试。' }
        $migration.record.phase = 'snapshotted'; Write-IkMigrationRecord
    }
    UninstallOld = {
        Assert-IkStopped @($sourceDirectory, $TargetDirectory)
        Assert-IkDirectoryPair $sourceDirectory $TargetDirectory
        Assert-IkFileHash $uninstaller $migration.record.sourceUninstallerSha256
        Assert-IkFileHash $uninstallLog $migration.record.sourceUninstallLogSha256
        $currentRegistration = Get-IkInstalledRegistration
        if (-not $currentRegistration -or [IO.Path]::GetFullPath($currentRegistration.InstallLocation).TrimEnd('\', '/') -ne $sourceDirectory) { throw '预检后现装登记发生变化，停止卸载。' }
        Invoke-IkInstallerProcess $uninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + (Join-Path $migration.root 'old-uninstall.log') + '"'))
        if (Get-IkInstalledRegistration) { throw '旧卸载返回后同 AppId 登记仍存在，已停止。' }
        $migration.oldRemoved = $true
        $migration.record.phase = 'oldUninstalled'; Write-IkMigrationRecord
    }
    InstallNew = {
        if (-not (Test-IkManifestEqual $migration.dataBefore @(Get-IkTreeManifest $dataDirectory))) { throw '旧卸载后用户数据变化，停止新安装并恢复旧程序；未自动覆盖数据。' }
        Assert-IkFileHash $InstallerPath $InstallerSha256
        Invoke-IkInstallerProcess $InstallerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=desktopicon',('/DIR="' + $TargetDirectory + '"'),('/LOG="' + (Join-Path $migration.root 'new-install.log') + '"'))
        $migration.record.phase = 'newInstalled'; Write-IkMigrationRecord
    }
    Verify = {
        $installed = Get-IkInstalledRegistration
        if (-not $installed -or ([IO.Path]::GetFullPath($installed.InstallLocation).TrimEnd('\', '/') -ne $TargetDirectory)) { throw '新安装卸载登记未指向目标目录。' }
        Assert-IkProductIdentity $TargetDirectory
        foreach ($entry in $bundleManifest.files) {
            $file = Get-IkManifestPath $TargetDirectory $entry.path
            Assert-IkFileHash $file $entry.sha256
            if ((Get-Item -LiteralPath $file).Length -ne $entry.length) { throw "发行文件长度不符：$($entry.path)" }
        }
        if (-not (Test-IkManifestEqual $migration.dataBefore @(Get-IkTreeManifest $dataDirectory))) { throw '启动前数据清单不一致；保留保护性快照，未自动覆盖。' }
        $shell = New-Object -ComObject WScript.Shell
        foreach ($shortcutPath in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'IK Music.lnk'),(Join-Path ([Environment]::GetFolderPath('Programs')) 'IK Music/IK Music.lnk'))) {
            if (-not (Test-Path -LiteralPath $shortcutPath)) { throw "新快捷方式缺失：$shortcutPath" }
            $shortcut = $shell.CreateShortcut($shortcutPath)
            if ($shortcut.TargetPath -ne (Join-Path $TargetDirectory 'yueyin_music.exe') -or $shortcut.WorkingDirectory -ne $TargetDirectory -or $shortcut.IconLocation -ne ((Join-Path $TargetDirectory 'ik.ico') + ',0')) { throw '新快捷方式的目标、工作目录或图标不一致。' }
        }
        $migration.record.remainingFiles = @(Get-IkTreeManifest $sourceDirectory)
        $migration.record.phase = 'verified'; Write-IkMigrationRecord
    }
    UninstallFailedNew = {
        $installed = Get-IkInstalledRegistration
        if (-not $installed) { return }
        if ([IO.Path]::GetFullPath($installed.InstallLocation).TrimEnd('\', '/') -ne $TargetDirectory) { throw '失败新包的卸载登记不是目标目录，拒绝猜测卸载。' }
        Assert-IkDirectoryPair $sourceDirectory $TargetDirectory
        Assert-IkProductIdentity $TargetDirectory
        $newUninstaller = Join-Path $TargetDirectory 'unins000.exe'
        if ([string]$installed.UninstallString -notmatch ('^"?' + [regex]::Escape($newUninstaller) + '"?(?:\s|$)')) { throw '失败新包的卸载命令不一致。' }
        Invoke-IkInstallerProcess $newUninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + (Join-Path $migration.root 'failed-new-uninstall.log') + '"'))
        if (Get-IkInstalledRegistration) { throw '失败新安装的登记未解除，停止自动回滚。' }
    }
    RestoreOld = {
        Assert-IkFileHash $RollbackInstallerPath $RollbackInstallerSha256
        Invoke-IkInstallerProcess $RollbackInstallerPath @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=desktopicon',('/DIR="' + $sourceDirectory + '"'),('/LOG="' + (Join-Path $migration.root 'rollback-install.log') + '"'))
        $restored = Get-IkInstalledRegistration
        if (-not $restored -or [IO.Path]::GetFullPath($restored.InstallLocation).TrimEnd('\', '/') -ne $sourceDirectory) { throw '回滚后的登记未回到旧路径。' }
        Assert-IkProductIdentity $sourceDirectory
        $migration.record.phase='rolledBack'; Write-IkMigrationRecord
    }
}
Invoke-IkMigrationTransaction -Actions $actions -OldInstallationRemoved { $migration.oldRemoved }
Write-Output "迁移与启动前核验完成：$TargetDirectory。用户数据保持原位；旧目录未登记内容保留。尚未自动启动应用。迁移记录：$migrationRoot"
